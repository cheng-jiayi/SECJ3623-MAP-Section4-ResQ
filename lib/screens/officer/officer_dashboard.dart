import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../core/constants/app_strings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/sos_report_model.dart';
import '../../models/claim_model.dart';
import '../../models/campaign_model.dart';
import '../../models/volunteer_task_model.dart';
import '../../models/volunteer_profile_model.dart';
import '../../services/authority_routing_service.dart';
import '../../services/firestore_service.dart';
import '../../services/awanis_service.dart';
import '../../services/pdf_report_service.dart';
import 'officer_faq_screen.dart';

import '../../widgets/common/sigap_app_bar.dart';

class OfficerDashboard extends StatefulWidget {
  const OfficerDashboard({super.key});

  @override
  State<OfficerDashboard> createState() => _OfficerDashboardState();
}

class _OfficerDashboardState extends State<OfficerDashboard> {
  int _currentIndex = 0;
  final List<String> _disasterZoneNames = [];
  Stream<QuerySnapshot>? _disasterZonesStream;
  String? _profileImageUrl;

  final _firestoreService = FirestoreService();

  final CameraPosition _kInitialPosition = const CameraPosition(
    target: LatLng(3.1390, 101.6869), // KL Center
    zoom: 8.0,
  );

  // Filters State for Krisis Tab
  String _filterUrgency = 'Semua';
  String _filterType = 'Semua';
  String _filterDuration = 'Semua';

  // Disaster Zone State
  bool _isSelectingDisasterZone = false;
  LatLng? _selectedDisasterEpicenter;
  double _disasterRadius = 5000.0; // meters
  String _disasterType = 'Banjir'.tr();
  final TextEditingController _disasterNameController = TextEditingController();
  final List<Circle> _disasterZones = [];
  String? _selectedBulkClaimZone;
  // IDs of claims checked in the bulk approval panel
  final Set<String> _bulkSelectedClaimIds = {};
  // Guard sets — prevent duplicate Firestore writes on re-render
  final Set<String> _autoRejectedClaimIds = {};
  final Set<String> _autoExpiredClaimIds = {};
  // Duplicate IC check cache: claimId -> hasDuplicate
  final Map<String, bool> _duplicateICCache = {};
  // Whether photo review was confirmed in bulk panel
  bool _photoReviewConfirmed = false;

  // Claim filtering state
  String _selectedClaimStatusFilter = 'Semua';
  String _selectedClaimZoneFilter = 'Semua';

  // Live SOS reports from Firestore (replaces _mockIncidents)
  List<SosReportModel> _activeReports = [];

  StreamSubscription<QuerySnapshot>? _volunteersSubscription;
  List<VolunteerProfileModel> _activeVolunteers = [];

  final List<Map<String, dynamic>> _awanisOfficerMessages = [];
  bool _isAwanisLoading = false;
  final TextEditingController _awanisMsgCtrl = TextEditingController();

  void _listenToActiveVolunteers() {
    _volunteersSubscription?.cancel();
    _volunteersSubscription =
        _firestoreService.streamActiveVolunteers().listen((snapshot) {
      if (mounted) {
        setState(() {
          _activeVolunteers = snapshot.docs.map((doc) {
            return VolunteerProfileModel.fromMap(
                doc.id, doc.data() as Map<String, dynamic>);
          }).toList();
        });
      }
    });
  }

  @override
  void dispose() {
    _disasterNameController.dispose();
    _volunteersSubscription?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _awanisOfficerMessages.add({
      'isBot': true,
      'text':
          'Hai Tuan/Puan Pegawai! Saya AWANIS, pembantu AI pusat kawalan anda. Boleh saya bantu paparkan status SOS, sukarelawan, atau analisa semasa?'
              .tr()
    });
    _disasterZonesStream = _firestoreService.streamDisasterZones();
    _loadOfficerData();
    _listenToActiveVolunteers();
  }

