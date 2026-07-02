import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:printing/printing.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../models/sos_report_model.dart';
import '../../models/volunteer_task_model.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import '../../services/notification_service.dart';
import '../../services/awanis_service.dart';
import '../../services/certificate_service.dart';
import '../../widgets/common/sigap_app_bar.dart';
import 'certificate_redemption_success_screen.dart';
import '../../core/constants/app_strings.dart';


class VolunteerDashboard extends StatefulWidget {
  const VolunteerDashboard({super.key});

  @override
  State<VolunteerDashboard> createState() => _VolunteerDashboardState();
}

class _VolunteerDashboardState extends State<VolunteerDashboard> {
  final _firestoreService = FirestoreService();
  final _locationService = LocationService();

  int _currentIndex = 0;
  String _assignedSquad = '';
  String _assignedSquadId = '';
  bool _isActive = false;
  int _sigapMataPoints = 0;
  bool _isToggling = false;
  String? _profileImageUrl;
  String _skills = '';
  String _fullName = '';
  Position? _currentPosition;
  String _selectedMissionFilter = 'all';

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<QuerySnapshot>? _taskSubscription;
  final Set<String> _seenTaskIds = {};
  final Set<String> _seenSosIds = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _initLocation();
    _initNotificationListeners();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _taskSubscription?.cancel();
    super.dispose();
  }

  void _startLocationTracking(String uid) {
    _positionSubscription?.cancel();
    _positionSubscription = LocationService.getPositionStream().listen((pos) {
      if (mounted && _isActive) {
        setState(() => _currentPosition = pos);
        _firestoreService.updateVolunteerLocation(uid, pos.latitude, pos.longitude);
      }
    });
  }

  void _stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _initNotificationListeners() {
    _taskSubscription = _firestoreService.streamAllVolunteerTasks().listen((snapshot) {
      for (final doc in snapshot.docs) {
        final id = doc.id;
        if (!_seenTaskIds.contains(id)) {
          _seenTaskIds.add(id);
          final data = doc.data() as Map<String, dynamic>;
          final squadName = data['squadName'] as String? ?? 'Tugasan Skuad'.tr();
          final zone = data['zone'] as String? ?? 'Lokasi tidak diketahui'.tr();
          final taskSquadId = data['squadId'] as String? ?? '';
          final taskSquadName = data['squadName'] as String? ?? '';
          
          // Only notify if this task is for the volunteer's squad
          if ((taskSquadId == _assignedSquadId || taskSquadName == _assignedSquad) && _seenTaskIds.length > 1) {
            NotificationService.instance.showLocalNotification(
              title: '📋 Tugasan Skuad Baru: $squadName',
              body: 'Tugasan di $zone untuk skuad anda',
              id: id.hashCode,
            );
          }
        }
      }
    });

    // Keep SOS notifications as is
    _firestoreService.streamActiveSOSReports().listen((snapshot) {
      for (final doc in snapshot.docs) {
        final id = doc.id;
        if (!_seenSosIds.contains(id)) {
          _seenSosIds.add(id);
          final data = doc.data() as Map<String, dynamic>;
          final type = data['type'] as String? ?? 'Kecemasan'.tr();
          final address = data['address'] as String? ?? 'Lokasi tidak diketahui'.tr();
          
          if (_seenSosIds.length > 1) {
            NotificationService.instance.showLocalNotification(
              title: '🆘 SOS Baru: $type',
              body: 'Insiden baru dilaporkan di $address',
              id: id.hashCode,
            );
          }
        }
      }
    });
  }

  Future<void> _initLocation() async {
    try {
      final pos = await _locationService.getCurrentPosition();
      if (mounted) setState(() => _currentPosition = pos);
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    final data = await _firestoreService.getVolunteerProfile(authState.uid);
    if (data != null && mounted) {
      setState(() {
        _isActive = data['isActive'] as bool? ?? false;
        final dbPoints = data['sigapMataPoints'] as int? ?? 0;
        _sigapMataPoints = dbPoints;
        _profileImageUrl = data['profileImageUrl'] as String?;
        _fullName = data['fullName'] as String? ?? authState.displayName ?? '';
        _assignedSquad = data['assignedSquad'] as String? ?? ''; // ADD THIS
        _assignedSquadId = data['assignedSquadId'] as String? ?? ''; // ADD THIS
        final skillsRaw = data['skills'];
        if (skillsRaw is List) {
          _skills = skillsRaw.join(', '.tr());
        } else if (skillsRaw is String) {
          _skills = skillsRaw;
        } else {
          _skills = '';
        }
      });
      print('Profile loaded: _isActive=$_isActive, skills=$_skills');
      if (_isActive) {
        _startLocationTracking(authState.uid);
      }
    }
  }

  Future<void> _toggleAvailability(String uid, bool value) async {
    setState(() {
      _isActive = value;
      _isToggling = true;
    });
    try {
      await _firestoreService.updateVolunteerActiveStatus(uid, value);
      if (value) {
        _startLocationTracking(uid);
        if (_currentPosition != null) {
          _firestoreService.updateVolunteerLocation(uid, _currentPosition!.latitude, _currentPosition!.longitude);
        }
      } else {
        _stopLocationTracking();
      }
    } catch (_) {
      if (mounted) setState(() => _isActive = !value);
    } finally {
      if (mounted) setState(() => _isToggling = false);
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'goodMorning'.tr();
    if (hour < 18) return 'goodAfternoon'.tr();
    return 'goodEvening'.tr();
  }

  @override
  Widget build(BuildContext context) {
    context.locale; // Trigger rebuild on locale change
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final uid = state is AuthAuthenticated ? state.uid : '';
        final name = _fullName.isNotEmpty ? _fullName : (state is AuthAuthenticated ? state.displayName : '');

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: SigapAppBar(
            title:'SIGAP'.tr(),
            showLogout: false,
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined),
                color: AppColors.textSecondary,
                onPressed: () => context.push(AppRoutes.volunteerNotifications),
              ),
              IconButton(
                icon: const Icon(Icons.person_outline_rounded),
                color: AppColors.textSecondary,
                onPressed: () => context.push(AppRoutes.volunteerProfile),
              ),
            ],
          ),
          body: _buildBody(uid, name),
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  Widget _buildBody(String uid, String name) {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab(uid, name);
      case 1:
        return _buildMissionsTab(uid);
      case 2:
        return _buildMapAndProgressTab(uid);
      case 3:
        return _buildLeaderboardPlaceholder();
      case 4:
        return _buildCertificatesTab();
      default:
        return const SizedBox.shrink();
    }
  }

  // ============================================================
  // HOME TAB
  // ============================================================

  Widget _buildHomeTab(String uid, String name) {
    return RefreshIndicator(
      onRefresh: _loadProfile,
      color: AppColors.volunteerAccent,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _buildHeader(name),
          const SizedBox(height: 20),
          _buildAvailabilityCard(uid),
          const SizedBox(height: 20),
          if (_skills.isNotEmpty) _buildSkillsSection(),
          const SizedBox(height: 24),
          _buildSigapMataSection(),
          const SizedBox(height: 24),
          _buildSectionHeader('Misi Berdekatan'.tr()),
          const SizedBox(height: 12),
          _buildNearbyMissionsPreview(),
          const SizedBox(height: 24),
          _buildSectionHeader('Tindakan Pantas'.tr()),
          const SizedBox(height: 12),
          _buildQuickActions(),
          const SizedBox(height: 24),
          _buildSectionHeader('Modul Akses'.tr()),
          const SizedBox(height: 12),
          _buildModuleGrid(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(String name) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.volunteerAccent.withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              color: Colors.white.withValues(alpha: 0.2),
            ),
            child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                ? ClipOval(
                    child: _profileImageUrl!.startsWith('data:image')
                        ? Image.memory(
                            base64Decode(_profileImageUrl!.split(',').last),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.3)),
                              child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                            ),
                          )
                        : Image.network(
                            _profileImageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.3)),
                              child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                            ),
                          ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 28),
                  ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_greeting()},', style: GoogleFonts.inter(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 2),
                Text(
                  name.isNotEmpty ? name : 'Sukarelawan'.tr(),
                  style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _isActive ? Colors.greenAccent : Colors.white54,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 4),
                Text(_isActive ? 'Aktif'.tr() : 'Tidak'.tr(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityCard(String uid) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _isActive ? AppColors.safeLight : AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
                  color: _isActive ? AppColors.safe : AppColors.textSecondary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Status Ketersediaan'.tr(), style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      _isActive ? 'Anda boleh dihubungi untuk misi'.tr() : 'Anda tidak tersedia buat masa ini'.tr(),
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              _isToggling
                  ? const SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.volunteerAccent))
                  : Switch(
                      value: _isActive,
                      activeThumbColor: AppColors.safe,
                      activeTrackColor: AppColors.safeLight,
                      inactiveThumbColor: AppColors.textHint,
                      inactiveTrackColor: AppColors.divider,
                      onChanged: uid.isNotEmpty ? (val) => _toggleAvailability(uid, val) : null,
                    ),
            ],
          ),
          if (_isActive) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: AppColors.safeLight, borderRadius: BorderRadius.circular(10)),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.safe),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Status anda boleh dilihat oleh pegawai SIGAP.'.tr(),
                      style: GoogleFonts.inter(fontSize: 12, color: AppColors.safe, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSkillsSection() {
    final skillsList = _skills.isNotEmpty ? _skills.split(',').map((s) => s.trim()).toList() : <String>[];
    if (skillsList.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Kepakaran Saya'.tr(), style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            GestureDetector(
              onTap: () => context.push(AppRoutes.volunteerProfile),
              child: Text('Kemaskini'.tr(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.volunteerAccent)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: skillsList.map((skill) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.volunteerAccent.withValues(alpha: 0.1),
              border: Border.all(color: AppColors.volunteerAccent.withValues(alpha: 0.3), width: 1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(skill.tr(), style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.volunteerAccent)),
          )).toList(),
        ),
      ],
    );
  }

  Widget _buildSigapMataSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text('SIGAP Mata'.tr(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ],
              ),
              Text('$_sigapMataPoints ${'points'.tr()}', style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.volunteerAccent)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _sigapMataPoints / 1240,
              minHeight: 8,
              backgroundColor: AppColors.divider,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.amber),
            ),
          ),
          const SizedBox(height: 8),
          Text('${1240 - _sigapMataPoints} ${'pointsToGoldCert'.tr()}', style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildNearbyMissionsPreview() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamActiveSOSReports(),
      builder: (context, sosSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.streamAllVolunteerTasks(),
          builder: (context, taskSnapshot) {
            List<dynamic> allMissions = [];
            
            if (sosSnapshot.hasData) {
              final authState = context.read<AuthBloc>().state;
              final uid = authState is AuthAuthenticated ? authState.uid : '';
              final sosReports = sosSnapshot.data!.docs
                  .map((doc) => SosReportModel.fromDocument(doc))
                  .where((r) => r.status == SosReportModel.statusActive && !r.declinedBy.contains(uid) && r.responderId == null)
                  .toList();
              allMissions.addAll(sosReports);
            }
            
            if (taskSnapshot.hasData) {
              final authState = context.read<AuthBloc>().state;
              final uid = authState is AuthAuthenticated ? authState.uid : '';
              final tasks = taskSnapshot.data!.docs
                  .map((doc) => VolunteerTaskModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                  .where((t) => 
                      t.status != 'Selesai Tugas'.tr() && 
                      !t.hasAccepted(uid) && 
                      !t.hasDeclined(uid) && 
                      !t.isFull &&
                      (t.squadId == _assignedSquadId || t.squadName == _assignedSquad)) // ADD squad filter
                  .toList();
              allMissions.addAll(tasks);
            }

            if (allMissions.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 36, color: AppColors.safe),
                      const SizedBox(height: 8),
                      Text('Kawasan anda selamat buat masa ini.'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              );
            }

            final preview = allMissions.take(3).toList();
            return Column(
              children: [
                ...preview.map((mission) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: mission is SosReportModel 
                      ? _missionPreviewCard(mission.type, mission.address, mission.urgency, 'sos')
                      : _missionPreviewCard((mission as VolunteerTaskModel).squadName, mission.zone, mission.priority, 'task'),
                )),
                if (allMissions.length > 3)
                  TextButton.icon(
                    onPressed: () => setState(() => _currentIndex = 1),
                    icon: const Icon(Icons.list_rounded, size: 16),
                    label: Text('seeMoreMissions'.tr(args: [(allMissions.length - 3).toString()]), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(foregroundColor: AppColors.volunteerAccent),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _missionPreviewCard(String title, String location, String priority, String type) {
    Color priorityColor;
    switch (priority) {
      case 'Kritikal': priorityColor = const Color(0xFFDC2626); break;
      case 'Tinggi': priorityColor = const Color(0xFFF97316); break;
      case 'Rendah': priorityColor = const Color(0xFF22C55E); break;
      default: priorityColor = const Color(0xFFFBBF24);
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: priorityColor.withValues(alpha: 0.3), width: 2),
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(type == 'sos' ? Icons.warning_rounded : Icons.group_rounded, color: priorityColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(location, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: priorityColor, borderRadius: BorderRadius.circular(6)),
            child: Text(priority.tr().toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        _actionCard(Icons.manage_accounts_rounded, 'Kemaskini Profil'.tr(), 'Nama, kemahiran & lokasi'.tr(), AppColors.volunteerAccent,
            () => context.push(AppRoutes.volunteerProfile)),
        const SizedBox(height: 10),
        _actionCard(Icons.assignment_rounded, 'Misi Tersedia'.tr(), 'Lihat misi yang memerlukan anda'.tr(), AppColors.warning,
            () => setState(() => _currentIndex = 1)),
        const SizedBox(height: 10),
        _actionCard(Icons.checklist_rounded, 'Senarai Semak Misi'.tr(), 'Tandai tugas yang diselesaikan'.tr(), const Color(0xFF10B981),
            () => context.push(AppRoutes.missionChecklist)),
        const SizedBox(height: 10),
        _actionCard(Icons.history_rounded, 'Sejarah Misi'.tr(), 'Rekod misi terdahulu'.tr(), AppColors.primary, () {}),
        const SizedBox(height: 10),
        _actionCard(Icons.auto_awesome_rounded, 'Briefing AWANIS'.tr(), 'Ringkasan pra-misi & sumber'.tr(), const Color(0xFFEC4899),
            () => _requestAwanisBriefing()),
        const SizedBox(height: 10),
        _actionCard(Icons.leaderboard_rounded, 'Leaderboard'.tr(), 'Peringkat sukarelawan terbaik'.tr(), const Color(0xFF8B5CF6),
            () => setState(() => _currentIndex = 3)),
      ],
    );
  }

  Widget _actionCard(IconData icon, String title, String subtitle, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: _cardDecoration(),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textHint),
          ],
        ),
      ),
    );
  }

  Widget _buildModuleGrid() {
    return GridView.count(
      crossAxisCount: 2,
      childAspectRatio: 1.1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: [
        _moduleCard(Icons.notifications_rounded, 'Pemberitahuan'.tr(), '2', const Color(0xFF06B6D4), () {}),
        _moduleCard(Icons.help_rounded, 'Bantuan'.tr(), 'FAQ'.tr(), const Color(0xFF10B981), () {}),
        _moduleCard(Icons.assessment_rounded, 'Laporan'.tr(), 'Progres'.tr(), const Color(0xFFEF4444), () {}),
        _moduleCard(Icons.school_rounded, 'Pembelajaran'.tr(), 'Video'.tr(), const Color(0xFFF97316), () {}),
        _moduleCard(Icons.location_on_rounded, 'Misi Tersedia'.tr(), 'Aktif'.tr(), const Color(0xFF8B5CF6), () => setState(() => _currentIndex = 1)),
        _moduleCard(Icons.card_giftcard_rounded, 'Pelepasan Mata'.tr(), 'Baru'.tr(), const Color(0xFFEC4899), () => setState(() => _currentIndex = 4)),
      ],
    );
  }

  Widget _moduleCard(IconData icon, String title, String badge, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2), width: 1),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text(badge, style: GoogleFonts.inter(fontSize: 11, color: color, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: Text('→', style: GoogleFonts.inter(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // TAB 1: MISI - ACCEPT MISSIONS (NO SQUAD FILTERING)
  // ============================================================

  Widget _buildMissionsTab(String uid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Misi Tersedia'.tr(), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Terima misi SOS atau tugasan skuad di sini'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: AppColors.volunteerAccent,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.volunteerAccent,
                  tabs: [
                    Tab(text: 'Misi SOS'.tr(), icon: const Icon(Icons.warning_rounded)),
                    Tab(text: 'Tugasan Skuad'.tr(), icon: const Icon(Icons.group_rounded)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildAvailableSOSMissions(uid),
                      _buildAvailableSquadTasks(uid),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvailableSOSMissions(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamActiveSOSReports(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.volunteerAccent));
        }

        final docs = snapshot.hasData ? snapshot.data!.docs : [];
        final reports = docs
            .map((doc) => SosReportModel.fromDocument(doc))
            .where((r) => r.status == SosReportModel.statusActive && !r.declinedBy.contains(uid) && r.responderId == null)
            .toList();

        reports.sort((a, b) {
          final urgencyComp = a.urgencyPriority.compareTo(b.urgencyPriority);
          if (urgencyComp != 0) return urgencyComp;
          if (_currentPosition != null) {
            final distA = LocationService.calculateDistanceKm(_currentPosition!.latitude, _currentPosition!.longitude, a.latitude, a.longitude);
            final distB = LocationService.calculateDistanceKm(_currentPosition!.latitude, _currentPosition!.longitude, b.latitude, b.longitude);
            return distA.compareTo(distB);
          }
          return 0;
        });

        if (reports.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline_rounded, size: 64, color: AppColors.safe),
                const SizedBox(height: 16),
                Text('Tiada Misi SOS Aktif'.tr(), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text('Kawasan anda selamat buat masa ini'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textHint)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: reports.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _buildAcceptSOSCard(reports[index]),
        );
      },
    );
  }

  Widget _buildAcceptSOSCard(SosReportModel report) {
    String distanceStr = '';
    if (_currentPosition != null) {
      final dist = LocationService.calculateDistanceKm(_currentPosition!.latitude, _currentPosition!.longitude, report.latitude, report.longitude);
      distanceStr = LocationService.formatDistance(dist);
    }

    final mySkillsList = _skills.split(',').map((s) => s.trim()).toList();
    final hasMatchingSkill = report.requiredSkills.any((s) => mySkillsList.contains(s));

    Color urgencyColor;
    switch (report.urgency) {
      case SosReportModel.urgencyKritikal: urgencyColor = const Color(0xFFDC2626); break;
      case SosReportModel.urgencyTinggi: urgencyColor = const Color(0xFFF97316); break;
      case SosReportModel.urgencySedang: urgencyColor = const Color(0xFFFBBF24); break;
      default: urgencyColor = const Color(0xFF22C55E);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: urgencyColor.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: urgencyColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(report.urgency.tr().toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const Spacer(),
                if (distanceStr.isNotEmpty) Text(distanceStr, style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.volunteerAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.warning_rounded, color: AppColors.volunteerAccent, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(report.type.tr(), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          const SizedBox(height: 4),
                          Text(report.address, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (report.description.isNotEmpty)
                  Text(report.description.tr(), maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 12),
                if (report.requiredSkills.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: report.requiredSkills.map((skill) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: hasMatchingSkill ? AppColors.safe.withValues(alpha: 0.1) : Colors.grey[100], borderRadius: BorderRadius.circular(4)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(hasMatchingSkill ? Icons.check_circle_rounded : Icons.info_outline_rounded, size: 12, color: hasMatchingSkill ? AppColors.safe : AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(skill.tr(), style: GoogleFonts.inter(fontSize: 11, color: hasMatchingSkill ? AppColors.safe : AppColors.textSecondary)),
                        ],
                      ),
                    )).toList(),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _declineSOSMission(report.id, report.type),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text('Tolak'.tr(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isActive ? () => _acceptSOSMission(report.id, report.type) : null,
                        style: ElevatedButton.styleFrom(backgroundColor: urgencyColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text('Terima Misi'.tr(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // FIXED: Show ALL squad tasks without filtering
  Widget _buildAvailableSquadTasks(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamAllVolunteerTasks(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: AppColors.volunteerAccent));
        }

        final docs = snapshot.hasData ? snapshot.data!.docs : [];
        print('=== Total Squad tasks: ${docs.length} ===');
        print('My assigned squad: $_assignedSquad');
        print('My assigned squad ID: $_assignedSquadId');
        
        final allTasks = docs.map((doc) {
          return VolunteerTaskModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
        }).toList();

        // ONLY show tasks for the volunteer's assigned squad
        final availableTasks = allTasks.where((task) {
          // Check if task belongs to volunteer's squad
          final isForMySquad = task.squadId == _assignedSquadId || task.squadName == _assignedSquad;
          final notCompleted = task.status != 'Selesai Tugas'.tr();
          final notAccepted = !task.hasAccepted(uid);
          final notDeclined = !task.hasDeclined(uid);
          final notFull = !task.isFull;
          
          print('Task ${task.squadName}: squadId=${task.squadId}, isForMySquad=$isForMySquad, status=${task.status}');
          
          return isForMySquad && notCompleted && notAccepted && notDeclined && notFull;
        }).toList();

        print('Available tasks for my squad: ${availableTasks.length}');

        // Show message if volunteer has no assigned squad
        if (_assignedSquad.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.group_off_rounded, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text('Belum Ditugaskan ke Skuad'.tr(), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text('Sila hubungi pegawai untuk ditugaskan ke skuad'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textHint)),
              ],
            ),
          );
        }

        if (availableTasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.group_off_rounded, size: 64, color: AppColors.textHint),
                const SizedBox(height: 16),
                Text('Tiada Tugasan Skuad'.tr(), style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                Text('noTasksForSquad'.tr(args: [_assignedSquad]), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textHint)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: availableTasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) => _buildAcceptSquadTaskCard(availableTasks[index], uid),
        );
      },
    );
  }

  Widget _buildAcceptSquadTaskCard(VolunteerTaskModel task, String uid) {
    Color priorityColor;
    switch (task.priority) {
      case 'Kritikal': priorityColor = const Color(0xFFDC2626); break;
      case 'Tinggi': priorityColor = const Color(0xFFF97316); break;
      case 'Rendah': priorityColor = const Color(0xFF22C55E); break;
      default: priorityColor = const Color(0xFFFBBF24);
    }

    final slotsLeft = task.requiredVolunteerCount - task.acceptedVolunteerUIDs.length;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: priorityColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.08), borderRadius: const BorderRadius.vertical(top: Radius.circular(16))),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: priorityColor, borderRadius: BorderRadius.circular(6)),
                  child: Text(task.priority.tr().toUpperCase(), style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(6)),
                  child: Text('needMoreSlots'.tr(args: [slotsLeft.toString()]), style: GoogleFonts.inter(fontSize: 10, color: AppColors.textSecondary)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: AppColors.volunteerAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.group_rounded, color: AppColors.volunteerAccent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(task.squadName, style: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(task.zone, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(task.taskDescription.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary, height: 1.4)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _declineSquadTask(task, uid),
                        style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text('Tolak'.tr(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isActive ? () => _acceptSquadTask(task, uid) : null,
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.volunteerAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                        child: Text('Terima Misi'.tr(), style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
                if (!_isActive)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, size: 12, color: AppColors.warning),
                          const SizedBox(width: 6),
                          Text('Aktifkan status ketersediaan untuk terima misi'.tr(), style: GoogleFonts.inter(fontSize: 11, color: AppColors.warning)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TAB 2: PETA + PROGRESS
  // ============================================================

  Widget _buildMapAndProgressTab(String uid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Peta & Kemajuan Misi'.tr(), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Lihat lokasi misi dan kemaskini kemajuan tugasan anda'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: AppColors.volunteerAccent,
                  unselectedLabelColor: AppColors.textSecondary,
                  indicatorColor: AppColors.volunteerAccent,
                  tabs: [
                    Tab(text: 'Peta'.tr(), icon: const Icon(Icons.map_rounded)),
                    Tab(text: 'Kemajuan Saya'.tr(), icon: const Icon(Icons.trending_up_rounded)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildMapView(),
                      _buildMyProgressTab(uid),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapView() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamActiveSOSReports(),
      builder: (context, sosSnapshot) {
        return StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.streamAllVolunteerTasks(),
          builder: (context, taskSnapshot) {
            final Set<Marker> markers = {};

            if (_currentPosition != null) {
              markers.add(
                Marker(
                  markerId: const MarkerId('my_location'),
                  position: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
                  icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                  infoWindow: InfoWindow(title:'Lokasi Anda'.tr()),
                ),
              );
            }

            if (sosSnapshot.hasData) {
              final sosReports = sosSnapshot.data!.docs
                  .map((doc) => SosReportModel.fromDocument(doc))
                  .where((r) => r.status == SosReportModel.statusActive)
                  .toList();

              for (final report in sosReports) {
                markers.add(
                  Marker(
                    markerId: MarkerId('sos_${report.id}'),
                    position: LatLng(report.latitude, report.longitude),
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                    infoWindow: InfoWindow(
                      title: 'SOS: ${report.type}',
                      snippet: 'Keutamaan: ${report.urgency}\n${report.address}',
                    ),
                  ),
                );
              }
            }

            if (taskSnapshot.hasData) {
              final tasks = taskSnapshot.data!.docs
                  .map((doc) => VolunteerTaskModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                  .where((t) => t.status != 'Selesai Tugas'.tr())
                  .toList();

              for (final task in tasks) {
                final taskCoords = _getTaskCoordinates(task.zone);
                markers.add(
                  Marker(
                    markerId: MarkerId('task_${task.id}'),
                    position: taskCoords,
                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
                    infoWindow: InfoWindow(
                      title: 'Skuad: ${task.squadName}',
                      snippet: 'Zon: ${task.zone}\nStatus: ${task.status}',
                    ),
                  ),
                );
              }
            }

            return GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPosition != null
                    ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    : const LatLng(3.1390, 101.6869),
                zoom: 11,
              ),
              markers: markers,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (_) {},
            );
          },
        );
      },
    );
  }

  LatLng _getTaskCoordinates(String zone) {
    final normalized = zone.toLowerCase();
    if (normalized.contains('ampang')) return const LatLng(3.1490, 101.7620);
    if (normalized.contains('hulu langat'.tr())) return const LatLng(3.0948, 101.8187);
    if (normalized.contains('gombak')) return const LatLng(3.2521, 101.6530);
    if (normalized.contains('sri petaling'.tr())) return const LatLng(3.0705, 101.6920);
    return const LatLng(3.1390, 101.6869);
  }

  // Replace the _buildMyProgressTab method with this:

  Widget _buildMyProgressTab(String uid) {
  return StreamBuilder<QuerySnapshot>(
    stream: FirebaseFirestore.instance
        .collection('sos_reports')
        .where('responderId', isEqualTo: uid)
        .snapshots(),
    builder: (context, sosSnapshot) {
      return StreamBuilder<QuerySnapshot>(
        stream: _firestoreService.streamAllVolunteerTasks(),
        builder: (context, taskSnapshot) {
          if (!sosSnapshot.hasData || !taskSnapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: AppColors.volunteerAccent));
          }

          // Parse and filter SOS reports
          final allReports = sosSnapshot.hasData
              ? sosSnapshot.data!.docs.map((doc) => SosReportModel.fromDocument(doc)).toList()
              : <SosReportModel>[];

          final filteredReports = allReports.where((r) {
            // Always hide cancelled SOS reports — citizen withdrew the request.
            if (r.status == SosReportModel.statusCancelled) return false;

            final isCompleted = r.status == 'resolved' ||
                r.status == 'completed' ||
                r.status == SosReportModel.statusResolved;
            if (_selectedMissionFilter == 'active') {
              return !isCompleted;
            } else if (_selectedMissionFilter == 'completed') {
              return isCompleted;
            }
            return true; // 'all'
          }).toList();

          // Parse and filter Squad Tasks
          final allTasks = taskSnapshot.hasData
              ? taskSnapshot.data!.docs
                  .map((doc) => VolunteerTaskModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
                  .toList()
              : <VolunteerTaskModel>[];

          final filteredTasks = allTasks.where((task) {
            if (!task.acceptedVolunteerUIDs.contains(uid)) return false;
            final isCompleted = task.status == 'Selesai Tugas'.tr();
            if (_selectedMissionFilter == 'active') {
              return !isCompleted;
            } else if (_selectedMissionFilter == 'completed') {
              return isCompleted;
            }
            return true; // 'all'
          }).toList();

          final isEmpty = filteredReports.isEmpty && filteredTasks.isEmpty && _selectedMissionFilter == 'active';

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            children: [
                // ── Classification Menu Bar
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      _buildFilterTab('all', 'Semua'),
                      _buildFilterTab('active', 'Aktif'.tr()),
                      _buildFilterTab('completed', 'Selesai'.tr()),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                if (isEmpty)
                  _buildEmptyMissionsState()
                else ...[
                  if (filteredReports.isNotEmpty) ...[
                    Text(
                      _selectedMissionFilter == 'completed'
                          ? 'Misi SOS Selesai'.tr()
                          : 'Misi SOS Dalam Progres'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...filteredReports.map((report) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildDetailedSOSProgressCard(report),
                    )),
                    const SizedBox(height: 8),
                  ],
                  if (filteredTasks.isNotEmpty) ...[
                    Text(
                      _selectedMissionFilter == 'completed'
                          ? 'Tugasan Skuad Selesai'.tr()
                          : 'Tugasan Skuad Dalam Progres'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...filteredTasks.map((task) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildDetailedSquadProgressCard(task, uid),
                    )),
                  ],
                  if (_selectedMissionFilter != 'active') ...[
                    const SizedBox(height: 16),
                    Text(
                      'Sejarah Misi Lepas'.tr(),
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFakePastMissionCard(
                      'Misi Bantuan Banjir (Alpha Rescue)'.tr(),
                      'Kampung Pasir Putih'.tr(),
                      '12 Nov 2023',
                      '+150 Mata'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildFakePastMissionCard(
                      'Pembersihan Pasca-Bencana (Bravo Medic)'.tr(),
                      'Sekolah Kebangsaan Skudai'.tr(),
                      '05 Okt 2023',
                      '+100 Mata'.tr(),
                    ),
                    const SizedBox(height: 12),
                    _buildFakePastMissionCard(
                      'Logistik Makanan (Charlie Logistics)'.tr(),
                      'Pusat Komuniti JB'.tr(),
                      '18 Sep 2023',
                      '+120 Mata'.tr(),
                    ),
                  ]
                ],
              ],
            );
        },
      );
    },
  );
}

Widget _buildFakePastMissionCard(String title, String location, String date, String points) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.divider),
      boxShadow: [
        BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 8, offset: const Offset(0, 4)),
      ],
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.safe.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.check_circle_rounded, color: AppColors.safe, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on_rounded, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(location, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.event_rounded, size: 12, color: AppColors.textSecondary),
                  const SizedBox(width: 4),
                  Text(date, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.volunteerAccent.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(points, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.volunteerAccent)),
        ),
      ],
    ),
  );
}

  Widget _buildFilterTab(String value, String label) {
    final isSelected = _selectedMissionFilter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedMissionFilter = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ]
                : [],
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected ? AppColors.volunteerAccent : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyMissionsState() {
    String title = 'Tiada Misi'.tr();
    String subtitle = 'Anda belum menerima sebarang misi atau tugasan lagi.\nTeroka Papan Tugas untuk misi terkini.'.tr();
    IconData icon = Icons.assignment_rounded;

    if (_selectedMissionFilter == 'active') {
      title = 'Tiada Misi Aktif'.tr();
      subtitle = 'Anda tidak mempunyai sebarang misi aktif\nyang sedang dijalankan buat masa ini.'.tr();
      icon = Icons.directions_run_rounded;
    } else if (_selectedMissionFilter == 'completed') {
      title = 'Tiada Misi Selesai'.tr();
      subtitle = 'Anda belum melengkapkan sebarang misi lagi.\nTeruskan usaha murni anda!'.tr();
      icon = Icons.check_circle_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.textHint.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 48, color: AppColors.textHint),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: AppColors.textHint,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  // ADD THIS NEW METHOD - Detailed SOS Progress Card (like reference design) - WITHOUT BUTTONS
  Widget _buildDetailedSOSProgressCard(SosReportModel report) {
    // Time ago calculation
    String timeAgo = 'Baru sahaja'.tr();
    if (report.createdAt != null) {
      final diff = DateTime.now().difference(report.createdAt!);
      if (diff.inMinutes < 60) {
        timeAgo = '${diff.inMinutes} min lalu';
      } else if (diff.inHours < 24) {
        timeAgo = '${diff.inHours} jam lalu';
      } else {
        timeAgo = '${diff.inDays} hari lalu';
      }
    }

    // Distance calculation
    String distanceStr = '';
    if (_currentPosition != null) {
      final dist = LocationService.calculateDistanceKm(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        report.latitude,
        report.longitude,
      );
      distanceStr = LocationService.formatDistance(dist);
    }

    // Skills match
    final mySkillsList = _skills.split(',').map((s) => s.trim().toLowerCase()).toList();
    final hasMatchingSkill = report.requiredSkills.any((s) => mySkillsList.contains(s.toLowerCase()));

    // Urgency colors
    Color urgencyColor;
    switch (report.urgency) {
      case SosReportModel.urgencyKritikal:
        urgencyColor = const Color(0xFFDC2626);
        break;
      case SosReportModel.urgencyTinggi:
        urgencyColor = const Color(0xFFF97316);
        break;
      case SosReportModel.urgencySedang:
        urgencyColor = const Color(0xFFFBBF24);
        break;
      default:
        urgencyColor = const Color(0xFF22C55E);
    }

    final isCompleted = report.status == 'resolved' ||
        report.status == 'completed' ||
        report.status == SosReportModel.statusResolved;

    return GestureDetector(
      onTap: () => context.push('/volunteer/sos-response', extra: report.id),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with urgency and time
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: urgencyColor.withOpacity(0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: urgencyColor,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      report.urgency,
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(Icons.access_time_rounded, size: 12, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Main content
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title and address
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.volunteerAccent.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.warning_rounded,
                          color: AppColors.volunteerAccent,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report.type,
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              report.address,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  // Description (if available)
                  if (report.description.isNotEmpty) ...[
                    Text(
                      report.description.tr(),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.textPrimary,
                        height: 1.4,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Info chips (distance, skills, etc.)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (distanceStr.isNotEmpty)
                        _infoChip(
                          Icons.location_on_rounded,
                          distanceStr,
                          AppColors.textPrimary,
                          Colors.grey[100]!,
                        ),
                      if (report.requiredSkills.isNotEmpty)
                        _infoChip(
                          hasMatchingSkill ? Icons.check_circle_rounded : Icons.psychology_rounded,
                          report.requiredSkills.first.tr() +
                              (report.requiredSkills.length > 1
                                  ? ' +${report.requiredSkills.length - 1}'
                                  : ''),
                          hasMatchingSkill ? AppColors.safe : AppColors.textSecondary,
                          hasMatchingSkill ? AppColors.safe.withOpacity(0.1) : Colors.grey[100]!,
                        ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  
                  if (!isCompleted) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        // "Tiba di Lokasi" button (only if not checked)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final checklist = Map<String, dynamic>.from(report.volunteerChecklist ?? {});
                              checklist[AppStrings.volunteerPeralatanKecemasanLengkapFirst] = true;
                              checklist[AppStrings.volunteerDalamPerjalananKeLokasi] = true;
                              checklist[AppStrings.volunteerTibaDiLokasiInsiden] = true;
                              
                              try {
                                await _firestoreService.updateSOSChecklist(report.id, checklist);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Status dikemaskini: Tiba di lokasi'.tr()),
                                      backgroundColor: AppColors.safe,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Gagal kemaskini status: $e'.tr()),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                }
                              }
                            },
                            icon: const Icon(Icons.location_on_rounded, size: 16),
                            label: Text(
                              'Tiba'.tr(),
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              foregroundColor: AppColors.volunteerAccent,
                              side: const BorderSide(color: AppColors.volunteerAccent),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // "Senarai Semak" button
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              context.push(AppRoutes.missionChecklist, extra: report.id);
                            },
                            icon: const Icon(Icons.checklist_rounded, size: 16),
                            label: Text(
                              'Semak'.tr(),
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              foregroundColor: Colors.purple,
                              side: const BorderSide(color: Colors.purple),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        // "Selesai" button
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              context.push(AppRoutes.missionCompletion, extra: report.id);
                            },
                            icon: const Icon(Icons.check_circle_rounded, size: 16, color: Colors.white),
                            label: Text(
                              'Selesai'.tr(),
                              style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.safe,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              elevation: 0,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ADD THIS HELPER METHOD FOR INFO CHIPS
  Widget _infoChip(IconData icon, String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  // UPDATE THE _buildDetailedSquadProgressCard to also use detailed design

  Widget _buildDetailedSquadProgressCard(VolunteerTaskModel task, String uid) {
    final statusSteps = [
      'Menuju ke Lokasi'.tr(),
      'Tiba di Lokasi'.tr(),
      'Sedang Bertugas'.tr(),
      'Selesai Tugas'.tr(),
    ];
    
    // Find current step index based on task status
    int currentStepIndex = statusSteps.indexOf(task.status);
    if (currentStepIndex == -1) {
      // If status not found, default to 0
      currentStepIndex = 0;
    }
    
    final isCompleted = task.status == 'Selesai Tugas'.tr();
    
    print('=== BUILDING SQUAD PROGRESS CARD ===');
    print('Task: ${task.squadName}');
    print('Current status: ${task.status}');
    print('Current step index: $currentStepIndex');
    print('Is completed: $isCompleted');
    print('Progress value: ${task.progress}');

    Color priorityColor;
    switch (task.priority) {
      case 'Kritikal':
        priorityColor = const Color(0xFFDC2626);
        break;
      case 'Tinggi':
        priorityColor = const Color(0xFFF97316);
        break;
      case 'Rendah':
        priorityColor = const Color(0xFF22C55E);
        break;
      default:
        priorityColor = const Color(0xFFFBBF24);
    }

    final slotsLeft = task.requiredVolunteerCount - task.acceptedVolunteerUIDs.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with priority and slots
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: priorityColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: priorityColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    task.priority,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Perlukan $slotsLeft lagi',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // Main content
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Squad info row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.volunteerAccent.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.group_rounded,
                        color: AppColors.volunteerAccent,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            task.squadName,
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            'Zon: ${task.zone}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: priorityColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        task.status,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: priorityColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Task description
                Text(
                  task.taskDescription,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                
                // Progress bar
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Kemajuan Tugasan'.tr(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          '${(task.progress * 100).round()}%',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: priorityColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: task.progress.clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: priorityColor.withOpacity(0.1),
                        color: priorityColor,
                      ),
                    ),
                  ],
                ),
                
                // PROGRESS UPDATE BUTTONS - ALWAYS SHOW if not completed
                if (!isCompleted) ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  Text(
                    'Kemaskini Status Tugasan:'.tr(),
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      // Show all buttons, but disable ones that are before current step
                      _buildStatusButton(
                        label:'Menuju ke Lokasi'.tr(),
                        isActive: currentStepIndex == 0,
                        isCompleted: currentStepIndex > 0,
                        onPressed: () => _updateSquadTaskProgress(task, 'Menuju ke Lokasi'.tr(), uid),
                        color: priorityColor,
                      ),
                      _buildStatusButton(
                        label:'Tiba di Lokasi'.tr(),
                        isActive: currentStepIndex == 1,
                        isCompleted: currentStepIndex > 1,
                        onPressed: () => _updateSquadTaskProgress(task, 'Tiba di Lokasi'.tr(), uid),
                        color: priorityColor,
                      ),
                      _buildStatusButton(
                        label:'Sedang Bertugas'.tr(),
                        isActive: currentStepIndex == 2,
                        isCompleted: currentStepIndex > 2,
                        onPressed: () => _updateSquadTaskProgress(task, 'Sedang Bertugas'.tr(), uid),
                        color: priorityColor,
                      ),
                      _buildStatusButton(
                        label:'Selesai Tugas'.tr(),
                        isActive: currentStepIndex == 3,
                        isCompleted: currentStepIndex > 3,
                        onPressed: () => _updateSquadTaskProgress(task, 'Selesai Tugas'.tr(), uid),
                        color: priorityColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline_rounded, size: 14, color: AppColors.warning),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Klik butang di atas untuk mengemaskini status tugasan anda'.tr(),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Add this helper method for status buttons
  Widget _buildStatusButton({
    required String label,
    required bool isActive,
    required bool isCompleted,
    required VoidCallback onPressed,
    required Color color,
  }) {
    // Determine button style based on state
    if (isCompleted) {
      // Already completed - show as green checkmark
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.safe.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.safe),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 12, color: AppColors.safe),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppColors.safe,
              ),
            ),
          ],
        ),
      );
    } else if (isActive) {
      // Current status - show as active (can't click again)
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      );
    } else {
      // Next available button - clickable
      return ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          elevation: 0,
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
  }

  // ============================================================
  // ACTION METHODS
  // ============================================================

  Future<void> _acceptSOSMission(String sosId, String type) async {
    final authState = context.read<AuthBloc>().state;
    final uid = authState is AuthAuthenticated ? authState.uid : '';
    final name = authState is AuthAuthenticated ? authState.displayName : 'Sukarelawan'.tr();

    print('=== ACCEPT SOS MISSION ===');
    print('sosId: $sosId, uid: $uid, name: $name, _isActive: $_isActive');

    if (!_isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sila aktifkan status ketersediaan anda terlebih dahulu'.tr()), backgroundColor: AppColors.warning),
      );
      return;
    }

    try {
      await _firestoreService.respondToSOS(sosId, uid, name);
      print('SUCCESS!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('successAcceptSOS'.tr(args: [type])), backgroundColor: AppColors.safe),
        );
        setState(() {});
      }
    } catch (e) {
      print('ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('failedAcceptSOS'.tr(args: [e.toString()])), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _declineSOSMission(String sosId, String type) async {
    final authState = context.read<AuthBloc>().state;
    final uid = authState is AuthAuthenticated ? authState.uid : '';

    try {
      await _firestoreService.declineSOSReport(sosId, uid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('rejectedSOS'.tr(args: [type])), backgroundColor: AppColors.textSecondary, duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('failedRejectSOS'.tr(args: [e.toString()])), backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _acceptSquadTask(VolunteerTaskModel task, String uid) async {
    print('=== ACCEPT SQUAD TASK ===');
    print('Task: ${task.squadName}, uid: $uid, _isActive: $_isActive');

    if (!_isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Sila aktifkan status ketersediaan anda terlebih dahulu'.tr()), backgroundColor: AppColors.warning),
      );
      return;
    }

    try {
      final updatedAccepted = List<String>.from(task.acceptedVolunteerUIDs)..add(uid);
      await _firestoreService.updateVolunteerTask(task.id, {
        'acceptedVolunteerUIDs': updatedAccepted,
      });
      print('SUCCESS!');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('successAcceptTask'.tr(args: [task.squadName])), backgroundColor: AppColors.safe),
        );
        setState(() {});
      }
    } catch (e) {
      print('ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('failedAcceptTask'.tr(args: [e.toString()])), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _declineSquadTask(VolunteerTaskModel task, String uid) async {
    try {
      final updatedDeclined = List<String>.from(task.declinedVolunteerUIDs)..add(uid);
      await _firestoreService.updateVolunteerTask(task.id, {'declinedVolunteerUIDs': updatedDeclined});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('rejectedTask'.tr(args: [task.squadName])), backgroundColor: AppColors.textSecondary, duration: const Duration(seconds: 2)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('failedRejectTask'.tr(args: [e.toString()])), backgroundColor: AppColors.danger));
      }
    }
  }

  Future<void> _updateSquadTaskProgress(VolunteerTaskModel task, String newStatus, String uid) async {
    final progressMap = {
      'Menuju ke Lokasi'.tr(): 0.0,
      'Tiba di Lokasi'.tr(): 0.33,
      'Sedang Bertugas'.tr(): 0.66,
      'Selesai Tugas'.tr(): 1.0,
    };

    try {
      final updates = <String, dynamic>{
        'status': newStatus,
        'progress': progressMap[newStatus] ?? task.progress,
        'lastKnownLocation': task.zone,
      };
      if (_currentPosition != null) {
        updates['currentLat'] = _currentPosition!.latitude;
        updates['currentLng'] = _currentPosition!.longitude;
      }
      await _firestoreService.updateVolunteerTask(task.id, updates);
      if (mounted && newStatus == 'Selesai Tugas'.tr()) {
        await _firestoreService.addVolunteerPoints(uid, 50);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Tugasan selesai! +50 SIGAP Mata'.tr()), backgroundColor: AppColors.safe));
          _loadProfile();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('failedUpdate'.tr(args: [e.toString()])), backgroundColor: AppColors.danger));
      }
    }
  }

  // ============================================================
  // PLACEHOLDER TABS
  // ============================================================

  Widget _buildLeaderboardPlaceholder() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Leaderboard'.tr(), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text('Peringkat sukarelawan berdasarkan SIGAP Mata'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              final docs = [
                {'name': 'Ahmad Albab'.tr(), 'assignedSquad': 'Alpha Rescue'.tr(), 'sigapMataPoints': 2450},
                {'name': 'Siti Nurhaliza'.tr(), 'assignedSquad': 'Bravo Medic'.tr(), 'sigapMataPoints': 2100},
                {'name': 'youVolunteer'.tr(), 'assignedSquad': 'Delta Support'.tr(), 'sigapMataPoints': _sigapMataPoints},
                {'name': 'Muthusamy'.tr(), 'assignedSquad': 'Echo Relief'.tr(), 'sigapMataPoints': 980},
                {'name': 'Wong Wei Kit'.tr(), 'assignedSquad': 'Alpha Rescue'.tr(), 'sigapMataPoints': 850},
                {'name': 'Nurul Ain'.tr(), 'assignedSquad': 'Echo Relief'.tr(), 'sigapMataPoints': 720},
                {'name': 'Faizal Tahir'.tr(), 'assignedSquad': 'Bravo Medic'.tr(), 'sigapMataPoints': 640},
              ];
              // Sort the list descending by points
              docs.sort((a, b) => (b['sigapMataPoints'] as int).compareTo(a['sigapMataPoints'] as int));

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final data = docs[index];
                  final name = data['name'] as String;
                  final points = data['sigapMataPoints'] as int;
                  final squad = data['assignedSquad'] as String;
                  final isUser = name == 'youVolunteer'.tr();
                  
                  Color rankColor;
                  if (index == 0) rankColor = Colors.amber;
                  else if (index == 1) rankColor = Colors.grey.shade400;
                  else if (index == 2) rankColor = Colors.orange.shade300;
                  else rankColor = AppColors.textHint;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isUser ? AppColors.volunteerAccent.withOpacity(0.05) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                      border: isUser ? Border.all(color: AppColors.volunteerAccent, width: 2) : (index < 3 ? Border.all(color: rankColor, width: 2) : Border.all(color: AppColors.divider)),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '#${index + 1}',
                          style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold, color: rankColor),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600, color: index == 2 ? AppColors.volunteerAccent : AppColors.textPrimary)),
                              Text(squad, style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.volunteerAccent.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.stars_rounded, color: Colors.amber, size: 16),
                              const SizedBox(width: 4),
                              Text('$points', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.volunteerAccent)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCertificatesTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        Text('Pelepasan SIGAP Mata'.tr(), style: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Text('Tukarkan poin SIGAP Mata anda dengan sijil tersertifikasi'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 24),
                  const SizedBox(width: 12),
                  Text('Poin SIGAP Mata Anda'.tr(), style: GoogleFonts.inter(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w500)),
                ],
              ),
              const SizedBox(height: 12),
              Text('$_sigapMataPoints', style: GoogleFonts.poppins(fontSize: 44, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Sijil Tersedia untuk Pelepasan'.tr(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        _certificateCard('Sijil NADMA\nSukarelawan Darurat'.tr(), 300, AppColors.primary, Icons.verified_user_rounded),
        const SizedBox(height: 12),
        _certificateCard('Sijil Bomba\nPembantu Penyelamat'.tr(), 750, const Color(0xFFEF4444), Icons.shield_rounded),
        const SizedBox(height: 12),
        _certificateCard('Sijil Lanjutan\nKoordinator Misi'.tr(), 1200, const Color(0xFF8B5CF6), Icons.military_tech_rounded),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: AppColors.safe.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.safe.withValues(alpha: 0.2))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lightbulb_rounded, size: 20, color: AppColors.safe),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Cara Mengumpul Poin'.tr(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                ],
              ),
              const SizedBox(height: 12),
              _pointsExplanation('Selesaikan misi darurat'.tr(), 'Dapatkan poin per misi yang selesai'.tr()),
              const SizedBox(height: 8),
              _pointsExplanation('Bantuan kepada korban'.tr(), 'Bonus poin untuk bantuan kualiti tinggi'.tr()),
              const SizedBox(height: 8),
              _pointsExplanation('Peringkat Leaderboard'.tr(), 'Bonus mingguan untuk volunteer terbaik'.tr()),
            ],
          ),
        ),
        const SizedBox(height: 32),
        Text('Sijil Anda'.tr(), style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        _buildRedeemedCertificatesList(),
      ],
    );
  }

  Widget _buildRedeemedCertificatesList() {
    final state = context.read<AuthBloc>().state;
    if (state is! AuthAuthenticated) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamVolunteerCertificates(state.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('Anda belum menebus sebarang sijil.'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
            ),
          );
        }

        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final title = data['title'] as String? ?? 'Sijil';
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: AppColors.safe.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.verified_rounded, color: AppColors.safe, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        const SizedBox(height: 4),
                        Text('Telah ditebus'.tr(), style: GoogleFonts.inter(fontSize: 11, color: AppColors.safe)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, color: AppColors.primary),
                    onPressed: () async {
                      try {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Menjana PDF sijil...'.tr()), duration: const Duration(seconds: 2)),
                        );
                        final pdfBytes = await CertificateService.generateCertificatePDF(
                          volunteerName: _fullName.isNotEmpty ? _fullName : (state.displayName.isNotEmpty ? state.displayName : 'Sukarelawan SIGAP'),
                          certificateTitle: title,
                          date: (data['redeemedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
                        );
                        await Printing.layoutPdf(
                          onLayout: (format) async => pdfBytes,
                          name: 'Sijil_$title.pdf',
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal menjana sijil: $e')));
                      }
                    },
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _certificateCard(String title, int cost, Color color, IconData icon) {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('redeemConfirmTitle'.tr(args: [title]), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
            content: Text('redeemConfirmContent'.tr(args: ['$cost SIGAP Mata']), style: GoogleFonts.inter(fontSize: 14, color: AppColors.textSecondary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Batal'.tr())),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  try {
                    final state = context.read<AuthBloc>().state;
                    if (state is AuthAuthenticated) {
                      await _firestoreService.redeemCertificate(state.uid, title, cost);
                      if (mounted) {
                        final authName = state is AuthAuthenticated ? state.displayName : 'Sukarelawan SIGAP';
                        final vName = _fullName.isNotEmpty ? _fullName : authName;
                        Navigator.push(context, MaterialPageRoute(builder: (_) => CertificateRedemptionSuccessScreen(
                          certTitle: title,
                          volunteerName: vName,
                        )));
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString()), backgroundColor: AppColors.danger));
                    }
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: color),
                child: Text('Ya, Tebus'.tr()),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3), width: 1.5)),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 4),
                  Text('$cost SIGAP Mata', style: GoogleFonts.inter(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_rounded, color: AppColors.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _pointsExplanation(String title, String description) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(margin: const EdgeInsets.only(top: 2), width: 4, height: 4, decoration: const BoxDecoration(color: AppColors.safe, shape: BoxShape.circle)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(description, style: GoogleFonts.inter(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: AppColors.surface,
      elevation: 20,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      child: SizedBox(
        height: 65,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _navItem(Icons.home_rounded, 'navHome'.tr(), 0),
            _navItem(Icons.assignment_rounded, 'navMissions'.tr(), 1),
            _navItem(Icons.map_rounded, 'navMap'.tr(), 2),
            _navItem(Icons.leaderboard_rounded, 'navLeaderboard'.tr(), 3),
            _navItem(Icons.card_giftcard_rounded, 'navRewards'.tr(), 4),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.volunteerAccent : AppColors.textSecondary;
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
            Text(label, style: GoogleFonts.inter(fontSize: 10, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500, color: color), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  void _showComingSoonDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(message, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr())),
        ],
      ),
    );
  }

  void _requestAwanisBriefing() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.volunteerAccent),
            const SizedBox(height: 16),
            Text('AWANIS sedang menganalisis laporan...'.tr(), style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );

    try {
      final summary = await AwanisService().getVolunteerBriefing();
      if (mounted) {
        Navigator.pop(context); // close loading
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.auto_awesome_rounded, color: Color(0xFFEC4899)),
                const SizedBox(width: 8),
                Expanded(child: Text('Pre-Mission Briefing'.tr(), style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18))),
              ],
            ),
            content: SingleChildScrollView(
              child: Text(summary, style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary)),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('OK'.tr())),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showComingSoonDialog('Ralat'.tr(), 'Gagal mendapatkan maklumat AWANIS.'.tr());
      }
    }
  }

  Widget _buildSectionHeader(String title) {
    return Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary));
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 10, offset: const Offset(0, 4))],
    );
  }
}