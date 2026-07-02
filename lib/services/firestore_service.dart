import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'authority_routing_service.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // ── Users collection ──────────────────────────────────────────────────────

  Future<void> createUserDocument(
    String uid,
    String email,
    String password,
    String role,
    String displayName,
  ) async {
    await _db.collection('users').doc(uid).set({
      'uid': uid,
      'email': email,
      'password': password,
      'role': role,
      'displayName': displayName,
      'createdAt': FieldValue.serverTimestamp(),
      'profileComplete': false,
    });

    // Also initialize the citizen profile with the password so it can be fetched immediately
    if (role == 'citizen') {
      await _db.collection('citizen_profiles').doc(uid).set({
        'uid': uid,
        'email': email,
        'password': password,
        'fullName': displayName,
      }, SetOptions(merge: true));
    }
  }

  Future<Map<String, dynamic>?> getUserDocument(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<List<Map<String, dynamic>>> getActiveReportsByStatus(
      String status) async {
    final query = await _db
        .collection('sos_reports')
        .where('status', isEqualTo: status)
        .get();
    return query.docs.map((d) => d.data()).toList();
  }

  // ── Global Notifications ───────────────────────────────────────────────────

  Stream<QuerySnapshot> streamGlobalNotifications() {
    return _db
        .collection('global_notifications')
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  Future<void> declareGlobalNotification(String title, String message, String type) async {
    await _db.collection('global_notifications').add({
      'title': title,
      'message': message,
      'fullDetails': message,
      'type': type,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  Future<bool> checkEmailExists(String email) async {
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim())
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  Future<String?> getUserRole(String uid) async {
    final data = await getUserDocument(uid);
    return data?['role'] as String?;
  }

  Future<void> updateUserDocument(String uid, Map<String, dynamic> data) async {
    await _db.collection('users').doc(uid).update(data);
  }

  // ── Role profiles ──────────────────────────────────────────────────────────

  Future<void> createCitizenProfile(
      String uid, Map<String, dynamic> data) async {
    await _db.collection('citizen_profiles').doc(uid).set({
      ...data,
      'uid': uid,
    }, SetOptions(merge: true));
    // Mark profile as complete in the users doc
    await updateUserDocument(uid, {'profileComplete': true});
  }

  Future<void> createVolunteerProfile(
      String uid, Map<String, dynamic> data) async {
    await _db.collection('volunteer_profiles').doc(uid).set({
      ...data,
      'uid': uid,
      'sigapMataPoints': 1250,
      'isActive': false,
    }, SetOptions(merge: true));
    await updateUserDocument(uid, {'profileComplete': true});
  }

  Future<void> createOfficerProfile(
      String uid, Map<String, dynamic> data) async {
    await _db.collection('officer_profiles').doc(uid).set({
      ...data,
      'uid': uid,
    }, SetOptions(merge: true));
    await updateUserDocument(uid, {'profileComplete': true});
  }

  Future<Map<String, dynamic>?> getCitizenProfile(String uid) async {
    final doc = await _db.collection('citizen_profiles').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<Map<String, dynamic>?> getVolunteerProfile(String uid) async {
    final doc = await _db.collection('volunteer_profiles').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<Map<String, dynamic>?> getOfficerProfile(String uid) async {
    final doc = await _db.collection('officer_profiles').doc(uid).get();
    return doc.exists ? doc.data() : null;
  }

  Future<void> updateVolunteerActiveStatus(String uid, bool isActive) async {
    await _db
        .collection('volunteer_profiles')
        .doc(uid)
        .update({'isActive': isActive});
  }

  Future<void> updateVolunteerLocation(String uid, double lat, double lng) async {
    await _db
        .collection('volunteer_profiles')
        .doc(uid)
        .update({
      'currentLat': lat,
      'currentLng': lng,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── SOS Reports ─────────────────────────────────────────────────────────────

  /// Create a new SOS report and return the document ID.
  /// Automatically computes and writes the routedAuthority field.
  Future<String> createSOSReport(Map<String, dynamic> data) async {
    final incidentType = data['type'] as String? ?? '';
    final authorityData = AuthorityRoutingService.instance.getAuthorityData(incidentType);

    final docRef = await _db.collection('sos_reports').add({
      ...data,
      'routedAuthority': authorityData,
    });

    final reporterId = data['reporterId'] as String?;
    if (reporterId != null) {
      await _db.collection('citizen_profiles').doc(reporterId).set({
        'safetyStatus': 'Perlu Bantuan',
      }, SetOptions(merge: true));
    }

    return docRef.id;
  }

  /// Stream active SOS reports (real-time) for the Volunteer Task Board.
  /// Only reports with status 'active' are returned, ordered newest-first.
  Stream<QuerySnapshot> streamActiveSOSReports() {
    return _db
        .collection('sos_reports')
        .where('status', isEqualTo: 'active')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  /// Stream the current user's active SOS reports (for citizen cancellation UI).
  /// Single-field filter only to avoid composite index requirements.
  /// Status filtering (isEqualTo 'active') is done client-side in the widget.
  Stream<QuerySnapshot> streamMyActiveSOSReports(String uid) {
    return _db
        .collection('sos_reports')
        .where('reporterId', isEqualTo: uid)
        .snapshots();
  }

  /// Update any fields on an SOS report document.
  Future<void> updateSOSReport(String docId, Map<String, dynamic> data) async {
    await _db.collection('sos_reports').doc(docId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Cancel an SOS report (citizen side — false alarm).
  Future<void> cancelSOSReport(String docId, String reason) async {
    final reportDoc = await _db.collection('sos_reports').doc(docId).get();
    final reporterId = reportDoc.data()?['reporterId'] as String?;

    await _db.collection('sos_reports').doc(docId).update({
      'status': 'cancelled',
      'cancelReason': reason,
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (reporterId != null) {
      await _db.collection('citizen_profiles').doc(reporterId).set({
        'safetyStatus': 'Selamat',
      }, SetOptions(merge: true));
    }
  }

  /// Volunteer accepts / responds to an SOS report.
  Future<void> respondToSOS(String docId, String volunteerId, String volunteerName) async {
    print('respondToSOS called with docId: $docId, volunteerId: $volunteerId');
    try {
      await _db.collection('sos_reports').doc(docId).update({
        'status': 'responded',
        'responderId': volunteerId,
        'responderName': volunteerName,
        'respondedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('respondToSOS successful');
    } catch (e) {
      print('respondToSOS error: $e');
      rethrow;
    }
  }

  /// Volunteer declines an SOS report so it won't appear on their task board.
  Future<void> declineSOSReport(String docId, String volunteerId) async {
    await _db.collection('sos_reports').doc(docId).update({
      'declinedBy': FieldValue.arrayUnion([volunteerId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Update volunteer mission checklist progress
  Future<void> updateSOSChecklist(String docId, Map<String, dynamic> checklist) async {
    await _db.collection('sos_reports').doc(docId).update({
      'volunteerChecklist': checklist,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Get a single SOS report by ID.
  Future<Map<String, dynamic>?> getSOSReport(String docId) async {
    final doc = await _db.collection('sos_reports').doc(docId).get();
    return doc.exists ? {'id': doc.id, ...doc.data()!} : null;
  }

  // ── Officer SOS Monitoring ────────────────────────────────────────────────

  /// Officer: stream ALL SOS reports that are active or responded (need monitoring).
  /// Ordered by creation time newest-first. Requires a Firestore composite index on
  /// (status, createdAt desc) — or fall back to client-side sorting without orderBy.
  Stream<QuerySnapshot> streamAllActiveSOSReportsForOfficer() {
    return _db.collection('sos_reports').where('status', whereIn: [
      'active',
      'responded'
    ]).snapshots(); // Sorted client-side to avoid composite index requirement
  }

  /// Officer: stream SOS reports that have been resolved (for history view).
  Stream<QuerySnapshot> streamResolvedSOSReports() {
    return _db
        .collection('sos_reports')
        .where('status', isEqualTo: 'resolved')
        .snapshots(); // Sorted client-side
  }

  /// Officer resolves a citizen SOS report. This automatically removes it from
  /// the volunteer task board (which only streams 'active' status) and from the
  /// officer's active monitoring list.
  Future<void> resolveSOSReportByOfficer(String docId) async {
    final reportDoc = await _db.collection('sos_reports').doc(docId).get();
    final reporterId = reportDoc.data()?['reporterId'] as String?;

    await _db.collection('sos_reports').doc(docId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (reporterId != null) {
      await _db.collection('citizen_profiles').doc(reporterId).set({
        'safetyStatus': 'Berpindah',
      }, SetOptions(merge: true));
    }
  }

  // ── Disaster Zones ────────────────────────────────────────────────────────

  /// Create a new disaster zone in Firestore.
  Future<String> createDisasterZone(Map<String, dynamic> data) async {
    final docRef = await _db.collection('disaster_zones').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return docRef.id;
  }

  /// Stream all declared disaster zones in real time.
  Stream<QuerySnapshot> streamDisasterZones() {
    return _db.collection('disaster_zones').snapshots();
  }

  /// Stream active or responded SOS reports for a specific citizen.
  /// NOTE: We intentionally do NOT filter by status in Firestore here because
  /// the compound index (reporterId + status) may not be deployed. Status
  /// filtering is done client-side in the widget to guarantee correctness.
  Stream<QuerySnapshot> streamMyActiveAndRespondedSOSReports(String uid) {
    return _db
        .collection('sos_reports')
        .where('reporterId', isEqualTo: uid)
        .snapshots();
  }

  /// Check if a citizen already has an active or responded SOS report.
  Future<bool> hasActiveSOS(String uid) async {
    final snapshot = await _db
        .collection('sos_reports')
        .where('reporterId', isEqualTo: uid)
        .where('status', whereIn: ['active', 'responded'])
        .get();
    return snapshot.docs.isNotEmpty;
  }

  /// Request backup/reinforcements for a specific SOS report.
  Future<void> updateSOSReportBackupRequest(
      String docId, bool needBackup) async {
    await _db.collection('sos_reports').doc(docId).update({
      'needBackup': needBackup,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Volunteer resolves a citizen SOS report with completion details.
  Future<void> resolveSOSReportByVolunteer(String docId, {Map<String, dynamic>? completionDetails}) async {
    final reportDoc = await _db.collection('sos_reports').doc(docId).get();
    final reporterId = reportDoc.data()?['reporterId'] as String?;

    await _db.collection('sos_reports').doc(docId).update({
      'status': 'resolved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      if (completionDetails != null) 'completionDetails': completionDetails,
    });

    if (reporterId != null) {
      await _db.collection('citizen_profiles').doc(reporterId).set({
        'safetyStatus': 'Selamat',
      }, SetOptions(merge: true));
    }
  }

  // ── Claims (Tuntutan) ──────────────────────────────────────────────────────

  Future<void> submitClaim(Map<String, dynamic> data) async {
    await _db.collection('claims').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> streamClaimsForCitizen(String citizenId) {
    return _db
        .collection('claims')
        .where('citizenId', isEqualTo: citizenId)
        .snapshots();
  }

  Stream<QuerySnapshot> streamPendingClaims() {
    return _db
        .collection('claims')
        .where('status', isEqualTo: 'submitted')
        .snapshots();
  }

  Stream<QuerySnapshot> streamClaimsForOfficerReview() {
    return _db
        .collection('claims')
        .where('status', whereIn: ['submitted', 'under_review', 'expired']).snapshots();
  }

  Future<void> updateClaimStatus(
    String claimId,
    String status, {
    String? reason,
    String? officerId,
    DateTime? infoDeadline,
  }) async {
    await _db.collection('claims').doc(claimId).update({
      'status': status,
      if (status == 'rejected' && reason != null) 'rejectReason': reason,
      if (status == 'under_review' && reason != null)
        'infoRequestReason': reason,
      if (infoDeadline != null) 'infoDeadline': Timestamp.fromDate(infoDeadline),
      if (officerId != null) 'reviewedBy': officerId,
      'reviewedAt': FieldValue.serverTimestamp(),
      if (status == 'approved') ...{
        'rejectReason': FieldValue.delete(),
        'infoRequestReason': FieldValue.delete(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<int> bulkApproveClaimsByZone(String location,
      {String? officerId}) async {
    final pendingClaims = await _db
        .collection('claims')
        .where('status', isEqualTo: 'submitted')
        .get();

    if (pendingClaims.docs.isEmpty) return 0;

    final targetZone = location.toLowerCase().trim();
    final matchingDocs = pendingClaims.docs.where((doc) {
      final data = doc.data();
      final claimLocation = (data['location'] as String? ?? '').toLowerCase().trim();
      return claimLocation == targetZone ||
          claimLocation.contains(targetZone) ||
          targetZone.contains(claimLocation);
    }).toList();

    if (matchingDocs.isEmpty) return 0;

    final batch = _db.batch();
    for (final doc in matchingDocs) {
      batch.update(doc.reference, {
        'status': 'approved',
        'rejectReason': FieldValue.delete(),
        'infoRequestReason': FieldValue.delete(),
        if (officerId != null) 'reviewedBy': officerId,
        'reviewedAt': FieldValue.serverTimestamp(),
        'bulkApproved': true,
        'bulkApprovedZone': location,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
    return matchingDocs.length;
  }

  Future<void> deleteClaim(String claimId) async {
    await _db.collection('claims').doc(claimId).delete();
  }

  /// Citizen cancels their own pending claim.
  Future<void> cancelClaim(String claimId) async {
    await _db.collection('claims').doc(claimId).update({
      'status': 'cancelled',
      'cancelledAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Generic file upload to Firebase Storage. Falls back to base64 on failure.
  Future<String> uploadFile(File imageFile, String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      final bytes = await imageFile.readAsBytes();
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      final snapshot = await uploadTask;
      if (snapshot.state == TaskState.success) {
        return await snapshot.ref.getDownloadURL();
      } else {
        throw Exception('Upload did not succeed. State: ${snapshot.state}');
      }
    } catch (e) {
      debugPrint('Firebase Storage upload failed: $e. Falling back to Base64.');
      final bytes = await imageFile.readAsBytes();
      return 'data:image/jpeg;base64,${base64Encode(bytes)}';
    }
  }

  /// Backward-compatible alias for evidence upload.
  Future<String> uploadClaimEvidence(File imageFile, String citizenId) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}_$citizenId.jpg';
    return uploadFile(imageFile, 'claims_evidence/$fileName');
  }

  // ── Donation Campaigns ─────────────────────────────────────────────────────

  Future<void> createCampaign(Map<String, dynamic> data) async {
    await _db.collection('campaigns').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateCampaign(String campaignId, Map<String, dynamic> data) async {
    await _db.collection('campaigns').doc(campaignId).update({
      ...data,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> closeCampaign(String campaignId) async {
    await _db.collection('campaigns').doc(campaignId).update({
      'status': 'closed',
      'closedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Permanently delete a campaign document.
  Future<void> deleteCampaign(String campaignId) async {
    await _db.collection('campaigns').doc(campaignId).delete();
  }

  Stream<QuerySnapshot> streamActiveCampaigns() {
    return _db.collection('campaigns').snapshots();
  }

  // ── Donations ──────────────────────────────────────────────────────────────

  Stream<QuerySnapshot> streamUserDonations(String citizenId) {
    return _db
        .collection('donations')
        .where('citizenId', isEqualTo: citizenId)
        .snapshots();
  }

  Future<void> submitDonation(String campaignId,
      Map<String, dynamic> donationData, double amount) async {
    try {
      final campaignRef = _db.collection('campaigns').doc(campaignId);
      
      // Check if campaign exists
      final campaignDoc = await campaignRef.get();
      if (!campaignDoc.exists) {
        throw Exception("Campaign does not exist!");
      }

      // Get current amount
      final currentAmount = (campaignDoc.data()?['currentAmount'] as num?)?.toDouble() ?? 0.0;
      
      // Use transaction for atomic update
      await _db.runTransaction((transaction) async {
        // Update campaign current amount
        transaction.update(campaignRef, {
          'currentAmount': currentAmount + amount,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        
        // Add donation document with proper ID
        final newDonationRef = _db.collection('donations').doc();
        donationData['id'] = newDonationRef.id;
        donationData['createdAt'] = FieldValue.serverTimestamp();
        transaction.set(newDonationRef, donationData);
      });
      
      debugPrint('✅ Donation submitted successfully for campaign: $campaignId');
    } catch (e) {
      debugPrint('❌ submitDonation error: $e');
      rethrow;
    }
  }
  // ── Volunteer Tasks ────────────────────────────────────────────────────────

  Future<void> createVolunteerTask(Map<String, dynamic> data) async {
    await _db.collection('volunteer_tasks').add({
      ...data,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> streamVolunteerTasks() {
    return _db.collection('volunteer_tasks').snapshots();
  }

  Stream<QuerySnapshot> streamActiveVolunteerTasks() {
    return _db.collection('volunteer_tasks').snapshots();
  }

  Future<void> updateVolunteerTask(String taskId, Map<String, dynamic> updates) async {
    print('updateVolunteerTask called: taskId=$taskId, updates=$updates');
    try {
      await _db.collection('volunteer_tasks').doc(taskId).update({
        ...updates,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      print('updateVolunteerTask successful');
    } catch (e) {
      print('updateVolunteerTask error: $e');
      rethrow;
    }
  }

  Future<void> updateVolunteerSquadAssignment(String volunteerId, String squadName, String squadId) async {
    await _db.collection('volunteer_profiles').doc(volunteerId).update({
      'assignedSquad': squadName,
      'assignedSquadId': squadId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<QuerySnapshot> streamAllVolunteerTasks() {
    return _db.collection('volunteer_tasks').snapshots();
  }



  // ── Volunteer Dispatch ────────────────────────────────────────────────────

  /// Stream all volunteers who have set themselves as active/available.
  Stream<QuerySnapshot> streamActiveVolunteers() {
    return _db
        .collection('volunteer_profiles')
        .where('isActive', isEqualTo: true)
        .snapshots();
  }

  /// Officer dispatches a specific volunteer to an SOS report.
  Future<void> dispatchVolunteerToSOS(
    String sosDocId,
    String volunteerId,
    String volunteerName,
  ) async {
    await _db.collection('sos_reports').doc(sosDocId).update({
      'status': 'responded',
      'responderId': volunteerId,
      'responderName': volunteerName,
      'respondedAt': FieldValue.serverTimestamp(),
      'dispatchedByOfficer': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Save or refresh a user's FCM device token.
  Future<void> saveFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set({
      'fcmToken': token,
      'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  // Add to FirestoreService class
  Future<List<Map<String, dynamic>>> getAvailableSquads() async {
    try {
      final snapshot = await _db.collection('volunteer_tasks').get();
      final Set<String> uniqueSquads = {};
      final List<Map<String, dynamic>> squads = [];
      
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final squadName = data['squadName'] as String?;
        final squadId = data['squadId'] as String?;
        
        if (squadName != null && squadName.isNotEmpty && !uniqueSquads.contains(squadName)) {
          uniqueSquads.add(squadName);
          squads.add({
            'name': squadName,
            'id': squadId ?? squadName.replaceAll(' ', '_').toLowerCase(),
            'description': _getSquadDescription(squadName),
          });
        }
      }
      
      // Also add predefined squads
      final predefinedSquads = [
        {'name': 'Skuad Alpha (Penyelamat)', 'id': 'skuad_alpha_penyelamat', 'description': 'Pasukan penyelamat utama'},
        {'name': 'Skuad Bravo (Pembersihan)', 'id': 'skuad_bravo_pembersihan', 'description': 'Pasukan pembersihan dan sanitasi'},
        {'name': 'Skuad Charlie (Logistik)', 'id': 'skuad_charlie_logistik', 'description': 'Pasukan logistik dan bekalan'},
        {'name': 'Skuad Delta (Perubatan)', 'id': 'skuad_delta_perubatan', 'description': 'Pasukan perubatan dan kesihatan'},
        {'name': 'Skuad Echo (Dapur Jalanan)', 'id': 'skuad_echo_dapur', 'description': 'Pasukan dapur dan makanan'},
        {'name': 'Skuad Foxtrot (Komunikasi)', 'id': 'skuad_foxtrot_komunikasi', 'description': 'Pasukan komunikasi dan maklumat'},
      ];
      
      for (final squad in predefinedSquads) {
        if (!uniqueSquads.contains(squad['name'])) {
          squads.add(squad);
        }
      }
      
      return squads;
    } catch (e) {
      print('Error getting squads: $e');
      return [];
    }
  }

  String _getSquadDescription(String squadName) {
    if (squadName.toLowerCase().contains('alpha')) return 'Pasukan penyelamat dan tindakan pantas';
    if (squadName.toLowerCase().contains('bravo')) return 'Pasukan pembersihan dan sanitasi';
    if (squadName.toLowerCase().contains('charlie')) return 'Pasukan logistik dan bekalan';
    if (squadName.toLowerCase().contains('delta')) return 'Pasukan perubatan dan kesihatan';
    if (squadName.toLowerCase().contains('echo')) return 'Pasukan dapur dan makanan';
    if (squadName.toLowerCase().contains('foxtrot')) return 'Pasukan komunikasi dan maklumat';
    return 'Skuad bantuan bencana';
  }

  // Add to FirestoreService class
  Future<void> assignVolunteerToSquad(String volunteerId, String squadName, String squadId) async {
    await _db.collection('volunteer_profiles').doc(volunteerId).update({
      'assignedSquad': squadName,
      'assignedSquadId': squadId,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Claim Validation Helpers ──────────────────────────────────────────────

  /// Check if a citizen (by IC number) already has an approved claim within 30 days.
  /// Returns the list of matching approved claim documents.
  Future<List<Map<String, dynamic>>> checkDuplicateICInZone(
      String icNumber) async {
    if (icNumber.trim().isEmpty || icNumber == '-') return [];
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    try {
      final result = await _db
          .collection('claims')
          .where('icNumber', isEqualTo: icNumber.trim())
          .where('status', isEqualTo: 'approved')
          .get();
      return result.docs
          .map((d) => {'id': d.id, ...d.data()})
          .where((d) {
            final ts = d['createdAt'];
            if (ts == null) return false;
            final date = ts is Timestamp ? ts.toDate() : null;
            return date != null && date.isAfter(cutoff);
          })
          .toList();
    } catch (_) {
      // Fail silently if composite index is not yet created
      return [];
    }
  }

  // ── Volunteer Task Helpers ─────────────────────────────────────────────────

  /// Volunteer accepts a task — appends their UID to acceptedVolunteerUIDs.
  Future<void> acceptVolunteerTask(String taskId, String volunteerId) async {
    await _db.collection('volunteer_tasks').doc(taskId).update({
      'acceptedVolunteerUIDs': FieldValue.arrayUnion([volunteerId]),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Release all volunteers assigned to a completed task.
  Future<void> releaseVolunteersFromTask(
      String taskId, List<String> volunteerUIDs) async {
    final batch = _db.batch();
    for (final uid in volunteerUIDs) {
      final ref = _db.collection('volunteer_profiles').doc(uid);
      batch.update(ref, {
        'currentTaskId': FieldValue.delete(),
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_db.collection('volunteer_tasks').doc(taskId), {
      'status': 'Selesai Tugas',
      'progress': 1.0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// Add SIGAP Mata points to a volunteer's profile
  Future<void> addVolunteerPoints(String uid, int points) async {
    await _db.collection('volunteer_profiles').doc(uid).update({
      'sigapMataPoints': FieldValue.increment(points),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Certificates ─────────────────────────────────────────────────────────

  Future<void> redeemCertificate(String uid, String certTitle, int costPoints) async {
    final profileRef = _db.collection('volunteer_profiles').doc(uid);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(profileRef);
      if (!snapshot.exists) throw Exception("Profile does not exist!");
      final currentPoints = snapshot.data()?['sigapMataPoints'] as int? ?? 0;
      if (currentPoints < costPoints) {
        throw Exception("Mata tidak mencukupi untuk menebus sijil ini.");
      }
      
      transaction.update(profileRef, {
        'sigapMataPoints': currentPoints - costPoints,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final certRef = profileRef.collection('certificates').doc();
      transaction.set(certRef, {
        'id': certRef.id,
        'title': certTitle,
        'redeemedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Stream<QuerySnapshot> streamVolunteerCertificates(String uid) {
    return _db
        .collection('volunteer_profiles')
        .doc(uid)
        .collection('certificates')
        .orderBy('redeemedAt', descending: true)
        .snapshots();
  }
}