  Future<void> _loadOfficerData() async {
    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) {
      try {
        final data = await _firestoreService.getOfficerProfile(state.uid);
        if (data != null && mounted) {
          setState(() {
            _profileImageUrl = data['profileImageUrl'] as String?;
          });
        }
      } catch (e) {
        debugPrint('Error loading officer data: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    context.locale;
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final name = state is AuthAuthenticated ? state.displayName : '';
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: SigapAppBar(
            title: AppStrings.appName,
            showLogout: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_active_rounded,
                    color: AppColors.warning),
                onPressed: () => context.push(AppRoutes.officerNotifications),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline_rounded),
                onPressed: () => context.push(AppRoutes.officerProfile),
              ),
            ],
          ),
          body: _buildBody(name),
          bottomNavigationBar: _buildBottomAppBar(),
        );
      },
    );
  }

  Widget _buildBody(String name) {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab(name);
      case 1:
        return _buildCrisisTab();
      case 2:
        return _buildVolunteerTab();
      case 3:
        return _buildAwanisTab();
      case 4:
        return _buildClaimsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ─── BOTTOM APP BAR ───────────────────────────────────────────────
  Widget _buildBottomAppBar() {
    return BottomAppBar(
      shape: const CircularNotchedRectangle(),
      notchMargin: 8.0,
      color: AppColors.surface,
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: SizedBox(
        height: 65,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.dashboard_rounded, 'navHome'.tr(), 0),
            _navItem(Icons.warning_amber_rounded, 'navCrisis'.tr(), 1),
            _navItem(Icons.group_rounded, 'navSquad'.tr(), 2),
            _navItem(Icons.smart_toy_rounded, 'navAwanis'.tr(), 3),
            _navItem(Icons.receipt_long_rounded, 'navClaims'.tr(), 4),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final color =
        isSelected ? AppColors.officerAccent : AppColors.textSecondary;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: color)),
          ],
        ),
      ),
    );
  }

  // ─── UTAMA (HOME) TAB ─────────────────────────────────────────────
  Widget _buildHomeTab(String name) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCommandCard(name),
        const SizedBox(height: 16),
        _buildStatsRow(),
        const SizedBox(height: 24),
        _sectionTitle('Modul & Ciri Tambahan'.tr()),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
                child: _moduleCard('Laporan Analitik'.tr(),
                    Icons.analytics_rounded, AppColors.primary)),
            const SizedBox(width: 12),
            Expanded(
                child: _moduleCard('Modul Tambahan'.tr(),
                    Icons.extension_rounded, Colors.teal)),
          ],
        ),
        const SizedBox(height: 24),
        _sectionTitle('Kempen Derma Aktif'.tr()),
        const SizedBox(height: 12),
        StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.streamActiveCampaigns(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final docs = snapshot.hasData ? snapshot.data!.docs.toList() : [];
            if (docs.isEmpty) {
              return Container(
                height: 100,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Text('Tiada kempen aktif'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary)),
              );
            }
            docs.sort((a, b) {
              final aTime =
                  (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              final bTime =
                  (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

            return SizedBox(
              height: 262,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final campaign = CampaignModel.fromMap(docs[index].id, data);
                  return Padding(
                    padding: const EdgeInsets.only(right: 16.0),
                    child: SizedBox(
                      width: 320,
                      child: _donationCampaignCard(campaign),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _createCampaignDialog,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Cipta Kempen Baru'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 24),
        _sectionTitle('Soalan Lazim (FAQ)'.tr()),
        const SizedBox(height: 12),
        _faqCard('Panduan & FAQ Pegawai'.tr()),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _moduleCard(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(height: 12),
          Text(title,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _faqCard(String title) {
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OfficerFAQScreen())),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppColors.textPrimary)),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  // ─── KRISIS (SOS & MAP) TAB ───────────────────────────────────────
  Widget _buildCrisisTab() {
    return StreamBuilder(
      stream: _disasterZonesStream,
      builder: (context, zoneSnapshot) {
        if (zoneSnapshot.hasData) {
          _disasterZones.clear();
          _disasterZoneNames.clear();
          for (final doc in zoneSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final latRaw = data['epicenterLat'];
            final lngRaw = data['epicenterLng'];
            final radRaw = data['radius'];
            // Skip documents with missing or invalid coordinate fields
            if (latRaw == null || lngRaw == null || radRaw == null) continue;
            final lat = (latRaw as num).toDouble();
            final lng = (lngRaw as num).toDouble();
            final rad = (radRaw as num).toDouble();
            final zoneName = (data['name'] as String? ?? '').trim();
            _disasterZones.add(
              Circle(
                circleId: CircleId(doc.id),
                center: LatLng(lat, lng),
                radius: rad,
                fillColor: AppColors.danger.withValues(alpha: 0.2),
                strokeColor: AppColors.danger,
                strokeWidth: 2,
              ),
            );
            if (zoneName.isNotEmpty) _disasterZoneNames.add(zoneName);
          }
        }

        return StreamBuilder(
          stream: _firestoreService.streamAllActiveSOSReportsForOfficer(),
          builder: (context, snapshot) {
            // Update local state from stream
            if (snapshot.hasData) {
              _activeReports = snapshot.data!.docs
                  .map((doc) => SosReportModel.fromDocument(doc))
                  .toList();
              // Sort locally: newest first
              _activeReports.sort((a, b) {
                final aTime = a.createdAt ?? DateTime(2000);
                final bTime = b.createdAt ?? DateTime(2000);
                return bTime.compareTo(aTime);
              });
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Heatmap Krisis'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                // Declare Disaster Zone button / selection UI
                SizedBox(
                  width: double.infinity,
                  child: _isSelectingDisasterZone
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_selectedDisasterEpicenter == null)
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                    color: AppColors.warning
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                    border:
                                        Border.all(color: AppColors.warning)),
                                child: Text(
                                    'Sila tap pada peta untuk memilih pusat zon darurat.'
                                        .tr(),
                                    style: GoogleFonts.inter(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13)),
                              )
                            else ...[
                              Text(
                                  'zoneRadiusKm'.tr(args: [
                                    (_disasterRadius / 1000).toString()
                                  ]),
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                              Slider(
                                value: _disasterRadius,
                                min: 1000,
                                max: 20000,
                                divisions: 19,
                                activeColor: AppColors.danger,
                                label: '${_disasterRadius / 1000} km',
                                onChanged: (val) {
                                  setState(() {
                                    _disasterRadius = val;
                                  });
                                },
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                isExpanded: true,
                                initialValue: _disasterType,
                                decoration: InputDecoration(
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    labelText: 'Jenis Bencana'.tr(),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 8)),
                                items: [
                                  'Banjir'.tr(),
                                  'Tanah Runtuh'.tr(),
                                  'Kebakaran'.tr(),
                                  'Lain-lain'.tr()
                                ]
                                    .map((t) => DropdownMenuItem(
                                        value: t, child: Text(t)))
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() => _disasterType = val);
                                  }
                                },
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _disasterNameController,
                                decoration: InputDecoration(
                                    labelText: 'Nama / Butiran Zon'.tr(),
                                    hintText:
                                        'Contoh: Banjir Kilat Seksyen 7'.tr(),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 12)),
                                maxLines: 1,
                              ),
                            ],
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () {
                                      setState(() {
                                        _isSelectingDisasterZone = false;
                                        _selectedDisasterEpicenter = null;
                                        _disasterRadius = 5000.0;
                                        _disasterNameController.clear();
                                      });
                                    },
                                    child: Text('Batal'.tr()),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed:
                                        _selectedDisasterEpicenter == null ||
                                                _disasterNameController.text
                                                    .trim()
                                                    .isEmpty
                                            ? null
                                            : _confirmDisasterZone,
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.danger),
                                    child: Text('Teruskan'.tr(),
                                        style: TextStyle(color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        )
                      : ElevatedButton.icon(
                          onPressed: _declareDisasterZone,
                          icon: const Icon(Icons.campaign_rounded, size: 18),
                          label: Text('Isytihar Darurat (Zon Bencana)'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.danger,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                ),
                // Filter row
                if (!_isSelectingDisasterZone)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterDropdown(
                          label: 'Tahap'.tr(),
                          value: _filterUrgency,
                          items: [
                            'Semua',
                            SosReportModel.urgencyKritikal,
                            SosReportModel.urgencyTinggi,
                            SosReportModel.urgencySedang,
                            SosReportModel.urgencyRendah,
                          ],
                          onChanged: (v) => setState(() => _filterUrgency = v!),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterDropdown(
                          label: 'Jenis'.tr(),
                          value: _filterType,
                          items: [
                            'Semua',
                            'Banjir'.tr(),
                            'Tanah Runtuh'.tr(),
                            'Kebakaran'.tr(),
                            'Perubatan'.tr(),
                            'Orang Hilang'.tr(),
                          ],
                          onChanged: (v) => setState(() => _filterType = v!),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterDropdown(
                          label: 'Masa'.tr(),
                          value: _filterDuration,
                          items: [
                            'Semua',
                            '< 1 Hari'.tr(),
                            '< 3 Hari'.tr(),
                            '> 3 Hari'.tr(),
                          ],
                          onChanged: (v) =>
                              setState(() => _filterDuration = v!),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                // Google Maps
                Container(
                  height: 300,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E3DF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: _isSelectingDisasterZone
                            ? AppColors.danger
                            : AppColors.divider,
                        width: _isSelectingDisasterZone ? 2 : 1),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: _kInitialPosition,
                        onMapCreated: (_) {},
                        myLocationEnabled: true,
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                        zoomControlsEnabled: true,
                        markers:
                            _buildMarkersFromReports(_getFilteredReports()),
                        circles: _buildCircles(),
                        onTap: (LatLng location) {
                          if (_isSelectingDisasterZone) {
                            setState(() {
                              _selectedDisasterEpicenter = location;
                            });
                          }
                        },
                      ),
                      Positioned(
                        top: 12,
                        right: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                              color: Colors.black87,
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                      color: AppColors.danger,
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('Siaran Langsung'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _sectionTitle('Insiden Aktif & Penyelesaian'.tr()),
                    InkWell(
                      onTap: _showHistoryDialog,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Text(
                          'History'.tr(),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.officerAccent,
                            decoration: TextDecoration.underline,
                            decorationColor: AppColors.officerAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Stream loading / error / empty states
                if (snapshot.connectionState == ConnectionState.waiting)
                  const Center(
                      child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: CircularProgressIndicator(
                        color: AppColors.officerAccent),
                  ))
                else if (snapshot.hasError)
                  _buildFirestoreError(snapshot.error.toString())
                else
                  _buildIncidentList(_getFilteredReports()),
                const SizedBox(height: 80),
              ],
            );
          },
        );
      },
    );
  }

  List<SosReportModel> _getFilteredReports() {
    var reports = List<SosReportModel>.from(_activeReports);

    if (_filterUrgency != 'Semua') {
      reports = reports.where((r) => r.urgency == _filterUrgency).toList();
    }
    if (_filterType != 'Semua') {
      reports = reports.where((r) => r.type == _filterType).toList();
    }
    if (_filterDuration != 'Semua') {
      final now = DateTime.now();
      reports = reports.where((r) {
        if (r.createdAt == null) return true;
        final diff = now.difference(r.createdAt!);
        if (_filterDuration == '< 1 Hari'.tr()) return diff.inDays < 1;
        if (_filterDuration == '< 3 Hari'.tr()) return diff.inDays < 3;
        if (_filterDuration == '> 3 Hari'.tr()) return diff.inDays >= 3;
        return true;
      }).toList();
    }
    return reports;
  }

  Widget _buildFirestoreError(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.dangerLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_rounded,
                color: AppColors.danger, size: 18),
            const SizedBox(width: 8),
            Text('Gagal memuatkan laporan Firestore'.tr(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          Text(
              'Semak Firebase Security Rules anda: allow read di sos_reports bagi pengguna yang log masuk.'
                  .tr(),
              style: GoogleFonts.inter(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          // Fallback: show mock data
          Text('Menunjukkan data ujian sementara:'.tr(),
              style: GoogleFonts.inter(
                  fontSize: 11,
                  color: AppColors.textHint,
                  fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }

  Widget _buildIncidentList(List<SosReportModel> reports) {
    final hasReports = reports.isNotEmpty;
    final hasZones = _disasterZoneNames.isNotEmpty;

    if (!hasReports && !hasZones) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const Icon(Icons.check_circle_outline_rounded,
                  size: 48, color: AppColors.safe),
              const SizedBox(height: 12),
              Text('Tiada insiden aktif ditemui.'.tr(),
                  style: GoogleFonts.inter(color: AppColors.textSecondary)),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // ── Declared Disaster Zones (shown as incident banners) ──────────
        if (hasZones) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              children: [
                const Icon(Icons.campaign_rounded,
                    size: 16, color: AppColors.danger),
                const SizedBox(width: 6),
                Text(
                  'declaredDisasterZones'
                      .tr(args: [_disasterZoneNames.length.toString()]),
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger),
                ),
              ],
            ),
          ),
          ..._disasterZoneNames.map((zone) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.danger.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.campaign_rounded,
                              color: AppColors.danger, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(zone,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.inter(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: AppColors.textPrimary)),
                              const SizedBox(height: 2),
                              Text('Zon Darurat Aktif'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                              color: AppColors.danger.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(99)),
                          child: Text('AKTIF'.tr(),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.danger)),
                        ),
                      ],
                    ),
                  ),
                ),
              )),
          if (hasReports) const SizedBox(height: 8),
        ],
        // ── SOS Reports ─────────────────────────────────────────────────
        ...reports.map((report) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Dismissible(
                key: Key(report.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  padding: const EdgeInsets.only(right: 20),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    color: AppColors.safe,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 28),
                ),
                confirmDismiss: (direction) async {
                  return await _confirmResolveDialog(report);
                },
                onDismissed: (direction) {
                  _resolveIncident(report);
                },
                child: _resolvableSOSCard(report),
              ),
            )),
      ],
    );
  }

  Set<Marker> _buildMarkersFromReports(List<SosReportModel> reports) {
    final Set<Marker> markers = reports.map((report) {
      double hue = BitmapDescriptor.hueRed; // KRITIKAL default
      if (report.urgency == SosReportModel.urgencyTinggi) {
        hue = BitmapDescriptor.hueOrange;
      } else if (report.urgency == SosReportModel.urgencySedang) {
        hue = BitmapDescriptor.hueYellow;
      } else if (report.urgency == SosReportModel.urgencyRendah) {
        hue = BitmapDescriptor.hueGreen;
      }

      Color markerColor = AppColors.danger;
      if (report.urgency == SosReportModel.urgencyTinggi) {
        markerColor = AppColors.warning;
      } else if (report.urgency == SosReportModel.urgencySedang) {
        markerColor = const Color(0xFFFBBF24);
      } else if (report.urgency == SosReportModel.urgencyRendah) {
        markerColor = AppColors.safe;
      }

      IconData icon = _typeIcon(report.type);

      return Marker(
        markerId: MarkerId(report.id),
        position: LatLng(report.latitude, report.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: '${report.type} — ${report.urgency}',
          snippet: report.address.isNotEmpty
              ? report.address
              : '${report.latitude.toStringAsFixed(4)}, ${report.longitude.toStringAsFixed(4)}',
          onTap: () => _showSOSDetails(report, markerColor, icon),
        ),
      );
    }).toSet();

    // Add active volunteer markers
    for (final vol in _activeVolunteers) {
      if (vol.currentLat != null && vol.currentLng != null) {
        markers.add(
          Marker(
            markerId: MarkerId('volunteer_${vol.uid}'),
            position: LatLng(vol.currentLat!, vol.currentLng!),
            icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure),
            infoWindow: InfoWindow(
              title: 'Sukarelawan: ${vol.fullName}',
              snippet:
                  'Kepakaran: ${vol.skills.isNotEmpty ? vol.skills : "Umum"} | Aktif',
            ),
          ),
        );
      }
    }

    return markers;
  }

  Set<Circle> _buildCircles() {
    final Set<Circle> circles = {};
    for (int i = 0; i < _disasterZones.length; i++) {
      circles.add(_disasterZones[i]);
    }

    // Add glowing halos for active SOS reports matching urgency levels
    for (final report in _getFilteredReports()) {
      Color markerColor = AppColors.danger;
      if (report.urgency == SosReportModel.urgencyTinggi) {
        markerColor = AppColors.warning;
      } else if (report.urgency == SosReportModel.urgencySedang) {
        markerColor = const Color(0xFFFBBF24);
      } else if (report.urgency == SosReportModel.urgencyRendah) {
        markerColor = AppColors.safe;
      }

      circles.add(
        Circle(
          circleId: CircleId('glow_sos_${report.id}'),
          center: LatLng(report.latitude, report.longitude),
          radius: 300,
          fillColor: markerColor.withValues(alpha: 0.18),
          strokeColor: markerColor.withValues(alpha: 0.5),
          strokeWidth: 1,
        ),
      );
    }

    if (_isSelectingDisasterZone && _selectedDisasterEpicenter != null) {
      circles.add(
        Circle(
          circleId: const CircleId('preview_zone'),
          center: _selectedDisasterEpicenter!,
          radius: _disasterRadius,
          fillColor: AppColors.danger.withValues(alpha: 0.3),
          strokeColor: AppColors.danger,
          strokeWidth: 2,
        ),
      );
    }
    return circles;
  }

  Widget _buildFilterDropdown({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: value != 'Semua'
            ? AppColors.officerAccent.withValues(alpha: 0.1)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(99),
        border: Border.all(
            color:
                value != 'Semua' ? AppColors.officerAccent : AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          icon: Icon(Icons.arrow_drop_down,
              color: value != 'Semua'
                  ? AppColors.officerAccent
                  : AppColors.textSecondary),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: value != 'Semua' ? FontWeight.w600 : FontWeight.w500,
            color: value != 'Semua'
                ? AppColors.officerAccent
                : AppColors.textSecondary,
          ),
          onChanged: onChanged,
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item == 'Semua' ? '$label: Semua' : item),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _declareDisasterZone() {
    setState(() {
      _isSelectingDisasterZone = true;
    });
  }

  void _confirmDisasterZone() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            Text('Isytihar Zon Darurat'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger)),
          ],
        ),
        content: Text(
          'pushAlertWarning'.tr(args: [(_disasterRadius / 1000).toString()]),
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Batal'.tr(),
                  style: GoogleFonts.inter(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              final epicenter = _selectedDisasterEpicenter!;
              Navigator.pop(ctx);

              _firestoreService.createDisasterZone({
                'epicenterLat': epicenter.latitude,
                'epicenterLng': epicenter.longitude,
                'radius': _disasterRadius,
                'type': _disasterType,
                'name': _disasterNameController.text.trim(),
              }).then((_) {
                int affectedCount =
                    _calculateAffectedUsers(epicenter, _disasterRadius);
                if (mounted) {
                  setState(() {
                    _isSelectingDisasterZone = false;
                    _selectedDisasterEpicenter = null;
                    _disasterRadius = 5000.0;
                    _disasterNameController.clear();
                  });
                  _showGeofenceSuccessDialog(affectedCount);
                }
              }).catchError((e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('errorSavingZone'.tr(args: [e.toString()])),
                      backgroundColor: AppColors.danger));
                }
              });
            },
            child: Text('Sah & Hantar'.tr(),
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  int _calculateAffectedUsers(LatLng center, double radiusInMeters) {
    int affectedReports = 0;
    for (final report in _activeReports) {
      if (_calculateDistance(center.latitude, center.longitude, report.latitude,
              report.longitude) <=
          radiusInMeters) {
        affectedReports++;
      }
    }
    return affectedReports > 0
        ? (affectedReports * 124)
        : (radiusInMeters / 10).round();
  }

  double _calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaPhi = (lat2 - lat1) * math.pi / 180;
    final deltaLambda = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(deltaLambda / 2) *
            math.sin(deltaLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  void _showGeofenceSuccessDialog(int totalReached) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.podcasts_rounded, color: AppColors.safe, size: 40),
            const SizedBox(height: 12),
            Text('geofencingSuccess'.tr(args: [totalReached.toString()]),
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ],
        ),
        content: Text(
          'Sistem geofencing SIGAP telah berjaya memancarkan Push Alerts kepada anggaran $totalReached peranti pengguna awam di dalam radius sasaran.',
          style:
              GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup'.tr(),
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Future<void> _resolveIncident(SosReportModel report) async {
    try {
      await _firestoreService.resolveSOSReportByOfficer(report.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('incidentResolvedMsg'.tr(args: [
              report.type,
              report.address.isNotEmpty ? report.address : "lokasi insiden".tr()
            ])),
            backgroundColor: AppColors.safe));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('failedResolveIncident'.tr(args: [e.toString()])),
            backgroundColor: AppColors.danger));
      }
    }
  }

  Future<bool> _confirmResolveDialog(SosReportModel report) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Selesaikan Insiden?'.tr(),
            style:
                GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
        content: Text(
            'confirmResolveCase'.tr(args: [
              report.type,
              report.address.isNotEmpty ? report.address : report.urgency
            ]),
            style: GoogleFonts.inter(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal'.tr(),
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.safe),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Selesai'.tr(),
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSOSDetails(SosReportModel report, Color color, IconData icon) {
    String selectedSquad = 'Skuad Alpha'.tr();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateSheet) => DraggableScrollableSheet(
          initialChildSize:
              report.status == SosReportModel.statusActive ? 0.75 : 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollController) => SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          shape: BoxShape.circle),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.type,
                              style: GoogleFonts.poppins(
                                  fontSize: 18, fontWeight: FontWeight.w700)),
                          Text(
                              report.address.isNotEmpty
                                  ? report.address
                                  : '${report.latitude.toStringAsFixed(4)}, ${report.longitude.toStringAsFixed(4)}',
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    _detailBadge('Keutamaan'.tr(), report.urgency, color),
                    const SizedBox(width: 12),
                    _detailBadge(
                        'Status'.tr(), report.status, AppColors.officerAccent),
                  ],
                ),
                const SizedBox(height: 16),
                if (report.description.isNotEmpty) ...[
                  Text('Keterangan'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Text(report.description,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                          height: 1.5)),
                  const SizedBox(height: 16),
                ],
                if (report.reporterName.isNotEmpty) ...[
                  Text('reporterNameStr'.tr(args: [report.reporterName]),
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                ],
                if (report.imageUrl != null && report.imageUrl!.isNotEmpty) ...[
                  Text('Gambar Bukti Kecemasan'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: report.imageUrl!.startsWith('data:image')
                        ? Image.memory(
                            base64Decode(report.imageUrl!.split(',').last),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200,
                          )
                        : Image.network(
                            report.imageUrl!,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: 200,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 100,
                                color: Colors.grey[100],
                                alignment: Alignment.center,
                                child: Text(
                                  'Gagal memuatkan gambar bukti.'.tr(),
                                  style: GoogleFonts.inter(
                                      color: AppColors.textSecondary),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Show dispatch section if status is active
                if (report.status == SosReportModel.statusActive) ...[
                  const Divider(height: 32),
                  Text('Agih Skuad Bantuan (Manual Dispatch)'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: selectedSquad,
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(color: AppColors.divider),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: AppColors.officerAccent),
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'Skuad Alpha'.tr(),
                          child: Text('Skuad Alpha (Penyelamat)'.tr())),
                      DropdownMenuItem(
                          value: 'Skuad Delta'.tr(),
                          child: Text('Skuad Delta (Perubatan)'.tr())),
                      DropdownMenuItem(
                          value: 'Skuad Charlie'.tr(),
                          child: Text('Skuad Charlie (Logistik)'.tr())),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setStateSheet(() {
                          selectedSquad = val;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final navigator = Navigator.of(ctx);
                        final scaffoldMessenger = ScaffoldMessenger.of(context);
                        try {
                          await _firestoreService.respondToSOS(
                            report.id,
                            'officer_dispatch_${selectedSquad.replaceAll(" ", "_").toLowerCase()}',
                            selectedSquad,
                          );
                          if (navigator.mounted) {
                            navigator.pop();
                          }
                          scaffoldMessenger.showSnackBar(SnackBar(
                            content: Text('successDispatchSquad'
                                .tr(args: [selectedSquad])),
                            backgroundColor: AppColors.safe,
                          ));
                        } catch (e) {
                          scaffoldMessenger.showSnackBar(SnackBar(
                            content: Text(
                                'failedDispatchSquad'.tr(args: [e.toString()])),
                            backgroundColor: AppColors.danger,
                          ));
                        }
                      },
                      icon: const Icon(Icons.send_rounded,
                          size: 18, color: Colors.white),
                      label: Text('Hantar Skuad Sekarang'.tr(),
                          style: TextStyle(color: Colors.white)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.officerAccent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Show responder details & backup warnings if status is responded
                if (report.status == SosReportModel.statusResponded) ...[
                  const Divider(height: 32),
                  Text('Maklumat Respon / Menyelamat'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.engineering_rounded,
                            color: AppColors.primary, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RESPONDER'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                report.responderName ?? 'Sukarelawan'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (report.needBackup) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: AppColors.danger.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_rounded,
                              color: AppColors.danger, size: 24),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'BANTUAN TAMBAHAN DIPERLUKAN'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.danger),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Responder di lokasi telah meminta bantuan unit tambahan/squad sokongan segera.'
                                      .tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 12, color: AppColors.danger),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ],

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text('Tutup'.tr(),
                        style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  void _showHistoryDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Sejarah Insiden Selesai'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder(
                stream: _firestoreService.streamResolvedSOSReports(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.officerAccent));
                  }
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return Center(
                        child: Text('Tiada sejarah insiden ditemui.'.tr(),
                            style: GoogleFonts.inter(
                                color: AppColors.textSecondary)));
                  }
                  final resolved =
                      docs.map((d) => SosReportModel.fromDocument(d)).toList();
                  return ListView.builder(
                    itemCount: resolved.length,
                    itemBuilder: (context, index) {
                      final r = resolved[index];
                      return ListTile(
                        leading: const Icon(Icons.check_circle_rounded,
                            color: AppColors.safe),
                        title: Text(r.type,
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w600)),
                        subtitle: Text(
                            r.address.isNotEmpty ? r.address : r.reporterName,
                            style: GoogleFonts.inter(fontSize: 12)),
                        trailing: Text(r.urgency,
                            style: GoogleFonts.inter(
                                fontSize: 12, color: AppColors.textPrimary)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _resolvableSOSCard(SosReportModel report) {
    Color color = AppColors.primary;
    IconData icon = Icons.warning_amber_rounded;

    switch (report.urgency) {
      case SosReportModel.urgencyKritikal:
        color = AppColors.danger;
        break;
      case SosReportModel.urgencyTinggi:
        color = AppColors.warning;
        break;
      case SosReportModel.urgencySedang:
        color = const Color(0xFFFBBF24);
        break;
      case SosReportModel.urgencyRendah:
        color = AppColors.safe;
        break;
    }
    icon = _typeIcon(report.type);

    // Duration string
    String duration = '';
    if (report.createdAt != null) {
      final diff = DateTime.now().difference(report.createdAt!);
      if (diff.inMinutes < 60) {
        duration = '${diff.inMinutes} minit lalu';
      } else if (diff.inHours < 24) {
        duration = '${diff.inHours} jam lalu';
      } else {
        duration = '${diff.inDays} hari lalu';
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showSOSDetails(report, color, icon),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${report.type}${report.address.isNotEmpty ? " — ${report.address}" : ""}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 2),
                          Text(
                              duration.isNotEmpty
                                  ? 'durationStr'.tr(args: [duration])
                                  : 'reporterNameStr'
                                      .tr(args: [report.reporterName]),
                              style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(99)),
                      child: Text(report.urgency,
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Authority Routing Badge
                Builder(builder: (_) {
                  final authority = AuthorityRoutingService.instance
                      .getAuthority(report.type);
                  return Row(
                    children: [
                      Icon(authority.icon, size: 13, color: authority.color),
                      const SizedBox(width: 4),
                      Text(
                        'routedTo'.tr(args: [authority.shortName]),
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: authority.color),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => AuthorityRoutingService.instance
                            .callAuthority(authority),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: authority.color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: authority.color.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.phone_rounded,
                                  size: 11, color: authority.color),
                              const SizedBox(width: 3),
                              Text(authority.phone,
                                  style: GoogleFonts.inter(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: authority.color)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
                if (report.status == SosReportModel.statusResponded ||
                    report.needBackup) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.engineering_rounded,
                              size: 14, color: AppColors.officerAccent),
                          const SizedBox(width: 4),
                          Text(
                            'respondedBy'.tr(args: [
                              report.responderName ?? "Penyelamat".tr()
                            ]),
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      if (report.needBackup)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                              color: AppColors.dangerLight,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                  color:
                                      AppColors.danger.withValues(alpha: 0.2))),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.warning_rounded,
                                  size: 10, color: AppColors.danger),
                              const SizedBox(width: 4),
                              Text(
                                'Perlu Bantuan'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.danger),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final confirm = await _confirmResolveDialog(report);
                      if (confirm && mounted) {
                        _resolveIncident(report);
                      }
                    },
                    icon: const Icon(Icons.check_circle_outline_rounded,
                        size: 18),
                    label: Text('Selesaikan Insiden'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.safe,
                      side: const BorderSide(color: AppColors.safe),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── SKUAD (VOLUNTEER) TAB ────────────────────────────────────────
  Widget _buildVolunteerTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Penugasan Skuad'.tr(),
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _assignVolunteerDialog,
            icon: const Icon(Icons.group_add_rounded, size: 18),
            label: Text('Agih Skuad (Assign Squad)'.tr()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volunteerAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.streamVolunteerTasks(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final docs = snapshot.hasData ? snapshot.data!.docs.toList() : [];
            if (docs.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider)),
                child: Text('Tiada skuad ditugaskan.'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary)),
              );
            }
            docs.sort((a, b) {
              final aTime =
                  (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              final bTime =
                  (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime);
            });

            return Column(
              children: docs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final task = VolunteerTaskModel.fromMap(doc.id, data);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: _volunteerSquadCard(task),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  // Calculates distance between squad zone target and a volunteer's live position
  double _distToZone(LatLng zoneCoords, VolunteerProfileModel vol) {
    if (vol.currentLat == null || vol.currentLng == null)
      return double.infinity;
    return _calculateDistance(zoneCoords.latitude, zoneCoords.longitude,
        vol.currentLat!, vol.currentLng!);
  }

  void _assignSquadDialog() {
    final unassignedVolunteers =
        _activeVolunteers.where((v) => v.assignedSquad.isEmpty).toList();
    String selectedSquad = 'Skuad Alpha (Penyelamat)'.tr();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Tugaskan Skuad kepada Sukarelawan'.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.volunteerAccent)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      labelText: 'Pilih Skuad'.tr()),
                  initialValue: selectedSquad,
                  items: [
                    DropdownMenuItem(
                        value: 'Skuad Alpha (Penyelamat)'.tr(),
                        child: Text('Skuad Alpha (Penyelamat)'.tr())),
                    DropdownMenuItem(
                        value: 'Skuad Bravo (Pembersihan)'.tr(),
                        child: Text('Skuad Bravo (Pembersihan)'.tr())),
                    DropdownMenuItem(
                        value: 'Skuad Charlie (Logistik)'.tr(),
                        child: Text('Skuad Charlie (Logistik)'.tr())),
                    DropdownMenuItem(
                        value: 'Skuad Delta (Perubatan)'.tr(),
                        child: Text('Skuad Delta (Perubatan)'.tr())),
                    DropdownMenuItem(
                        value: 'Skuad Echo (Dapur Jalanan)'.tr(),
                        child: Text('Skuad Echo (Dapur Jalanan)'.tr())),
                    DropdownMenuItem(
                        value: 'Skuad Foxtrot (Komunikasi)'.tr(),
                        child: Text('Skuad Foxtrot (Komunikasi)'.tr())),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialogState(() => selectedSquad = v);
                  },
                ),
                const SizedBox(height: 16),
                if (unassignedVolunteers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('Tiada sukarelawan yang belum ditugaskan.'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textSecondary)),
                  )
                else
                  ...unassignedVolunteers.map((vol) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: AppColors.volunteerAccent
                                  .withValues(alpha: 0.2),
                              child: Text(vol.fullName[0].toUpperCase(),
                                  style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.volunteerAccent)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(vol.fullName,
                                      style: GoogleFonts.inter(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600)),
                                  Text(
                                      vol.skills.isNotEmpty
                                          ? vol.skills
                                          : 'Tiada kemahiran'.tr(),
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () async {
                                final squadId = selectedSquad
                                    .toLowerCase()
                                    .replaceAll('(', '.tr()')
                                    .replaceAll(')', '.tr()')
                                    .replaceAll(' ', '.tr()_');
                                await _firestoreService.assignVolunteerToSquad(
                                    vol.uid, selectedSquad, squadId);
                                if (mounted) {
                                  Navigator.pop(ctx);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                        content: Text(
                                            '${vol.fullName} ditugaskan ke $selectedSquad'),
                                        backgroundColor: AppColors.safe),
                                  );
                                  _listenToActiveVolunteers(); // Refresh list
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.volunteerAccent,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20)),
                              ),
                              child: Text('Tugaskan'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Tutup'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary))),
          ],
        );
      }),
    );
  }

  void _assignVolunteerDialog() {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    String selectedSquad = 'Skuad Alpha (Penyelamat)'.tr();
    final Set<String> dynamicZonesSet = {};

    // Store the loading dialog context/navigator to close it later
    NavigatorState? loadingNavigator;

    // Show loading dialog first while fetching data
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext loadingCtx) {
        loadingNavigator = Navigator.of(loadingCtx);
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: AppColors.volunteerAccent),
              const SizedBox(height: 16),
              Text('Memuatkan zon aktif...'.tr(),
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        );
      },
    );

    // Fetch active SOS reports directly from Firestore
    FirebaseFirestore.instance
        .collection('sos_reports')
        .where('status', isEqualTo: SosReportModel.statusActive)
        .get()
        .then((sosSnapshot) {
      if (!mounted) return;
      // Also fetch disaster zones
      FirebaseFirestore.instance
          .collection('disaster_zones')
          .get()
          .then((zoneSnapshot) {
        if (!mounted) return;
        final Map<String, LatLng> zoneCoordinatesMap = {};

        // Populate zones from active SOS reports
        for (var doc in sosSnapshot.docs) {
          final report = SosReportModel.fromDocument(doc);
          final coords = LatLng(report.latitude, report.longitude);
          if (report.address.isNotEmpty) {
            dynamicZonesSet.add(report.address);
            zoneCoordinatesMap[report.address] = coords;
          }
          // Also add from coordinates if address is empty
          if (report.address.isEmpty) {
            final coordStr =
                '${report.latitude.toStringAsFixed(4)}, ${report.longitude.toStringAsFixed(4)}';
            dynamicZonesSet.add(coordStr);
            zoneCoordinatesMap[coordStr] = coords;
          }
        }

        // Add declared disaster zones
        for (var doc in zoneSnapshot.docs) {
          final data = doc.data();
          final zoneName = data['name'] as String?;
          final latRaw = data['epicenterLat'];
          final lngRaw = data['epicenterLng'];
          if (zoneName != null && zoneName.trim().isNotEmpty) {
            final name = zoneName.trim();
            dynamicZonesSet.add(name);
            if (latRaw != null && lngRaw != null) {
              zoneCoordinatesMap[name] = LatLng(
                  (latRaw as num).toDouble(), (lngRaw as num).toDouble());
            }
          }
        }

        // Fallback if still empty
        if (dynamicZonesSet.isEmpty) {
          dynamicZonesSet.add('Tiada Zon Aktif'.tr());
        }

        final dynamicZones = dynamicZonesSet.toList()..sort();

        // Close loading dialog
        if (mounted) {
          loadingNavigator?.pop();
        }

        // Show actual assignment dialog
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (BuildContext dialogContext) {
            return _SquadDispatchDialog(
              dynamicZones: dynamicZones,
              zoneCoordinatesMap: zoneCoordinatesMap,
              initialSquad: selectedSquad,
              fallbackCoordinates: _zoneCoordinates,
              onCreateTask: _firestoreService.createVolunteerTask,
            );
          },
        );
      }).catchError((e) {
        // Handle error - close loading dialog if open
        if (mounted) {
          loadingNavigator?.pop();
          messenger.showSnackBar(SnackBar(
              content: Text('failedLoadZone'.tr(args: [e.toString()])),
              backgroundColor: AppColors.danger));
        }
      });
    }).catchError((e) {
      // Handle error - close loading dialog if open
      if (mounted) {
        loadingNavigator?.pop();
        messenger.showSnackBar(SnackBar(
            content: Text('failedLoadSOS'.tr(args: [e.toString()])),
            backgroundColor: AppColors.danger));
      }
    });
  }

  LatLng _zoneCoordinates(String zone) {
    final normalized = zone.toLowerCase();
    if (normalized.contains('ampang')) return const LatLng(3.1490, 101.7620);
    if (normalized.contains('hulu langat'.tr())) {
      return const LatLng(3.0948, 101.8187);
    }
    if (normalized.contains('gombak')) return const LatLng(3.2521, 101.6530);
    if (normalized.contains('sri petaling'.tr())) {
      return const LatLng(3.0705, 101.6920);
    }
    return const LatLng(3.1390, 101.6869);
  }

  void _redirectVolunteerDialog(VolunteerTaskModel task) {
    // Build dynamic zone list from active SOS reports + declared disaster zones
    final Set<String> zonesSet = {};
    for (var report in _activeReports) {
      if (report.address.isNotEmpty) zonesSet.add(report.address);
    }
    zonesSet.addAll(_disasterZoneNames);
    // Ensure the task's current zone is always available
    if (task.zone.isNotEmpty) zonesSet.add(task.zone);
    if (zonesSet.isEmpty) zonesSet.add('Tiada Zon Tersedia'.tr());
    final zones = zonesSet.toList()..sort();
    // Default new zone to the first zone that is NOT the current one
    String newZone =
        zones.firstWhere((z) => z != task.zone, orElse: () => zones.first);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (context, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Tukar Lokasi Skuad'.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('redirectSquadMsg'.tr(args: [task.squadName]),
                    style: GoogleFonts.inter(fontSize: 14)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: InputDecoration(
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      labelText: 'Lokasi Baharu'.tr()),
                  initialValue: newZone,
                  items: zones
                      .map((z) => DropdownMenuItem(
                            value: z,
                            child: Text(z, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialogState(() => newZone = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Batal'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () async {
                final coords = _zoneCoordinates(newZone);
                await _firestoreService.updateVolunteerTask(task.id, {
                  'zone': newZone,
                  'status': 'Menuju ke Lokasi'.tr(),
                  'progress': 0.1,
                  'currentLat': coords.latitude,
                  'currentLng': coords.longitude,
                  'lastKnownLocation': newZone,
                  'eta': '20 min',
                });
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(
                          '${task.squadName} diarahkan ke lokasi baharu.')));
                }
              },
              child: Text('Ubah Lokasi'.tr(),
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      }),
    );
  }

  void _showSquadTrackMapDialog(VolunteerTaskModel task) {
    if (task.currentLat == null || task.currentLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lokasi skuad belum disegerakkan oleh GPS.'.tr()),
      ));
      return;
    }

    final destCoords = _zoneCoordinates(task.zone);
    final squadPos = LatLng(task.currentLat!, task.currentLng!);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Kesan Skuad: ${task.squadName}',
            style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.primary)),
        content: Container(
          width: double.maxFinite,
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          clipBehavior: Clip.hardEdge,
          child: GoogleMap(
            initialCameraPosition: CameraPosition(
              target: squadPos,
              zoom: 12.0,
            ),
            markers: {
              Marker(
                markerId: const MarkerId('squad_pos'),
                position: squadPos,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
                infoWindow: InfoWindow(
                  title: task.squadName,
                  snippet:
                      'Status: ${task.status} | Progres: ${(task.progress * 100).round()}%',
                ),
              ),
              Marker(
                markerId: const MarkerId('dest_pos'),
                position: destCoords,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueRed),
                infoWindow: InfoWindow(
                  title: 'Zon Destinasi: ${task.zone}',
                  snippet: task.taskDescription,
                ),
              ),
            },
            circles: {
              Circle(
                circleId: const CircleId('dest_radius'),
                center: destCoords,
                radius: 1000,
                fillColor: AppColors.danger.withValues(alpha: 0.15),
                strokeColor: AppColors.danger,
                strokeWidth: 1,
              )
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup'.tr(),
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          )
        ],
      ),
    );
  }

  Widget _volunteerSquadCard(VolunteerTaskModel task) {
    Color statusColor = Colors.orange;
    if (task.status == 'Sedang Bertugas'.tr()) statusColor = Colors.green;
    if (task.status == 'Selesai Tugas'.tr()) statusColor = Colors.blue;
    final priorityColor =
        task.priority == 'Kritikal'.tr() || task.priority == 'Tinggi'.tr()
            ? AppColors.danger
            : task.priority == 'Rendah'.tr()
                ? AppColors.safe
                : AppColors.warning;
    final coordinates = task.currentLat != null && task.currentLng != null
        ? '${task.currentLat!.toStringAsFixed(4)}, ${task.currentLng!.toStringAsFixed(4)}'
        : 'Belum disegerakkan'.tr();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.group_rounded,
                        color: AppColors.volunteerAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(task.squadName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99)),
                child: Row(
                  children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                            color: statusColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(task.status,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: statusColor)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _trackingChip(
                  Icons.priority_high_rounded, task.priority, priorityColor),
              _trackingChip(
                  Icons.person_pin_circle_rounded,
                  task.assignedVolunteer.isEmpty
                      ? 'Skuad penuh'.tr()
                      : task.assignedVolunteer,
                  AppColors.volunteerAccent),
              _trackingChip(
                  Icons.timer_rounded, 'ETA ${task.eta}', AppColors.primary),
              // Acceptance counter badge
              if (task.requiredVolunteerCount > 0)
                _trackingChip(
                    Icons.how_to_reg_rounded,
                    '${task.acceptedVolunteerUIDs.length}/${task.requiredVolunteerCount} terima',
                    task.acceptedVolunteerUIDs.length >=
                            task.requiredVolunteerCount
                        ? AppColors.safe
                        : AppColors.warning),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('Lokasi: ${task.zone}',
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Icon(Icons.radar_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text('Live Track: $coordinates',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textSecondary)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Tugasan Semasa:'.tr(),
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(task.taskDescription,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          LinearProgressIndicator(
              value: task.progress,
              backgroundColor: statusColor.withValues(alpha: 0.1),
              color: statusColor,
              minHeight: 6,
              borderRadius: BorderRadius.circular(4)),
          const SizedBox(height: 16),
          // ── Action buttons row 1: Tukar Lokasi + Kesan Peta ───────────────
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _redirectVolunteerDialog(task),
                  icon: const Icon(Icons.alt_route_rounded, size: 14),
                  label:
                      Text('Tukar Lokasi'.tr(), style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showSquadTrackMapDialog(task),
                  icon: const Icon(Icons.map_rounded, size: 14),
                  label:
                      Text('Kesan Peta'.tr(), style: TextStyle(fontSize: 11)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const SizedBox(height: 8),
          if (task.status == 'Selesai Tugas'.tr())
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.safe.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.verified_rounded,
                      color: AppColors.safe, size: 16),
                  const SizedBox(width: 6),
                  Text('Tugasan Selesai'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: AppColors.safe)),
                ],
              ),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                  color: AppColors.volunteerAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.hourglass_empty_rounded,
                      color: AppColors.volunteerAccent, size: 16),
                  const SizedBox(width: 6),
                  Text('Menunggu kemas kini sukarelawan...'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.volunteerAccent)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trackingChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(99)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  // ─── AWANIS TAB ───────────────────────────────────────────────────
  Widget _buildAwanisTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: AppColors.surface,
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xFF6B4EE6).withValues(alpha: 0.1),
                    shape: BoxShape.circle),
                child: const Icon(Icons.smart_toy_rounded,
                    color: Color(0xFF6B4EE6), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AWANIS'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF6B4EE6))),
                    Text('Pembantu Analitik & Pelaporan'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _generateIncidentSummary,
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 16),
                label: Text('Jana Laporan'.tr()),
                style: ElevatedButton.styleFrom(
                  minimumSize: Size.zero,
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        _buildOfficerQuickAccessChips(),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _awanisOfficerMessages.length,
            itemBuilder: (context, index) {
              final msg = _awanisOfficerMessages[index];
              final isBot = msg['isBot'] as bool;
              return _buildChatBubble(msg['text'] as String, isBot);
            },
          ),
        ),
        if (_isAwanisLoading)
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(color: Color(0xFF6B4EE6)),
          ),
        _buildAwanisInput(),
      ],
    );
  }

  Widget _buildChatBubble(String text, bool isBot) {
    return Align(
      alignment: isBot ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isBot ? Colors.white : AppColors.officerAccent,
          borderRadius: BorderRadius.circular(16),
          border: isBot ? Border.all(color: AppColors.divider) : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 5,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            color: isBot ? AppColors.textPrimary : Colors.white,
            fontSize: 13,
            height: 1.4,
          ),
        ),
      ),
    );
  }

  Widget _buildOfficerQuickAccessChips() {
    final quickQuestions = [
      {
        'icon': '📊',
        'label': 'Statistik SOS'.tr(),
        'query': 'Berapa banyak SOS yang belum diselesaikan hari ini?'.tr(),
        'color': AppColors.danger,
      },
      {
        'icon': '👥',
        'label': 'Jumlah Mangsa'.tr(),
        'query': 'Berapa jumlah mangsa di kawasan Gombak?'.tr(),
        'color': AppColors.safe,
      },
      {
        'icon': '🛡️',
        'label': 'Status Skuad'.tr(),
        'query': 'Berapa ramai sukarelawan aktif sekarang?'.tr(),
        'color': AppColors.officerAccent,
      },
      {
        'icon': '💰',
        'label': 'Tuntutan BWI'.tr(),
        'query': 'Berapa jumlah dana tuntutan yang telah diluluskan?'.tr(),
        'color': AppColors.warning,
      },
    ];

    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: quickQuestions.map((q) {
            final color = q['color'] as Color;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _sendOfficerQuickQuery(q['query'] as String),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(q['icon'] as String,
                            style: const TextStyle(fontSize: 14)),
                        const SizedBox(width: 6),
                        Text(
                          q['label'] as String,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAwanisInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _awanisMsgCtrl,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  textInputAction: TextInputAction.send,
                  decoration: InputDecoration(
                    hintText:
                        'Tanya AWANIS (cth: Berapa SOS hari ini?)...'.tr(),
                    hintStyle: GoogleFonts.inter(
                        color: AppColors.textHint, fontSize: 13),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onSubmitted: (_) => _sendAwanisMessage(),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                decoration: const BoxDecoration(
                  color: AppColors.officerAccent,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
                  onPressed: _sendAwanisMessage,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _sendOfficerQuickQuery(String query) {
    _awanisMsgCtrl.text = query;
    _sendAwanisMessage();
  }

  void _sendAwanisMessage() async {
    final text = _awanisMsgCtrl.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _awanisOfficerMessages.add({'isBot': false, 'text': text});
      _isAwanisLoading = true;
    });
    _awanisMsgCtrl.clear();

    try {
      // Gather some simple analytics data
      final activeSOS = _activeReports.length;
      final activeVols = _activeVolunteers.length;
      final firestoreData = {
        'jumlah_sos_aktif': activeSOS,
        'jumlah_sukarelawan_aktif': activeVols,
      };

      final response =
          await AwanisService().queryOfficerAnalytics(text, firestoreData);
      if (mounted) {
        setState(() {
          _awanisOfficerMessages.add({'isBot': true, 'text': response});
          _isAwanisLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _awanisOfficerMessages.add({
            'isBot': true,
            'text': 'Maaf, ralat berlaku semasa memproses soalan anda.'.tr()
          });
          _isAwanisLoading = false;
        });
      }
    }
  }

  void _generateIncidentSummary() async {
    setState(() {
      _isAwanisLoading = true;
    });
    try {
      final activeSOS = _activeReports.length;
      final activeVols = _activeVolunteers.length;
      final zoneData = {
        'nama_zon': 'Zon Darurat Semasa'.tr(),
        'jumlah_sos_aktif': activeSOS,
        'sukarelawan_aktif': activeVols,
      };

      final report = await AwanisService().generateIncidentSummary(zoneData);

      if (mounted) {
        setState(() {
          _isAwanisLoading = false;
        });
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.picture_as_pdf_rounded, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(
                    child: Text('Laporan Insiden AI'.tr(),
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.bold, fontSize: 18))),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(report,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textPrimary)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Tutup'.tr(),
                    style: GoogleFonts.inter(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: () async {
                  final file = await PdfReportService.generateReportPdf(report, 'Laporan Insiden AI'.tr());
                  await PdfReportService.shareReport(file);
                },
                icon: const Icon(Icons.share_rounded, size: 16),
                label: Text('Kongsi'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final file = await PdfReportService.generateReportPdf(report, 'Laporan Insiden AI'.tr());
                  await PdfReportService.downloadReport(file);
                },
                icon: const Icon(Icons.download_rounded, size: 16),
                label: Text('Muat Turun'.tr()),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.safe,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAwanisLoading = false;
        });
      }
    }
  }

  // ─── TUNTUTAN (CLAIMS) TAB ────────────────────────────────────────
  Widget _buildClaimsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamClaimsForOfficerReview(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final claims =
            snapshot.hasData ? snapshot.data!.docs : <DocumentSnapshot>[];
        claims.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['createdAt'] as Timestamp?;
          final bTime = bData['createdAt'] as Timestamp?;
          if (aTime == null || bTime == null) return 0;
          return bTime.compareTo(aTime); // descending
        });

        // Extract unique active locations/zones from active claims list for filter dropdown
        final claimLocations = claims
            .map((doc) =>
                (doc.data() as Map<String, dynamic>)['location'] as String? ??
                '')
            .where((loc) => loc.trim().isNotEmpty)
            .toSet()
            .toList();
        claimLocations.sort();

        // Apply filters (Zone and Status)
        final filteredClaims = claims.where((doc) {
          final claim =
              ClaimModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);

          // 1. Status Filter
          if (_selectedClaimStatusFilter != 'Semua') {
            if (claim.status != _selectedClaimStatusFilter) return false;
          }

          // 2. Zone/Location Filter
          if (_selectedClaimZoneFilter != 'Semua') {
            if (!_claimMatchesZone(claim.location, _selectedClaimZoneFilter))
              return false;
          }

          return true;
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Semakan Tuntutan Bantuan'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
                'Semak bukti, beri maklum balas, atau luluskan tuntutan mengikut zon bencana.'
                    .tr(),
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            _bulkApprovalPanel(claims),
            const SizedBox(height: 16),

            // --- Filter controls ---
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.filter_list_rounded,
                              size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Tapis Senarai Tuntutan'.tr(),
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      if (_selectedClaimStatusFilter != 'Semua' ||
                          _selectedClaimZoneFilter != 'Semua')
                        TextButton(
                          onPressed: () => setState(() {
                            _selectedClaimStatusFilter = 'Semua';
                            _selectedClaimZoneFilter = 'Semua';
                          }),
                          style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                          ),
                          child: Text(
                            'Set Semula'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // Dropdown Filter for Zone
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedClaimZoneFilter,
                    decoration: InputDecoration(
                      labelText: 'Tapis Mengikut Zon Bencana'.tr(),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'Semua', child: Text('Semua Zon'.tr())),
                      ...claimLocations.map((loc) => DropdownMenuItem(
                          value: loc,
                          child: Text(loc, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedClaimZoneFilter = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  // Status chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Semua', 'Semua', claims),
                        const SizedBox(width: 8),
                        _buildFilterChip('Baru'.tr(), 'submitted', claims),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'Dalam Semakan'.tr(), 'under_review', claims),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                            'Tamat Tempoh'.tr(), 'expired', claims),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (filteredClaims.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32.0),
                child: Center(
                  child: Text(
                    claims.isEmpty
                        ? 'Tiada tuntutan untuk semakan buat masa ini.'.tr()
                        : 'Tiada tuntutan sepadan dengan penapis.'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...filteredClaims.map((doc) {
                final claim = ClaimModel.fromMap(
                    doc.id, doc.data() as Map<String, dynamic>);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _claimCard(claim),
                );
              }),
            const SizedBox(height: 80),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip(
      String label, String status, List<DocumentSnapshot> allClaims) {
    // Count claims in this status matching the current zone filter
    final count = allClaims.where((doc) {
      final claim =
          ClaimModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      if (_selectedClaimZoneFilter != 'Semua' &&
          !_claimMatchesZone(claim.location, _selectedClaimZoneFilter)) {
        return false;
      }
      return status == 'Semua' || claim.status == status;
    }).length;

    final isSelected = _selectedClaimStatusFilter == status;
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    final bgColor =
        isSelected ? AppColors.primary.withValues(alpha: 0.1) : Colors.white;
    final borderColor = isSelected ? AppColors.primary : AppColors.divider;

    return InkWell(
      onTap: () => setState(() => _selectedClaimStatusFilter = status),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.grey[200],
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulkApprovalPanel(List<DocumentSnapshot> reviewClaims) {
    return StreamBuilder<QuerySnapshot>(
      stream: _disasterZonesStream,
      builder: (context, zoneSnapshot) {
        final zones = zoneSnapshot.hasData
            ? zoneSnapshot.data!.docs
                .map((doc) =>
                    (doc.data() as Map<String, dynamic>)['name'] as String? ??
                    doc.id)
                .where((name) => name.trim().isNotEmpty)
                .toSet()
                .toList()
            : <String>[];
        zones.sort();

        final allSubmitted = reviewClaims
            .map((doc) =>
                ClaimModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
            .where((claim) => claim.status == 'submitted')
            .toList();

        final fallbackZones = allSubmitted
            .map((c) => c.location)
            .where((l) => l.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final selectableZones = zones.isNotEmpty ? zones : fallbackZones;

        if (_selectedBulkClaimZone == null && selectableZones.isNotEmpty) {
          _selectedBulkClaimZone = selectableZones.first;
        } else if (_selectedBulkClaimZone != null &&
            !selectableZones.contains(_selectedBulkClaimZone)) {
          selectableZones.add(_selectedBulkClaimZone!);
        }

        final selectedZone = _selectedBulkClaimZone;
        final matchingClaims = selectedZone == null
            ? <ClaimModel>[]
            : allSubmitted
                .where((c) => _claimMatchesZone(c.location, selectedZone))
                .toList();

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.divider)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.done_all_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Kelulusan Pukal Zon Bencana'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                  ),
                  Text('${matchingClaims.length} tuntutan',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ],
              ),
              const SizedBox(height: 10),
              // Zone dropdown
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedZone,
                decoration: InputDecoration(
                    labelText: 'Zon bencana'.tr(),
                    isDense: true,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8))),
                items: selectableZones
                    .map((zone) => DropdownMenuItem(
                          value: zone,
                          child: Text(zone, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: selectableZones.isEmpty
                    ? null
                    : (zone) => setState(() {
                          _selectedBulkClaimZone = zone;
                          _bulkSelectedClaimIds.clear();
                          _photoReviewConfirmed = false;
                        }),
              ),
              if (matchingClaims.isEmpty && selectedZone != null) ...[
                const SizedBox(height: 10),
                Text('Tiada tuntutan "dihantar" untuk zon ini.'.tr(),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textSecondary)),
              ] else if (matchingClaims.isNotEmpty) ...[
                const SizedBox(height: 10),
                // Select-all toggle row
                Row(
                  children: [
                    Checkbox(
                      value:
                          _bulkSelectedClaimIds.length == matchingClaims.length,
                      tristate: true,
                      activeColor: AppColors.primary,
                      onChanged: (_) => setState(() {
                        if (_bulkSelectedClaimIds.length ==
                            matchingClaims.length) {
                          _bulkSelectedClaimIds.clear();
                        } else {
                          _bulkSelectedClaimIds
                            ..clear()
                            ..addAll(matchingClaims.map((c) => c.id));
                        }
                      }),
                    ),
                    Text(
                      _bulkSelectedClaimIds.length == matchingClaims.length
                          ? 'Nyahpilih semua'.tr()
                          : 'Pilih semua (${matchingClaims.length})',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
                // Scrollable checklist of claims
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: matchingClaims.length,
                    itemBuilder: (ctx, i) {
                      final claim = matchingClaims[i];
                      final checked = _bulkSelectedClaimIds.contains(claim.id);
                      return CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        activeColor: AppColors.primary,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: checked,
                        onChanged: (_) => setState(() {
                          if (checked) {
                            _bulkSelectedClaimIds.remove(claim.id);
                          } else {
                            _bulkSelectedClaimIds.add(claim.id);
                          }
                        }),
                        title: Text(
                          claim.citizenName,
                          style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary),
                        ),
                        subtitle: Text(
                          claim.location,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                              fontSize: 10, color: AppColors.textSecondary),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                // Semak Bukti Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _bulkSelectedClaimIds.isEmpty
                        ? null
                        : () => _showBulkPhotoReviewDialog(
                              matchingClaims
                                  .where((c) =>
                                      _bulkSelectedClaimIds.contains(c.id))
                                  .toList(),
                            ),
                    icon: const Icon(Icons.grid_view_rounded, size: 18),
                    label:
                        Text('Semak Bukti (${_bulkSelectedClaimIds.length})'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      disabledForegroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Approve selected button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: (_bulkSelectedClaimIds.isEmpty ||
                            !_photoReviewConfirmed)
                        ? null
                        : () => _bulkApproveSelectedClaims(
                            List.from(_bulkSelectedClaimIds),
                            selectedZone ?? ''),
                    icon: const Icon(Icons.verified_rounded, size: 18),
                    label: Text(
                      _bulkSelectedClaimIds.isEmpty
                          ? 'Pilih tuntutan untuk diluluskan'.tr()
                          : !_photoReviewConfirmed
                              ? 'Sila semak bukti dahulu'.tr()
                              : 'Lulus ${_bulkSelectedClaimIds.length} Tuntutan Terpilih',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _claimMatchesZone(String claimLocation, String zoneName) {
    final location = claimLocation.toLowerCase();
    final zone = zoneName.toLowerCase();
    return location == zone ||
        location.contains(zone) ||
        zone.contains(location);
  }

  Future<void> _bulkApproveSelectedClaims(
      List<String> claimIds, String zoneName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.done_all_rounded, color: AppColors.primary),
            const SizedBox(width: 8),
            Text('Sahkan Kelulusan Pukal'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ],
        ),
        content: Text(
          'Tindakan ini akan meluluskan ${claimIds.length} tuntutan yang dipilih untuk zon "$zoneName". Teruskan?',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.textPrimary),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Batal'.tr(),
                  style: GoogleFonts.inter(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Lulus Semua'.tr(),
                style: GoogleFonts.inter(
                    color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    try {
      final officerId = _currentOfficerId();
      int count = 0;
      for (final id in claimIds) {
        await _firestoreService.updateClaimStatus(id, 'approved',
            officerId: officerId);
        count++;
      }
      if (mounted) {
        setState(() {
          _bulkSelectedClaimIds.clear();
          _photoReviewConfirmed = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content:
                Text('$count tuntutan dalam zon "$zoneName" telah diluluskan.'),
            backgroundColor: AppColors.safe));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal meluluskan tuntutan: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  void _showBulkPhotoReviewDialog(List<ClaimModel> claims) {
    bool isConfirmed = _photoReviewConfirmed;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Semak Bukti Bergambar'.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          content: SizedBox(
            width: double.maxFinite,
            height: 400,
            child: Column(
              children: [
                Expanded(
                  child: GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 0.8,
                    ),
                    itemCount: claims.length,
                    itemBuilder: (context, index) {
                      final claim = claims[index];
                      final isUrl = claim.photoEvidence.startsWith('http');
                      final isBase64 =
                          claim.photoEvidence.startsWith('data:image');
                      Widget imageWidget;

                      if (isUrl) {
                        imageWidget = Image.network(
                          claim.photoEvidence,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_rounded,
                              size: 40,
                              color: Colors.grey),
                        );
                      } else if (isBase64) {
                        try {
                          final base64String =
                              claim.photoEvidence.split(',').last;
                          imageWidget = Image.memory(
                            base64Decode(base64String),
                            fit: BoxFit.cover,
                          );
                        } catch (e) {
                          imageWidget = const Icon(Icons.broken_image_rounded,
                              size: 40, color: Colors.grey);
                        }
                      } else {
                        imageWidget = const Icon(
                            Icons.insert_drive_file_rounded,
                            size: 40,
                            color: Colors.grey);
                      }

                      return GestureDetector(
                        onTap: () => _showImageZoomDialog(
                            claim.photoEvidence, claim.citizenName),
                        child: Container(
                          decoration: BoxDecoration(
                              border: Border.all(color: AppColors.divider),
                              borderRadius: BorderRadius.circular(8)),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              imageWidget,
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 4),
                                  child: Text(
                                    claim.citizenName,
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 10),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CheckboxListTile(
                    value: isConfirmed,
                    activeColor: AppColors.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      'Saya mengesahkan bukti gambar bagi semua tuntutan terpilih telah disemak dan adalah sah'
                          .tr(),
                      style: GoogleFonts.inter(
                          fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    onChanged: (val) {
                      setDialogState(() => isConfirmed = val ?? false);
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Tutup'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                setState(() => _photoReviewConfirmed = isConfirmed);
                Navigator.pop(ctx);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text(isConfirmed
                          ? 'Bukti disahkan. Boleh meluluskan tuntutan.'.tr()
                          : 'Pengesahan ditarik balik.'.tr()),
                      backgroundColor:
                          isConfirmed ? AppColors.safe : AppColors.warning));
                }
              },
              child: Text('Sahkan & Tutup'.tr(),
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      }),
    );
  }

  void _showImageZoomDialog(String photoEvidence, String title) {
    showDialog(
      context: context,
      builder: (ctx) {
        final isUrl = photoEvidence.startsWith('http');
        final isBase64 = photoEvidence.startsWith('data:image');
        Widget img;
        if (isUrl) {
          img = Image.network(
            photoEvidence,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded,
                size: 80, color: Colors.grey),
          );
        } else if (isBase64) {
          try {
            final base64String = photoEvidence.split(',').last;
            img = Image.memory(base64Decode(base64String), fit: BoxFit.contain);
          } catch (_) {
            img = const Icon(Icons.broken_image_rounded,
                size: 80, color: Colors.grey);
          }
        } else {
          img = const Icon(Icons.insert_drive_file_rounded,
              size: 80, color: Colors.grey);
        }
        return AlertDialog(
          backgroundColor: Colors.black,
          contentPadding: EdgeInsets.zero,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          title: Text(title,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          content: Stack(
            children: [
              InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: Center(child: img),
              ),
              Positioned(
                bottom: 12,
                right: 12,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon:
                        const Icon(Icons.download_rounded, color: Colors.white),
                    onPressed: () =>
                        _downloadEvidence(photoEvidence, title, ctx),
                    tooltip: 'Muat Turun Gambar'.tr(),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Tutup'.tr(), style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _downloadEvidence(
      String photoEvidence, String title, BuildContext ctx) async {
    // Show a loading indicator
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (loadingCtx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text('Menyimpan gambar...'.tr()),
          ],
        ),
      ),
    );

    try {
      final isUrl = photoEvidence.startsWith('http');
      final isBase64 = photoEvidence.startsWith('data:image');
      List<int> bytes;

      if (isBase64) {
        bytes = base64Decode(photoEvidence.split(',').last);
      } else if (isUrl) {
        final request = await HttpClient().getUrl(Uri.parse(photoEvidence));
        final response = await request.close();
        final bytesBuilder = BytesBuilder();
        await for (final chunk in response) {
          bytesBuilder.add(chunk);
        }
        bytes = bytesBuilder.takeBytes();
      } else {
        throw 'Format gambar tidak disokong.'.tr();
      }

      final tempDir = await getTemporaryDirectory();
      final extension =
          isBase64 && photoEvidence.contains('image/png') ? 'png' : 'jpg';
      final fileName =
          'bukti_${title.replaceAll(' ', '.tr()_')}_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes);

      // Close the loading dialog
      if (ctx.mounted) {
        Navigator.pop(ctx);
      }

      // Share the file so the user can download/save it native style
      await Share.shareXFiles([XFile(file.path)],
          text: 'Bukti Bergambar - $title');
    } catch (e) {
      // Close the loading dialog
      if (ctx.mounted) {
        Navigator.pop(ctx);
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('Gagal menyimpan gambar: $e'),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }

  String? _currentOfficerId() {
    final state = context.read<AuthBloc>().state;
    return state is AuthAuthenticated ? state.uid : null;
  }

  void _reviewClaim(ClaimModel claim, String actionType) {
    if (actionType == 'approve') {
      bool isConfirmed = false;
      showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: AppColors.safe),
                const SizedBox(width: 8),
                Text('Sahkan Kelulusan'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Adakah anda pasti mahu meluluskan tuntutan bantuan oleh ${claim.citizenName}?',
                    style: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textPrimary)),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: CheckboxListTile(
                    value: isConfirmed,
                    activeColor: AppColors.primary,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                    title: Text(
                      'Saya mengesahkan bukti gambar bagi tuntutan ini telah disemak dan adalah sah'
                          .tr(),
                      style: GoogleFonts.inter(
                          fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    onChanged: (val) {
                      setDialogState(() => isConfirmed = val ?? false);
                    },
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Batal'.tr(),
                      style:
                          GoogleFonts.inter(color: AppColors.textSecondary))),
              ElevatedButton(
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.safe),
                onPressed: isConfirmed
                    ? () {
                        Navigator.pop(ctx);
                        _firestoreService
                            .updateClaimStatus(claim.id, 'approved',
                                officerId: _currentOfficerId())
                            .then((_) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(
                                    'Tuntutan ${claim.citizenName} diluluskan.'),
                                backgroundColor: AppColors.safe));
                          }
                        });
                      }
                    : null,
                child: Text('Ya, Lulus'.tr(),
                    style: GoogleFonts.inter(
                        color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ],
          );
        }),
      );
      return;
    } else if (actionType == 'info') {
      _showInfoRequestWithDeadlineDialog(claim);
      return;
    }

    _showClaimFeedbackDialog(
      claim: claim,
      title: 'Tolak Tuntutan'.tr(),
      actionLabel: 'Tolak'.tr(),
      status: 'rejected',
      color: AppColors.danger,
      hint: 'Nyatakan sebab penolakan'.tr(),
    );
  }

  void _showInfoRequestWithDeadlineDialog(ClaimModel claim) {
    final ctrl = TextEditingController();
    int selectedDays = 3;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Minta Maklumat Tambahan'.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.warning)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                decoration: InputDecoration(
                  hintText:
                      'Contoh: Sila muat naik gambar kerosakan yang lebih jelas.'
                          .tr(),
                  hintStyle: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textHint),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.timer_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Text('Tarikh akhir respons:'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  DropdownButton<int>(
                    value: selectedDays,
                    items: [
                      DropdownMenuItem(value: 2, child: Text('2 hari'.tr())),
                      DropdownMenuItem(value: 3, child: Text('3 hari'.tr())),
                      DropdownMenuItem(value: 4, child: Text('4 hari'.tr())),
                      DropdownMenuItem(value: 5, child: Text('5 hari'.tr())),
                    ],
                    onChanged: (v) {
                      if (v != null) setS(() => selectedDays = v);
                    },
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Batal'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary))),
            ElevatedButton(
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.warning),
              onPressed: () {
                if (ctrl.text.isEmpty) return;
                final deadline =
                    DateTime.now().add(Duration(days: selectedDays));
                Navigator.pop(ctx);
                _firestoreService
                    .updateClaimStatus(
                  claim.id,
                  'under_review',
                  reason: ctrl.text.trim(),
                  officerId: _currentOfficerId(),
                  infoDeadline: deadline,
                )
                    .then((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(
                            'Permintaan maklumat dihantar. Tarikh akhir: $selectedDays hari.'),
                        backgroundColor: AppColors.warning));
                  }
                }).catchError((e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Ralat: $e'),
                        backgroundColor: AppColors.danger));
                  }
                });
              },
              child: Text('Hantar'.tr(),
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      }),
    ).then((_) => ctrl.dispose());
  }

  void _showClaimFeedbackDialog({
    required ClaimModel claim,
    required String title,
    required String actionLabel,
    required String status,
    required Color color,
    required String hint,
  }) {
    String selectedReason = 'Bukti Gambar Tidak Jelas / Ralat'.tr();
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        final isOther = selectedReason == 'Lain-lain (Nyatakan)'.tr();
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(title,
              style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700, color: color)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pilih sebab penolakan:'.tr(),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedReason,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
                items: [
                  DropdownMenuItem(
                      value: 'Bukti Gambar Tidak Jelas / Ralat'.tr(),
                      child: Text('Bukti Gambar Tidak Jelas / Ralat'.tr())),
                  DropdownMenuItem(
                      value: 'Tuntutan Bertindih (Duplicate IC)'.tr(),
                      child: Text('Tuntutan Bertindih (Duplicate IC)'.tr())),
                  DropdownMenuItem(
                      value: 'Alamat di Luar Zon Bencana'.tr(),
                      child: Text('Alamat di Luar Zon Bencana'.tr())),
                  DropdownMenuItem(
                      value: 'Bawah Umur & Tiada Wali Sah'.tr(),
                      child: Text('Bawah Umur & Tiada Wali Sah'.tr())),
                  DropdownMenuItem(
                      value: 'Kerosakan Tidak Memenuhi Syarat Kelayakan'.tr(),
                      child: Text(
                          'Kerosakan Tidak Memenuhi Syarat Kelayakan'.tr())),
                  DropdownMenuItem(
                      value: 'Lain-lain (Nyatakan)'.tr(),
                      child: Text('Lain-lain (Nyatakan)'.tr())),
                ],
                onChanged: (v) {
                  if (v != null) {
                    setDialogState(() {
                      selectedReason = v;
                    });
                  }
                },
              ),
              if (isOther) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: 'Sila nyatakan sebab...'.tr(),
                    hintStyle: GoogleFonts.inter(
                        fontSize: 13, color: AppColors.textHint),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  maxLines: 3,
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Batal'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: color),
              onPressed: () {
                final reasonText = isOther ? ctrl.text.trim() : selectedReason;
                if (isOther && reasonText.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text('Sila nyatakan sebab penolakan.'.tr()),
                    backgroundColor: AppColors.danger,
                  ));
                  return;
                }
                Navigator.pop(ctx);
                _firestoreService
                    .updateClaimStatus(
                  claim.id,
                  status,
                  reason: reasonText,
                  officerId: _currentOfficerId(),
                )
                    .then((_) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(status == 'rejected'
                            ? 'Tuntutan ${claim.citizenName} ditolak.'
                            : 'Permintaan maklumat tambahan dihantar kepada ${claim.citizenName}.'),
                        backgroundColor: color));
                  }
                });
              },
              child: Text(actionLabel,
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      }),
    );
  }

  // ── IC validation helpers ───────────────────────────────────────────────
  static final _icRegex = RegExp(r'^\d{6}-\d{2}-\d{4}$');

  bool _isValidIC(String ic) => _icRegex.hasMatch(ic.trim());

  /// Returns age in years from Malaysian IC (YYMMDD prefix). Returns null if unparseable.
  int? _ageFromIC(String ic) {
    try {
      final digits = ic.replaceAll('-', '.tr()');
      final yy = int.parse(digits.substring(0, 2));
      final mm = int.parse(digits.substring(2, 4));
      final dd = int.parse(digits.substring(4, 6));
      final now = DateTime.now();
      // Assume YY >= 00: if yy > current 2-digit year, born in 1900s
      final year = yy > (now.year % 100) ? 1900 + yy : 2000 + yy;
      final birth = DateTime(year, mm, dd);
      int age = now.year - birth.year;
      if (now.month < birth.month ||
          (now.month == birth.month && now.day < birth.day)) {
        age--;
      }
      return age;
    } catch (_) {
      return null;
    }
  }

  /// Returns true if claim location doesn't match any declared zone name.
  bool _isOutsideDeclaredZones(String location) {
    if (_disasterZoneNames.isEmpty) return false;
    return !_disasterZoneNames.any((zone) => _claimMatchesZone(location, zone));
  }

  Widget _claimCard(ClaimModel claim) {
    // ── Auto-reject household > 15 (one-shot) ──────────────────────
    if (claim.householdSize > 15 &&
        !_autoRejectedClaimIds.contains(claim.id) &&
        claim.status == 'submitted') {
      _autoRejectedClaimIds.add(claim.id);
      Future.microtask(() => _firestoreService.updateClaimStatus(
            claim.id,
            'rejected',
            reason:
                'Auto-tolak: Saiz isi rumah melebihi had maksimum (15 orang). Sila hubungi pejabat.'
                    .tr(),
            officerId: _currentOfficerId(),
          ));
    }

    // ── Auto-expire info requests past deadline (one-shot) ─────────
    if (claim.status == 'under_review' &&
        claim.infoDeadline != null &&
        DateTime.now().isAfter(claim.infoDeadline!) &&
        !_autoExpiredClaimIds.contains(claim.id)) {
      _autoExpiredClaimIds.add(claim.id);
      Future.microtask(() => _firestoreService.updateClaimStatus(
            claim.id,
            'expired',
            officerId: _currentOfficerId(),
          ));
    }

    // ── Duplicate IC check (async, cached) ─────────────────────────
    if (!_duplicateICCache.containsKey(claim.id) &&
        _isValidIC(claim.icNumber)) {
      _duplicateICCache[claim.id] = false; // placeholder
      _firestoreService.checkDuplicateICInZone(claim.icNumber).then((dupes) {
        final hasDupe = dupes.any((d) => d['id'] != claim.id);
        if (mounted && _duplicateICCache[claim.id] != hasDupe) {
          setState(() => _duplicateICCache[claim.id] = hasDupe);
        }
      });
    }

    // ── Derived state ───────────────────────────────────────────────
    final isInfoRequested = claim.status == 'under_review';
    final isExpired = claim.status == 'expired';
    final validIC = _isValidIC(claim.icNumber);
    final age = validIC ? _ageFromIC(claim.icNumber) : null;
    final isUnderAge = age != null && age < 18;
    final isLargeHousehold = claim.householdSize > 10;
    final isAutoRejected = claim.householdSize > 15;
    final isOutOfZone = _isOutsideDeclaredZones(claim.location);
    final hasDuplicateIC = _duplicateICCache[claim.id] ?? false;
    final canApprove =
        validIC && !isUnderAge && !hasDuplicateIC && !isAutoRejected;
    // True when citizen has resubmitted after an info request
    final citizenResubmitted =
        claim.status == 'submitted' && claim.citizenUpdatedAt != null;

    // Deadline countdown
    String? deadlineText;
    bool deadlinePassed = false;
    if (claim.infoDeadline != null) {
      final diff = claim.infoDeadline!.difference(DateTime.now());
      if (diff.isNegative) {
        deadlinePassed = true;
        deadlineText = 'TAMAT TEMPOH'.tr();
      } else {
        final days = diff.inDays;
        deadlineText =
            days > 0 ? 'Respon dalam $days hari lagi' : 'Respon hari ini'.tr();
      }
    }

    Color statusColor = isExpired
        ? Colors.grey
        : isInfoRequested
            ? Colors.purple
            : citizenResubmitted
                ? AppColors.safe
                : AppColors.warning;
    String statusLabel = isExpired
        ? 'Tamat Tempoh'.tr()
        : isInfoRequested
            ? 'Info Diminta'.tr()
            : citizenResubmitted
                ? 'Respons Diterima ✓'.tr()
                : 'Menunggu'.tr();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isAutoRejected
                  ? AppColors.danger.withValues(alpha: 0.4)
                  : AppColors.divider)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(claim.citizenName,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary)),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(99)),
                child: Text(statusLabel,
                    style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: statusColor)),
              ),
            ],
          ),
          // ── Validation banners ─────────────────────────────────
          if (hasDuplicateIC) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: AppColors.danger.withValues(alpha: 0.3))),
              child: Row(children: [
                const Icon(Icons.warning_rounded,
                    color: AppColors.danger, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'IC ini telah mempunyai tuntutan diluluskan dalam 30 hari lepas.'
                          .tr(),
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.danger,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
          if (!validIC) ...[
            const SizedBox(height: 8),
            _claimBadge('Format IC Tidak Sah'.tr(), Colors.orange),
          ],
          if (validIC && isUnderAge) ...[
            const SizedBox(height: 8),
            _claimBadge(
                'Bawah Umur ($age thn) — Wali Diperlukan', Colors.amber[700]!),
          ],
          if (isLargeHousehold && !isAutoRejected) ...[
            const SizedBox(height: 8),
            _claimBadge(
                'Saiz Besar (${claim.householdSize} org) — Semak Lanjut',
                Colors.orange),
          ],
          if (isAutoRejected) ...[
            const SizedBox(height: 8),
            _claimBadge(
                'Auto-Tolak: Saiz Melebihi Had (${claim.householdSize} org)',
                AppColors.danger),
          ],
          if (isOutOfZone) ...[
            const SizedBox(height: 8),
            _claimBadge('Di Luar Zon Bencana Diisytiharkan ⚠️'.tr(),
                Colors.amber[800]!),
          ],
          if (citizenResubmitted) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                  color: AppColors.safe.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: AppColors.safe.withValues(alpha: 0.4))),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.safe, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                      'Pemohon telah menghantar semula bukti dan maklumat kemaskini. Sila semak bukti terbaru.'
                          .tr(),
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppColors.safe,
                          fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
          ],
          const SizedBox(height: 8),
          // ── Claim type + location ──────────────────────────────
          Row(
            children: [
              const Icon(Icons.receipt_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(claim.type,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.location_on_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(claim.location,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
          const SizedBox(height: 12),
          // ── IC + household ─────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.badge_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('IC: ${claim.icNumber}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textPrimary)),
              const SizedBox(width: 16),
              const Icon(Icons.family_restroom_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text('Isi Rumah: ${claim.householdSize}',
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textPrimary)),
            ],
          ),
          const SizedBox(height: 6),
          // ── Bank Info + KIR ────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.account_balance_rounded,
                  size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                    'Bank: ${claim.bankName ?? '-'} (${claim.bankAccountNumber ?? '-'})',
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textPrimary)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(
                  claim.isKIR
                      ? Icons.verified_user_rounded
                      : Icons.cancel_rounded,
                  size: 14,
                  color: claim.isKIR ? AppColors.safe : AppColors.danger),
              const SizedBox(width: 6),
              Text(
                  claim.isKIR ? 'Ketua Isi Rumah (KIR)'.tr() : 'Bukan KIR'.tr(),
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      color: claim.isKIR ? AppColors.safe : AppColors.danger,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 14, color: AppColors.danger),
              const SizedBox(width: 6),
              Expanded(
                  child: Text('Kerosakan: ${claim.damageDescription}',
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textPrimary))),
            ],
          ),
          // ── Info request reason + deadline ─────────────────────
          if (claim.infoRequestReason != null &&
              claim.infoRequestReason!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Maklumat diminta: ${claim.infoRequestReason}',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          color: Colors.purple,
                          fontWeight: FontWeight.w600)),
                  if (deadlineText != null) ...[
                    const SizedBox(height: 4),
                    Text(deadlineText,
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: deadlinePassed
                                ? AppColors.danger
                                : Colors.purple[400])),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.hourglass_empty_rounded,
                          size: 12, color: Colors.purple),
                      const SizedBox(width: 4),
                      Text('Menunggu respons daripada pemohon...'.tr(),
                          style: GoogleFonts.inter(
                              fontSize: 11,
                              fontStyle: FontStyle.italic,
                              color: Colors.purple[700])),
                    ],
                  ),
                ],
              ),
            ),
          ],
          // ── Photo evidence ─────────────────────────────────────
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () =>
                _showImageZoomDialog(claim.photoEvidence, claim.citizenName),
            child: Container(
              height: 110,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                children: [
                  // Image
                  if (claim.photoEvidence.startsWith('http'))
                    Image.network(
                      claim.photoEvidence,
                      width: double.infinity,
                      height: 110,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Center(
                        child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.broken_image_rounded,
                                  color: Colors.grey, size: 32),
                              const SizedBox(height: 4),
                              Text('Gagal muat gambar'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 11, color: Colors.grey)),
                            ]),
                      ),
                    )
                  else if (claim.photoEvidence.startsWith('data:image'))
                    Builder(builder: (_) {
                      try {
                        return Image.memory(
                          base64Decode(claim.photoEvidence.split(',').last),
                          width: double.infinity,
                          height: 110,
                          fit: BoxFit.cover,
                        );
                      } catch (_) {
                        return const Center(
                            child: Icon(Icons.broken_image_rounded,
                                color: Colors.grey, size: 32));
                      }
                    })
                  else
                    Center(
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.insert_drive_file_rounded,
                                color: Colors.grey, size: 32),
                            const SizedBox(height: 4),
                            Text('Tiada gambar'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 11, color: Colors.grey)),
                          ]),
                    ),
                  // "Tap to view" overlay
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      color: Colors.black54,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.zoom_in_rounded,
                              color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text('Ketik untuk perbesar'.tr(),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.white,
                                  fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // ── Action buttons ─────────────────────────────────────
          if (!isAutoRejected && !isExpired) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _reviewClaim(claim, 'reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Tolak'.tr(), style: TextStyle(fontSize: 12)),
                  ),
                ),
                if (!isInfoRequested) ...[
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reviewClaim(claim, 'info'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text('Info'.tr(), style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canApprove
                        ? () {
                            if (isOutOfZone) {
                              _approveWithOutOfZoneDialog(claim);
                            } else {
                              _reviewClaim(claim, 'approve');
                            }
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.safe,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey[300],
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('Lulus'.tr(), style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _reviewClaim(claim, 'reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: Text('Tolak'.tr(), style: TextStyle(fontSize: 12)),
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _claimBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 12, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(text,
                style: GoogleFonts.inter(
                    fontSize: 11, fontWeight: FontWeight.w600, color: color)),
          ),
        ],
      ),
    );
  }

  void _approveWithOutOfZoneDialog(ClaimModel claim) {
    String selectedReason = 'Berkaitan Bencana'.tr();
    bool isConfirmed = false;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setDialogState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Lulus Di Luar Zon'.tr(),
              style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Colors.amber[800])),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Tuntutan ini berada di luar zon bencana yang diisytiharkan. Pilih sebab kelulusan:'
                      .tr(),
                  style: GoogleFonts.inter(fontSize: 13)),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedReason,
                decoration: InputDecoration(
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true),
                items: [
                  DropdownMenuItem(
                      value: 'Berkaitan Bencana'.tr(),
                      child: Text('Berkaitan Bencana'.tr())),
                  DropdownMenuItem(
                      value: 'Kes Khas'.tr(), child: Text('Kes Khas'.tr())),
                  DropdownMenuItem(
                      value: 'Ralat Lokasi'.tr(),
                      child: Text('Ralat Lokasi'.tr())),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => selectedReason = v);
                },
              ),
              const SizedBox(height: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: CheckboxListTile(
                  value: isConfirmed,
                  activeColor: AppColors.primary,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(
                    'Saya mengesahkan bukti gambar bagi tuntutan ini telah disemak dan adalah sah'
                        .tr(),
                    style: GoogleFonts.inter(
                        fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                  onChanged: (val) {
                    setDialogState(() => isConfirmed = val ?? false);
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Batal'.tr(),
                    style: GoogleFonts.inter(color: AppColors.textSecondary))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.safe),
              onPressed: isConfirmed
                  ? () async {
                      Navigator.pop(ctx);
                      await _firestoreService.updateClaimStatus(
                          claim.id, 'approved',
                          officerId: _currentOfficerId());
                      // Write outOfZoneReason separately
                      await FirebaseFirestore.instance
                          .collection('claims')
                          .doc(claim.id)
                          .update({'outOfZoneReason': selectedReason});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Tuntutan ${claim.citizenName} diluluskan ($selectedReason).'),
                            backgroundColor: AppColors.safe));
                      }
                    }
                  : null,
              child: Text('Lulus'.tr(),
                  style: GoogleFonts.inter(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      }),
    );
  }

  // ─── SHARED HELPERS ───────────────────────────────────────────────

  ImageProvider? _getAvatarProvider() {
    if (_profileImageUrl != null && _profileImageUrl!.isNotEmpty) {
      if (_profileImageUrl!.startsWith('data:image')) {
        final base64Str = _profileImageUrl!.split(',').last;
        return MemoryImage(base64Decode(base64Str));
      }
      return NetworkImage(_profileImageUrl!);
    }
    return null;
  }

  Widget _buildCommandCard(String name) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0E7490), AppColors.officerAccent],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.officerAccent.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Pusat Kawalan Operasi'.tr(),
                        style: GoogleFonts.inter(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(name.isNotEmpty ? name : 'Pegawai SIGAP'.tr(),
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => context
                    .push(AppRoutes.officerProfile)
                    .then((_) => _loadOfficerData()),
                child: Hero(
                  tag: 'officer_avatar',
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      backgroundImage: _getAvatarProvider(),
                      child: (_profileImageUrl == null ||
                              _profileImageUrl!.isEmpty)
                          ? const Icon(Icons.person_rounded,
                              color: Colors.white, size: 30)
                          : null,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _statusPill(Icons.circle, '4 Daerah Aktif', Colors.amber),
              const SizedBox(width: 8),
              _statusPill(Icons.warning_rounded, 'Darurat Ditetapkan'.tr(),
                  Colors.redAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statusPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        _statCard(
            '247', 'Jumlah SOS'.tr(), AppColors.danger, Icons.sos_rounded),
        const SizedBox(width: 12),
        _statCard(
            '38', 'Sukarelawan'.tr(), AppColors.safe, Icons.handshake_rounded),
        const SizedBox(width: 12),
        _statCard(
            '12', 'Zon Aktif'.tr(), AppColors.officerAccent, Icons.map_rounded),
      ],
    );
  }

  Widget _statCard(String value, String label, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 12),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            Text(label,
                style: GoogleFonts.inter(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t,
            style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );

  IconData _typeIcon(String type) {
    switch (type) {
      case 'Banjir':
        return Icons.water_rounded;
      case 'Kebakaran':
        return Icons.local_fire_department_rounded;
      case 'Tanah Runtuh':
        return Icons.landscape_rounded;
      case 'Perubatan':
      case 'Kecemasan Perubatan':
        return Icons.medical_services_rounded;
      case 'Orang Hilang':
        return Icons.person_search_rounded;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // DONATION CAMPAIGN MANAGEMENT (Officer)
  // ─────────────────────────────────────────────────────────────────────────────

  /// Builds a rich campaign management card for the officer home tab.
  Widget _donationCampaignCard(CampaignModel campaign) {
    final isClosed = campaign.isClosed;
    final progress = campaign.progressFraction;

    return Container(
      height: 240,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isClosed
              ? AppColors.divider
              : AppColors.primary.withValues(alpha: 0.25),
          width: isClosed ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status badge
          SizedBox(
            height: 38,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    campaign.name,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2.0),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isClosed
                          ? AppColors.divider
                          : AppColors.safe.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      isClosed ? 'Ditutup'.tr() : 'Aktif'.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color:
                            isClosed ? AppColors.textSecondary : AppColors.safe,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // Purpose text
          SizedBox(
            height: 30,
            child: Text(
              campaign.purpose,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(height: 10),

          // Amount + percent
          SizedBox(
            height: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'RM ${_fmtAmount(campaign.currentAmount)}',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isClosed
                        ? AppColors.textSecondary
                        : AppColors.officerAccent,
                  ),
                ),
                Text(
                  '${campaign.progressPercent}% / RM ${_fmtAmount(campaign.targetAmount)}',
                  style: GoogleFonts.inter(
                      fontSize: 11, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          // Progress bar
          SizedBox(
            height: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: AppColors.divider,
                valueColor: AlwaysStoppedAnimation<Color>(
                  isClosed ? AppColors.textSecondary : AppColors.officerAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Allocation chips (Standardized height of 24px)
          if (campaign.allocations.isNotEmpty)
            SizedBox(
              height: 24,
              child: ListView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                children: campaign.allocations.entries.take(4).map((e) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.officerAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color:
                                AppColors.officerAccent.withValues(alpha: 0.2)),
                      ),
                      child: Center(
                        child: Text(
                          '${e.key} ${e.value.toStringAsFixed(0)}%',
                          style: GoogleFonts.inter(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.officerAccent),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            )
          else
            const SizedBox(height: 24),

          const Spacer(),

          // Action buttons (Standardized height of 34px)
          if (!isClosed)
            SizedBox(
              height: 34,
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _allocateFundsDialog(campaign),
                      icon: const Icon(Icons.pie_chart_rounded, size: 14),
                      label: Text('Peruntuk'.tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.officerAccent,
                        side: const BorderSide(color: AppColors.officerAccent),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        textStyle: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _closeCampaignDialog(campaign),
                      icon: const Icon(Icons.lock_rounded, size: 14),
                      label: Text('Tutup'.tr()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        elevation: 0,
                        textStyle: GoogleFonts.inter(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            SizedBox(
              width: double.infinity,
              height: 34,
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Kempen ini telah ditutup'.tr(),
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                      fontStyle: FontStyle.italic),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Dialog to create a new donation campaign.
  void _createCampaignDialog() {
    final nameCtrl = TextEditingController();
    final purposeCtrl = TextEditingController();
    final targetCtrl = TextEditingController();
    final imageCtrl = TextEditingController();
    bool isSubmitting = false;

    // Dynamic allocation key-value pairs
    final allocationKeys = [TextEditingController()];
    final allocationVals = [TextEditingController()];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.campaign_rounded,
                        color: AppColors.officerAccent, size: 22),
                    const SizedBox(width: 10),
                    Text('Cipta Kempen Baru'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 17, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 20),
                _officerField('Nama Kempen'.tr(), nameCtrl,
                    hint: 'Contoh: Tabung Banjir Kelantan 2025'.tr()),
                const SizedBox(height: 12),
                _officerField('Tujuan / Keterangan'.tr(), purposeCtrl,
                    hint: 'Terangkan tujuan kempen ini...'.tr(), maxLines: 3),
                const SizedBox(height: 12),
                _officerField('Sasaran Jumlah (RM)'.tr(), targetCtrl,
                    hint: '50000', keyboardType: TextInputType.number),
                const SizedBox(height: 12),
                _officerField('URL Imej Kempen (Pilihan)'.tr(), imageCtrl,
                    hint: 'https://...'),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text('Pengagihan Dana (%)'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          allocationKeys.add(TextEditingController());
                          allocationVals.add(TextEditingController());
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text('Tambah'.tr()),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.officerAccent,
                        textStyle: GoogleFonts.inter(
                            fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(allocationKeys.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: allocationKeys[i],
                            decoration: InputDecoration(
                              hintText: 'Kategori (cth: Makanan)'.tr(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: allocationVals[i],
                            decoration: InputDecoration(
                              hintText: '%',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                        if (allocationKeys.length > 1)
                          IconButton(
                            onPressed: () {
                              setModalState(() {
                                allocationKeys.removeAt(i);
                                allocationVals.removeAt(i);
                              });
                            },
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: AppColors.danger,
                                size: 20),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final name = nameCtrl.text.trim();
                            final purpose = purposeCtrl.text.trim();
                            final target =
                                double.tryParse(targetCtrl.text) ?? 0.0;

                            if (name.isEmpty ||
                                purpose.isEmpty ||
                                target <= 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                      content: Text(
                                          'Sila lengkapkan semua medan wajib.'
                                              .tr())));
                              return;
                            }

                            // Build allocation map
                            final Map<String, double> allocations = {};
                            for (int i = 0; i < allocationKeys.length; i++) {
                              final key = allocationKeys[i].text.trim();
                              final val =
                                  double.tryParse(allocationVals[i].text) ??
                                      0.0;
                              if (key.isNotEmpty && val > 0) {
                                allocations[key] = val;
                              }
                            }

                            setModalState(() => isSubmitting = true);
                            await _firestoreService.createCampaign({
                              'name': name,
                              'purpose': purpose,
                              'targetAmount': target,
                              'currentAmount': 0.0,
                              'allocations': allocations,
                              'status': 'active',
                              if (imageCtrl.text.trim().isNotEmpty)
                                'imageUrl': imageCtrl.text.trim(),
                            });
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content:
                                      Text('Kempen "$name" berjaya dicipta!'),
                                  backgroundColor: AppColors.safe,
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.officerAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text('Cipta Kempen'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Dialog to edit fund allocation percentages of an existing campaign.
  void _allocateFundsDialog(CampaignModel campaign) {
    // Pre-fill existing allocations
    final keys = campaign.allocations.keys
        .map((k) => TextEditingController(text: k))
        .toList();
    final vals = campaign.allocations.values
        .map((v) => TextEditingController(text: v.toStringAsFixed(0)))
        .toList();
    if (keys.isEmpty) {
      keys.add(TextEditingController());
      vals.add(TextEditingController());
    }
    bool isSaving = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Container(
          padding:
              EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Icon(Icons.pie_chart_rounded,
                        color: AppColors.officerAccent, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Kemaskini Pengagihan Dana'.tr(),
                        style: GoogleFonts.poppins(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(campaign.name,
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Kategori & Peratus'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    TextButton.icon(
                      onPressed: () {
                        setModalState(() {
                          keys.add(TextEditingController());
                          vals.add(TextEditingController());
                        });
                      },
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text('Tambah'.tr()),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.officerAccent),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(keys.length, (i) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: keys[i],
                            decoration: InputDecoration(
                              hintText: 'Kategori'.tr(),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: vals[i],
                            decoration: InputDecoration(
                              hintText: '%',
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            keyboardType: TextInputType.number,
                            style: GoogleFonts.inter(fontSize: 12),
                          ),
                        ),
                        if (keys.length > 1)
                          IconButton(
                            onPressed: () {
                              setModalState(() {
                                keys.removeAt(i);
                                vals.removeAt(i);
                              });
                            },
                            icon: const Icon(
                                Icons.remove_circle_outline_rounded,
                                color: AppColors.danger,
                                size: 20),
                          ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final Map<String, double> newAllocations = {};
                            for (int i = 0; i < keys.length; i++) {
                              final k = keys[i].text.trim();
                              final v = double.tryParse(vals[i].text) ?? 0.0;
                              if (k.isNotEmpty && v > 0) newAllocations[k] = v;
                            }
                            setModalState(() => isSaving = true);
                            await _firestoreService.updateCampaign(
                                campaign.id, {'allocations': newAllocations});
                            if (mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                      'Pengagihan dana berjaya dikemaskini.'
                                          .tr()),
                                  backgroundColor: AppColors.safe,
                                ),
                              );
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.officerAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text('Simpan Perubahan'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Confirm dialog to close a campaign.
  void _closeCampaignDialog(CampaignModel campaign) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.lock_rounded, color: AppColors.danger, size: 20),
            const SizedBox(width: 8),
            Text('Tutup Kempen'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              campaign.name,
              style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 8),
            Text(
              'Kempen ini akan ditutup dan tidak lagi menerima sumbangan baru. Rekod derma sedia ada kekal disimpan.\n\nAdakah anda pasti?'
                  .tr(),
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warningLight,
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: AppColors.warning, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tindakan ini tidak boleh diundur.'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Batal'.tr(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _firestoreService.closeCampaign(campaign.id);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Kempen "${campaign.name}" telah ditutup.'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: Text('Ya, Tutup Kempen'.tr(),
                style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  /// Helper text field for officer dialogs.
  Widget _officerField(
    String label,
    TextEditingController ctrl, {
    String hint = '',
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hint,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                    color: AppColors.officerAccent, width: 1.5)),
          ),
          style: GoogleFonts.inter(fontSize: 13),
        ),
      ],
    );
  }

  String _fmtAmount(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}J';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }
}

class _SquadDispatchDialog extends StatefulWidget {
  final List<String> dynamicZones;
  final Map<String, LatLng> zoneCoordinatesMap;
  final String initialSquad;
  final LatLng Function(String) fallbackCoordinates;
  final Future<void> Function(Map<String, dynamic>) onCreateTask;

  const _SquadDispatchDialog({
    required this.dynamicZones,
    required this.zoneCoordinatesMap,
    required this.initialSquad,
    required this.fallbackCoordinates,
    required this.onCreateTask,
  });

  @override
  State<_SquadDispatchDialog> createState() => _SquadDispatchDialogState();
}

class _SquadDispatchDialogState extends State<_SquadDispatchDialog> {
  late String selectedSquad;
  late String selectedZone;
  String selectedPriority = 'Sederhana'.tr();
  int selectedVolunteerCount = 4;

  late TextEditingController squadCtrl;
  late TextEditingController taskCtrl;
  late TextEditingController etaCtrl;

  @override
  void initState() {
    super.initState();
    selectedSquad = widget.initialSquad;
    selectedZone = widget.dynamicZones.first;
    squadCtrl = TextEditingController(text: selectedSquad);
    taskCtrl = TextEditingController();
    etaCtrl = TextEditingController(text: '15 min');
  }

  @override
  void dispose() {
    squadCtrl.dispose();
    taskCtrl.dispose();
    etaCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Agih Skuad Baru'.tr(),
          style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppColors.volunteerAccent)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Squad selector ──────────────────────────────────────
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  labelText: 'Pilih Jenis Skuad'.tr()),
              initialValue: selectedSquad,
              items: [
                DropdownMenuItem(
                    value: 'Skuad Alpha (Penyelamat)'.tr(),
                    child: Text('Skuad Alpha (Penyelamat)'.tr())),
                DropdownMenuItem(
                    value: 'Skuad Bravo (Pembersihan)'.tr(),
                    child: Text('Skuad Bravo (Pembersihan)'.tr())),
                DropdownMenuItem(
                    value: 'Skuad Charlie (Logistik)'.tr(),
                    child: Text('Skuad Charlie (Logistik)'.tr())),
                DropdownMenuItem(
                    value: 'Skuad Delta (Perubatan)'.tr(),
                    child: Text('Skuad Delta (Perubatan)'.tr())),
                DropdownMenuItem(
                    value: 'Skuad Echo (Dapur Jalanan)'.tr(),
                    child: Text('Skuad Echo (Dapur Jalanan)'.tr())),
                DropdownMenuItem(
                    value: 'Skuad Foxtrot (Komunikasi)'.tr(),
                    child: Text('Skuad Foxtrot (Komunikasi)'.tr())),
              ],
              onChanged: (v) {
                if (v != null) {
                  setState(() {
                    selectedSquad = v;
                    squadCtrl.text = v;
                  });
                }
              },
            ),
            const SizedBox(height: 12),
            // ── Zone selector ───────────────────────────────────────
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  labelText: 'Lokasi Tugasan'.tr()),
              initialValue: selectedZone,
              items: widget.dynamicZones
                  .map((z) => DropdownMenuItem(
                      value: z,
                      child: Text(z, overflow: TextOverflow.ellipsis)))
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => selectedZone = v);
                }
              },
            ),
            const SizedBox(height: 12),
            // ── Priority selector ───────────────────────────────────
            DropdownButtonFormField<String>(
              isExpanded: true,
              decoration: InputDecoration(
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  labelText: 'Keutamaan Insiden'.tr()),
              initialValue: selectedPriority,
              items: [
                DropdownMenuItem(
                    value: 'Kritikal'.tr(), child: Text('Kritikal'.tr())),
                DropdownMenuItem(
                    value: 'Tinggi'.tr(), child: Text('Tinggi'.tr())),
                DropdownMenuItem(
                    value: 'Sederhana'.tr(), child: Text('Sederhana'.tr())),
                DropdownMenuItem(
                    value: 'Rendah'.tr(), child: Text('Rendah'.tr())),
              ],
              onChanged: (v) {
                if (v != null) setState(() => selectedPriority = v);
              },
            ),
            const SizedBox(height: 16),

            // ── Volunteer count slider ────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded,
                          size: 15, color: AppColors.volunteerAccent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('Bilangan Sukarelawan Diperlukan'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.volunteerAccent)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                      color: AppColors.volunteerAccent,
                      borderRadius: BorderRadius.circular(99)),
                  child: Text('$selectedVolunteerCount orang',
                      style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
              ],
            ),
            Slider(
              value: selectedVolunteerCount.toDouble(),
              min: 2,
              max: 8,
              divisions: 6,
              activeColor: AppColors.volunteerAccent,
              label: '$selectedVolunteerCount orang',
              onChanged: (v) =>
                  setState(() => selectedVolunteerCount = v.round()),
            ),
            // ── Task description ────────────────────────────────────
            TextField(
              controller: taskCtrl,
              decoration: InputDecoration(
                  labelText: 'Tugasan Khusus'.tr(),
                  hintText: 'Terangkan tugasan skuad ini...'.tr(),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8))),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            // ── ETA ──────────────────────────────────────────────────
            TextField(
              controller: etaCtrl,
              decoration: InputDecoration(
                  labelText: 'Anggaran Tiba (ETA)'.tr(),
                  hintText: 'Contoh: 15 min'.tr(),
                  prefixIcon: const Icon(Icons.timer_outlined, size: 18),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8))),
            ),

            // ── Info about squad assignment ─────────────────────────
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 14, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tugasan ini hanya akan dilihat oleh sukarelawan yang dipilih'
                          .tr(),
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.warning),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: Text('Batal'.tr(),
                style: GoogleFonts.inter(color: AppColors.textSecondary))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.volunteerAccent),
          onPressed: () async {
            if (taskCtrl.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Sila masukkan tugasan khusus.'.tr())));
              return;
            }
            final coords = widget.zoneCoordinatesMap[selectedZone] ??
                widget.fallbackCoordinates(selectedZone);
            // Create squadId from squad name
            final squadId = selectedSquad
                .toLowerCase()
                .replaceAll('(', '.tr()')
                .replaceAll(')', '.tr()')
                .replaceAll(' ', '.tr()_');

            print('Creating task with squadId: $squadId, zone: $selectedZone');

            final model = VolunteerTaskModel(
              id: '',
              squadName: selectedSquad,
              squadId: squadId,
              zone: selectedZone,
              priority: selectedPriority,
              status: 'Menuju ke Lokasi'.tr(),
              progress: 0.1,
              taskDescription: taskCtrl.text.trim(),
              assignedVolunteer: selectedSquad,
              eta: etaCtrl.text.trim().isEmpty ? '-' : etaCtrl.text.trim(),
              lastKnownLocation: selectedZone,
              currentLat: coords.latitude,
              currentLng: coords.longitude,
              requiredVolunteerCount: selectedVolunteerCount,
              acceptedVolunteerUIDs: const [],
              declinedVolunteerUIDs: const [],
            );

            final messenger = ScaffoldMessenger.of(context);
            final navigator = Navigator.of(context);

            try {
              await widget.onCreateTask(model.toMap());
              if (mounted) {
                navigator.pop();
                messenger.showSnackBar(SnackBar(
                    content: Text('Skuad berjaya diagihkan!'.tr()),
                    backgroundColor: AppColors.volunteerAccent));
              }
            } catch (e) {
              if (mounted) {
                messenger.showSnackBar(SnackBar(
                    content: Text('Gagal mengagihkan skuad: $e'),
                    backgroundColor: AppColors.danger));
              }
            }
          },
          child: Text('Agih Pasukan'.tr(),
              style: GoogleFonts.inter(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}
