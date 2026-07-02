import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_routes.dart';
import '../../core/constants/app_strings.dart';
import '../../models/sos_report_model.dart';
import '../../models/claim_model.dart';
import '../../services/authority_routing_service.dart';
import '../../services/firestore_service.dart';
import '../../services/location_service.dart';
import 'privacy_policy_screen.dart';
import '../../services/notification_service.dart';
import '../../widgets/common/sigap_app_bar.dart';
import '../../widgets/common/sigap_button.dart';
import 'package:geolocator/geolocator.dart';
import 'donation_campaigns_screen.dart';
import 'offline_guide_screen.dart';
import 'faq_screen.dart';
import 'awanis_chat_screen.dart';
import 'emergency_bag_screen.dart';
import 'dart:typed_data';
import 'package:url_launcher/url_launcher.dart';

class SirenOverlay extends StatefulWidget {
  final VoidCallback onClose;
  const SirenOverlay({super.key, required this.onClose});

  @override
  State<SirenOverlay> createState() => _SirenOverlayState();
}

class _SirenOverlayState extends State<SirenOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Timer? _timer;
  bool _isRed = true;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);

    _audioPlayer.setReleaseMode(ReleaseMode.loop);
    _audioPlayer.play(AssetSource('sounds/siren.mp3'));

    // Flash background color every 250ms
    _timer = Timer.periodic(const Duration(milliseconds: 250), (t) {
      if (mounted) {
        setState(() {
          _isRed = !_isRed;
        });
      }
    });
  }

  @override
  void dispose() {
    _animController.dispose();
    _timer?.cancel();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isRed ? const Color(0xFFDC2626) : Colors.white;
    final fgColor = _isRed ? Colors.white : const Color(0xFFDC2626);

    return Container(
      color: bgColor,
      width: double.infinity,
      height: double.infinity,
      child: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.9, end: 1.2).animate(
                CurvedAnimation(
                    parent: _animController, curve: Curves.easeInOut),
              ),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: fgColor.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.campaign_rounded,
                  color: fgColor,
                  size: 100,
                ),
              ),
            ),
            const SizedBox(height: 40),
            Text(
              'SIREN KECEMASAN AKTIF'.tr(),
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: fgColor,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Peranti anda sedang berkelip strobe dan memancarkan isyarat audio kelantangan maksimum untuk menarik perhatian penyelamat berhampiran.'
                    .tr(),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: fgColor.withValues(alpha: 0.9),
                ),
              ),
            ),
            const SizedBox(height: 48),
            ElevatedButton.icon(
              onPressed: widget.onClose,
              icon: const Icon(Icons.volume_off_rounded, size: 24),
              label: Text(
                'MATIKAN SIREN'.tr(),
                style: GoogleFonts.inter(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: fgColor,
                foregroundColor: bgColor,
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
                elevation: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CitizenDashboard extends StatefulWidget {
  const CitizenDashboard({super.key});

  @override
  State<CitizenDashboard> createState() => _CitizenDashboardState();
}

class _CitizenDashboardState extends State<CitizenDashboard> {
  final _firestoreService = FirestoreService();
  final _locationService = LocationService();
  int _currentIndex = 0;
  bool _isSubmittingSOS = false;
  bool _isSirenActive = false;
  bool _showAllClaims = false;
  String _selectedClaimFilter = 'Semua'.tr();

  // Track previous claim statuses to detect changes for notifications
  final Map<String, String> _lastKnownClaimStatuses = {};

  @override
  void initState() {
    super.initState();
    // Start claim status listener after first frame so BuildContext is ready
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _initClaimStatusListener());
  }

  void _initClaimStatusListener() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return;

    _firestoreService.streamClaimsForCitizen(authState.uid).listen((snapshot) {
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final id = doc.id;
        final status = data['status'] as String? ?? '';
        final prev = _lastKnownClaimStatuses[id];

        if (prev != null && prev != status) {
          // Status changed — fire local notification
          String statusLabel;
          switch (status) {
            case 'approved':
              statusLabel = 'Diluluskan ✅'.tr();
              break;
            case 'rejected':
              statusLabel = 'Ditolak ❌'.tr();
              break;
            case 'under_review':
              statusLabel = 'Sedang Disemak 🔍'.tr();
              break;
            case 'disbursed':
              statusLabel = 'Dana Disalurkan 💰'.tr();
              break;
            case 'cancelled':
              statusLabel = 'Dibatalkan'.tr();
              break;
            default:
              statusLabel = status;
          }
          NotificationService.instance.showLocalNotification(
            title: 'Kemaskini Tuntutan SIGAP'.tr(),
            body: 'Status tuntutan anda telah berubah kepada: $statusLabel',
            id: id.hashCode,
          );
        }
        _lastKnownClaimStatuses[id] = status;
      }
    });
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return AppStrings.goodMorning;
    if (hour < 18) return AppStrings.goodAfternoon;
    return AppStrings.goodEvening;
  }

  @override
  Widget build(BuildContext context) {
    context.locale;
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        final name = state is AuthAuthenticated ? state.displayName : '';
        final uid = state is AuthAuthenticated ? state.uid : '';
        final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        return Stack(
          children: [
            Scaffold(
              backgroundColor: AppColors.background,
              appBar: SigapAppBar(
                title: AppStrings.appName,
                showLogout: false,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.notifications_active_rounded,
                        color: AppColors.warning),
                    onPressed: () =>
                        context.push(AppRoutes.citizenNotifications),
                  ),
                  IconButton(
                    icon: const Icon(Icons.person_outline_rounded),
                    onPressed: () => context.push(AppRoutes.citizenProfile),
                  ),
                ],
              ),
              body: _buildBody(uid, name),
              floatingActionButton: isKeyboardOpen ? null : _buildSOSFab(uid),
              floatingActionButtonLocation: isKeyboardOpen
                  ? null
                  : FloatingActionButtonLocation.centerDocked,
              bottomNavigationBar: isKeyboardOpen ? null : _buildBottomAppBar(),
            ),
            if (_isSirenActive)
              Positioned.fill(
                child: SirenOverlay(
                  onClose: () {
                    setState(() {
                      _isSirenActive = false;
                    });
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBody(String uid, String name) {
    switch (_currentIndex) {
      case 0:
        return _buildHomeTab(uid, name);
      case 1:
        return _buildMapTab();
      case 2:
        return _buildAwanisScreen();
      case 3:
        return _buildClaimsTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildHomeTab(String uid, String name) {
    return RefreshIndicator(
      onRefresh: () async {},
      color: AppColors.primary,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          _buildEmergencyHeader(uid, name),
          _buildActiveSOSTracker(uid),
          const SizedBox(height: 24),
          _buildAlertBanner(),
          const SizedBox(height: 32),
          _buildFamilySafetyTracker(uid),
          const SizedBox(height: 32),
          _buildNearbyReliefCentre(),
          const SizedBox(height: 32),
          _buildEmergencyAlerts(),
          const SizedBox(height: 32),
          _buildOfflineToolkit(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  Widget _buildMapTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        _buildLiveCrisisMap(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildClaimsTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      children: [
        _buildReliefClaimTracker(),
        const SizedBox(height: 32),
        _buildDonationBanner(),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildDonationBanner() {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BlocProvider.value(
              value: context.read<AuthBloc>(),
              child: const DonationCampaignsScreen(),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF3B6DD4), Color(0xFF5B8DEF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.volunteer_activism_rounded,
                  color: Colors.white, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tabung Bantuan'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    'Lihat kempen derma aktif & sumbang sekarang'.tr(),
                    style:
                        GoogleFonts.inter(fontSize: 12, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: Colors.white70, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildSOSFab(String uid) {
    return Container(
      margin: const EdgeInsets.only(top: 30),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withValues(alpha: 0.4),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: FloatingActionButton(
        onPressed: () async {
          if (uid.isEmpty) return;
          final hasActive = await _firestoreService.hasActiveSOS(uid);
          if (hasActive) {
            if (mounted) {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Text('SOS Sedang Aktif'.tr(), style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 16)),
                    ],
                  ),
                  content: Text(
                    'Anda sudah mempunyai laporan SOS yang sedang aktif. Sila batalkan laporan sedia ada sebelum membuat laporan baharu.'.tr(),
                    style: GoogleFonts.inter(fontSize: 13, color: AppColors.textSecondary),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('Tutup'.tr(), style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              );
            }
            return;
          }
          _showSOSTypeDialog(context);
        },
        backgroundColor: AppColors.danger,
        elevation: 0,
        shape: const CircleBorder(),
        child: const Icon(Icons.sos_rounded, color: Colors.white, size: 36),
      ),
    );
  }

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
            _navItem(Icons.home_rounded, 'navHome'.tr(), 0),
            _navItem(Icons.map_rounded, 'navMap'.tr(), 1),
            const SizedBox(width: 48),
            _navItem(Icons.smart_toy_rounded, 'navAwanis'.tr(), 2),
            _navItem(Icons.receipt_long_rounded, 'navClaims'.tr(), 3),
          ],
        ),
      ),
    );
  }

  Widget _navItem(IconData icon, String label, int index) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? AppColors.primary : AppColors.textSecondary;
    return InkWell(
      onTap: () {
        setState(() => _currentIndex = index);
      },
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

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4)),
      ],
    );
  }

  Widget _buildEmergencyHeader(String uid, String name) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
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
                    Text(
                      '${_greeting()},',
                      style: GoogleFonts.inter(
                          color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      name.isNotEmpty ? name : 'Warga SIGAP'.tr(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('citizen_profiles')
                    .doc(uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  String? profileImageUrl;
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null) {
                      profileImageUrl = data['profileImageUrl'] as String?;
                    }
                  }

                  ImageProvider? avatarProvider;
                  if (profileImageUrl != null && profileImageUrl.isNotEmpty) {
                    if (profileImageUrl.startsWith('data:image')) {
                      final base64Str = profileImageUrl.split(',').last;
                      avatarProvider = MemoryImage(base64Decode(base64Str));
                    } else {
                      avatarProvider = NetworkImage(profileImageUrl);
                    }
                  }

                  return Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      image: avatarProvider != null
                          ? DecorationImage(
                              image: avatarProvider, fit: BoxFit.cover)
                          : null,
                    ),
                    child: avatarProvider == null
                        ? const Icon(Icons.person_rounded,
                            color: Colors.white, size: 30)
                        : null,
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('citizen_profiles')
                .doc(uid)
                .snapshots(),
            builder: (context, snapshot) {
              String rawStatus = 'Selamat'.tr();
              String status = 'Selamat (Safe 🟢)'.tr();
              String statusDesc = 'Selamat di lokasi berdaftar'.tr();
              Color statusColor = AppColors.safe;
              IconData statusIcon = Icons.check_circle_rounded;

              if (snapshot.hasData && snapshot.data!.exists) {
                final profileData =
                    snapshot.data!.data() as Map<String, dynamic>;
                rawStatus =
                    profileData['safetyStatus'] as String? ?? 'Selamat'.tr();

                if (rawStatus == 'Berpindah'.tr()) {
                  status = 'Berpindah (Evacuated 🟡)'.tr();
                  statusDesc = 'Telah dipindahkan ke pusat pemindahan'.tr();
                  statusColor = AppColors.warning;
                  statusIcon = Icons.home_work_rounded;
                } else if (rawStatus == 'Perlu Bantuan'.tr()) {
                  status = 'Perlu Bantuan (Need Help 🔴)'.tr();
                  statusDesc = 'Memerlukan bantuan penyelamat segera!'.tr();
                  statusColor = AppColors.danger;
                  statusIcon = Icons.error_rounded;
                } else {
                  status = 'Selamat (Safe 🟢)'.tr();
                  statusDesc = 'Selamat di lokasi berdaftar'.tr();
                  statusColor = AppColors.safe;
                  statusIcon = Icons.check_circle_rounded;
                }
              }

              return InkWell(
                onTap: () => _showSafetyStatusDialog(uid, rawStatus),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.6),
                              blurRadius: 12,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Icon(statusIcon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Status Keselamatan (Ketik untuk tukar)'.tr(),
                              style: GoogleFonts.inter(
                                  color: Colors.white70, fontSize: 12),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              status,
                              style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600),
                            ),
                            Text(
                              statusDesc,
                              style: GoogleFonts.inter(
                                  color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.edit_rounded,
                          color: Colors.white70, size: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showSafetyStatusDialog(String uid, String currentStatus) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Kemaskini Status Keselamatan'.tr(),
            style:
                GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _safetyStatusOption(
                uid,
                'Selamat'.tr(),
                'Safe 🟢'.tr(),
                'Saya selamat dan tidak memerlukan bantuan.'.tr(),
                AppColors.safe,
                currentStatus),
            const SizedBox(height: 12),
            _safetyStatusOption(
                uid,
                'Berpindah'.tr(),
                'Evacuated 🟡'.tr(),
                'Saya telah dipindahkan ke pusat pemindahan.'.tr(),
                AppColors.warning,
                currentStatus),
            const SizedBox(height: 12),
            _safetyStatusOption(
                uid,
                'Perlu Bantuan'.tr(),
                'Need Help 🔴'.tr(),
                'Saya terperangkap atau memerlukan bantuan segera!'.tr(),
                AppColors.danger,
                currentStatus),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tutup'.tr(),
                style: GoogleFonts.inter(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _safetyStatusOption(String uid, String value, String label,
      String desc, Color color, String current) {
    final isSelected = current == value;
    return InkWell(
      onTap: () async {
        Navigator.pop(context);
        await FirebaseFirestore.instance
            .collection('citizen_profiles')
            .doc(uid)
            .set({
          'safetyStatus': value,
        }, SetOptions(merge: true));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('statusUpdated'.tr(args: [label])),
              backgroundColor: color,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? color : AppColors.divider,
              width: isSelected ? 2 : 1),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: 0.6),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: GoogleFonts.inter(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSOSTracker(String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamMyActiveAndRespondedSOSReports(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Client-side safety filter: exclude cancelled/resolved reports
        // in case Firestore composite index is missing or has propagation delay.
        final activeDocs = snapshot.data!.docs.where((d) {
          final status =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return status == SosReportModel.statusActive ||
              status == SosReportModel.statusResponded;
        }).toList();

        if (activeDocs.isEmpty) return const SizedBox.shrink();

        final doc = activeDocs.first;
        final report = SosReportModel.fromDocument(doc);

        final bool isResponded =
            report.status == SosReportModel.statusResponded;
        final Color cardColor = isResponded ? AppColors.safe : AppColors.danger;
        final IconData icon =
            isResponded ? Icons.handshake_rounded : Icons.radar_rounded;
        final String statusLabel = isResponded
            ? 'Penyelamat Sedang Datang!'.tr()
            : 'Mencari Penyelamat...'.tr();
        final String statusDesc = isResponded
            ? 'sosAcceptedBy'
                .tr(args: [report.responderName ?? "Sukarelawan".tr()])
            : 'Laporan SOS anda telah diterima sistem. Sukarelawan berdekatan sedang dimaklumkan.'
                .tr();

        String etaStr = 'Anggaran Masa Tiba: 8 - 15 minit'.tr();
        if (isResponded) {
          final int hash = report.id.hashCode.abs();
          final int etaMin = 5 + (hash % 10);
          etaStr = 'etaMinutes'.tr(args: [etaMin.toString()]);
        }

        return GestureDetector(
          onTap: () => _showCitizenActiveSOSDetails(report, cardColor),
          child: Container(
            margin: const EdgeInsets.only(top: 20),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: cardColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: cardColor.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: cardColor,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            statusLabel,
                            style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: cardColor,
                            ),
                          ),
                          Text(
                            'typeAndTap'.tr(args: [report.type]),
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  statusDesc,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
                if (isResponded) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 8),
                        Text(
                          etaStr,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            _confirmCancelSOS(report.id, report.type),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                          side: const BorderSide(color: AppColors.danger),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        child: Text('Batal SOS'.tr(),
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            _isSirenActive = true;
                          });
                        },
                        icon: const Icon(Icons.campaign_rounded, size: 16),
                        label: Text('Siren'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          launchUrl(Uri.parse('tel:999'));
                        },
                        icon: const Icon(Icons.phone_rounded, size: 16),
                        label: Text('Hubungi'.tr()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCitizenActiveSOSDetails(SosReportModel report, Color cardColor) {
    final bool isResponded = report.status == SosReportModel.statusResponded;
    String etaStr = 'Anggaran Masa Tiba: 8 - 15 minit'.tr();
    if (isResponded) {
      final int hash = report.id.hashCode.abs();
      final int etaMin = 5 + (hash % 10);
      etaStr = '$etaMin minit';
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                children: [
                  Text(
                    'Perincian Laporan SOS'.tr(),
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(report.latitude, report.longitude),
                        zoom: 14.5,
                      ),
                      myLocationEnabled: false,
                      zoomControlsEnabled: false,
                      markers: {
                        Marker(
                          markerId: const MarkerId('victim'),
                          position: LatLng(report.latitude, report.longitude),
                          icon: BitmapDescriptor.defaultMarkerWithHue(
                              BitmapDescriptor.hueRed),
                          infoWindow: InfoWindow(
                              title:
                                  'yourLocationType'.tr(args: [report.type])),
                        ),
                        if (isResponded)
                          Marker(
                            markerId: const MarkerId('responder'),
                            position: LatLng(report.latitude + 0.003,
                                report.longitude + 0.003),
                            icon: BitmapDescriptor.defaultMarkerWithHue(
                                BitmapDescriptor.hueAzure),
                            infoWindow: InfoWindow(
                                title: 'rescuerName'
                                    .tr(args: [report.responderName!])),
                          ),
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: cardColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border:
                          Border.all(color: cardColor.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              isResponded
                                  ? Icons.check_circle_rounded
                                  : Icons.pending_rounded,
                              color: cardColor,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isResponded
                                  ? 'Bantuan Sedang Menuju'.tr()
                                  : 'Menunggu Penyelamat'.tr(),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: cardColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isResponded
                              ? 'sosReceivedBy'
                                  .tr(args: [report.responderName!])
                              : 'Laporan SOS anda telah dihantar ke sistem. Sukarelawan berhampiran sedang dipanggil.'
                                  .tr(),
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        if (isResponded) ...[
                          const SizedBox(height: 12),
                          const Divider(height: 1),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Anggaran Masa Tiba:'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary),
                              ),
                              Text(
                                etaStr,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Reinforcement needed banner (if volunteer requested backup)
                  if (isResponded && report.needBackup) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.dangerLight,
                        borderRadius: BorderRadius.circular(12),
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
                                  'Bantuan Tambahan Diminta'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.danger),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Penyelamat sedang meminta unit tambahan/squad sokongan ke lokasi.'
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
                    const SizedBox(height: 20),
                  ],

                  // Report Details Section
                  Text(
                    'Maklumat Laporan'.tr(),
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  _detailField('Jenis Kecemasan'.tr(), report.type),
                  _detailField('Tahap Keutamaan'.tr(), report.urgency),
                  if (report.description.isNotEmpty)
                    _detailField('Keterangan'.tr(), report.description),
                  _detailField(
                      'Lokasi/Alamat'.tr(),
                      report.address.isNotEmpty
                          ? report.address
                          : '${report.latitude}, ${report.longitude}'),
                  if (report.formattedSpecificDetails.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Spesifikasi SOS'.tr(),
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary),
                    ),
                    const SizedBox(height: 8),
                    ...report.formattedSpecificDetails.entries.map((entry) {
                      return _detailField(entry.key, entry.value);
                    }),
                  ],
                  const SizedBox(height: 24),

                  // Actions
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _confirmCancelSOS(report.id, report.type);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: Text('Batal SOS'.tr(),
                              style: TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() {
                              _isSirenActive = true;
                            });
                          },
                          icon: const Icon(Icons.campaign_rounded, size: 18),
                          label: Text('Siren'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.warning,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            launchUrl(Uri.parse('tel:999'));
                          },
                          icon: const Icon(Icons.phone_rounded, size: 18),
                          label: Text('Hubungi'.tr()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Widget _buildAlertBanner() {
    return GestureDetector(
      onTap: () {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: AppColors.warning),
                const SizedBox(width: 8),
                Text('Amaran Banjir Aktif'.tr(),
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.warning)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Lokasi: Lembah Klang'.tr(),
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 12),
                Text(
                  'Paras air sungai di stesen utama telah melepasi paras bahaya. Penduduk di kawasan rendah dinasihatkan bersedia untuk berpindah dan patuhi arahan pihak berkuasa.'
                      .tr(),
                  style: GoogleFonts.inter(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.5),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.warningLight.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Dikemaskini: 10 minit lepas'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.warning)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Tutup'.tr(),
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textSecondary)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() => _currentIndex = 1); // Go to Map tab
                },
                child: Text('Lihat Peta'.tr(),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warningLight.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.warning_amber_rounded,
                  color: AppColors.warning, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amaran Banjir Aktif'.tr(),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Lembah Klang — Paras Air Meningkat'.tr(),
                    style: GoogleFonts.inter(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.textSecondary, size: 24),
          ],
        ),
      ),
    );
  }

  void _showSOSTypeDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Pilih Jenis Kecemasan'.tr(),
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            Text(
                'Laporan SOS akan dihantar kepada sukarelawan berdekatan.'.tr(),
                style: GoogleFonts.inter(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _sosOption(
                    Icons.water_drop_rounded, 'Banjir'.tr(), Colors.blue),
                _sosOption(
                    Icons.landscape_rounded, 'Tanah Runtuh'.tr(), Colors.brown),
                _sosOption(Icons.local_fire_department_rounded,
                    'Kebakaran'.tr(), Colors.orange),
                _sosOption(Icons.medical_services_rounded, 'Perubatan'.tr(),
                    Colors.red),
                _sosOption(Icons.person_search_rounded, 'Orang Hilang'.tr(),
                    Colors.purple),
              ],
            ),
            const SizedBox(height: 24),
            // Cancel active SOS button
            _buildCancelActiveSOSButton(),
            const SizedBox(height: 12),
            SigapButton(
              label: 'Batal'.tr(),
              onPressed: () => Navigator.pop(ctx),
              variant: SigapButtonVariant.outlined,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _sosOption(IconData icon, String label, Color color) {
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        _showSOSDescriptionDialog(label);
      },
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, color: color, size: 32),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  /// Step 2 — Description input after selecting type
  void _showSOSDescriptionDialog(String type) {
    final descCtrl = TextEditingController();
    final urgency = SosReportModel.urgencyForType(type);
    final skills = SosReportModel.skillsForType(type);

    Color urgencyColor;
    switch (urgency) {
      case 'KRITIKAL':
        urgencyColor = const Color(0xFFDC2626);
        break;
      case 'TINGGI':
        urgencyColor = const Color(0xFFF97316);
        break;
      default:
        urgencyColor = const Color(0xFFFBBF24);
    }

    File? pickedSOSImage;

    // Dynamic specifications state variables
    String waterLevel = 'Paras Pinggang'.tr();
    String trappedPeople = 'Tiada'.tr();
    bool needBoat = false;

    String fireType = 'Rumah Kediaman'.tr();
    String fireTrappedPeople = 'Tiada'.tr();

    bool accessBlocked = false;
    bool stillActive = false;

    String victimCondition = 'Sedar & Bernafas'.tr();
    String ageGroup = 'Dewasa'.tr();

    final missingNameCtrl = TextEditingController();
    final missingAgeCtrl = TextEditingController();
    final lastSeenClothesCtrl = TextEditingController();

    bool agreedPDPA = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding:
                EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.grey[300],
                              borderRadius: BorderRadius.circular(2))),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: Text('sosReportType'.tr(args: [type]),
                              style: GoogleFonts.poppins(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary)),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: urgencyColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(urgency,
                              style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: skills
                          .map((s) => Chip(
                                label: Text(s,
                                    style: GoogleFonts.inter(
                                        fontSize: 10,
                                        color: AppColors.textSecondary)),
                                backgroundColor: AppColors.background,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ))
                          .toList(),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Huraikan keadaan kecemasan anda...'.tr(),
                        hintStyle: GoogleFonts.inter(
                            fontSize: 13, color: AppColors.textHint),
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: AppColors.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(
                              color: AppColors.primary, width: 2),
                        ),
                      ),
                    ),

                    // DYNAMIC SPECIFICATION FIELDS PER EMERGENCY TYPE
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.assignment_turned_in_rounded,
                                  color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'specificDetailsType'.tr(args: [type]),
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (type == 'Banjir'.tr()) ...[
                            _buildDropdownField(
                              label: 'Anggaran Paras Air'.tr(),
                              value: waterLevel,
                              items: [
                                'Bawah Lutut'.tr(),
                                'Paras Pinggang'.tr(),
                                'Paras Dada'.tr(),
                                'Melepasi Bumbung'.tr()
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  waterLevel = val!;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownField(
                              label: 'Jumlah Mangsa Terperangkap'.tr(),
                              value: trappedPeople,
                              items: [
                                'Tiada'.tr(),
                                '1 orang',
                                '2 orang',
                                '3 orang',
                                '4 orang',
                                '5+ orang'
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  trappedPeople = val!;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildSwitchField(
                              label: 'Memerlukan Bot Penyelamat?'.tr(),
                              value: needBoat,
                              onChanged: (val) {
                                setModalState(() {
                                  needBoat = val;
                                });
                              },
                            ),
                          ] else if (type == 'Tanah Runtuh'.tr()) ...[
                            _buildSwitchField(
                              label: 'Laluan/Akses Utama Terhalang?'.tr(),
                              value: accessBlocked,
                              onChanged: (val) {
                                setModalState(() {
                                  accessBlocked = val;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildSwitchField(
                              label: 'Pergerakan Tanah Masih Aktif?'.tr(),
                              value: stillActive,
                              onChanged: (val) {
                                setModalState(() {
                                  stillActive = val;
                                });
                              },
                            ),
                          ] else if (type == 'Kebakaran'.tr()) ...[
                            _buildDropdownField(
                              label: 'Jenis Kebakaran'.tr(),
                              value: fireType,
                              items: [
                                'Rumah Kediaman'.tr(),
                                'Hutan / Belukar'.tr(),
                                'Litar Pintas'.tr(),
                                'Bahan Kimia / Gas'.tr()
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  fireType = val!;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownField(
                              label: 'Ada Mangsa Terperangkap?'.tr(),
                              value: fireTrappedPeople,
                              items: [
                                'Tiada'.tr(),
                                '1 orang',
                                '2 orang',
                                '3 orang',
                                '4 orang',
                                '5+ orang'
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  fireTrappedPeople = val!;
                                });
                              },
                            ),
                          ] else if (type == 'Perubatan'.tr()) ...[
                            _buildDropdownField(
                              label: 'Keadaan/Kondisi Mangsa'.tr(),
                              value: victimCondition,
                              items: [
                                'Sedar & Bernafas'.tr(),
                                'Pengsan / Tiada Respon'.tr(),
                                'Pendarahan Teruk'.tr(),
                                'Sakit Dada / Sesak Nafas'.tr()
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  victimCondition = val!;
                                });
                              },
                            ),
                            const SizedBox(height: 12),
                            _buildDropdownField(
                              label: 'Kumpulan Umur Mangsa'.tr(),
                              value: ageGroup,
                              items: [
                                'Kanak-kanak / Bayi'.tr(),
                                'Dewasa'.tr(),
                                'Warga Emas'.tr()
                              ],
                              onChanged: (val) {
                                setModalState(() {
                                  ageGroup = val!;
                                });
                              },
                            ),
                          ] else if (type == 'Orang Hilang'.tr()) ...[
                            _buildTextField(
                              label: 'Nama Penuh Orang Hilang'.tr(),
                              controller: missingNameCtrl,
                              hint: 'Masukkan nama mangsa...'.tr(),
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              label: 'Anggaran Umur'.tr(),
                              controller: missingAgeCtrl,
                              hint: 'Contoh: 12 tahun, 70 tahun...'.tr(),
                            ),
                            const SizedBox(height: 12),
                            _buildTextField(
                              label: 'Pakaian Terakhir Dilihat'.tr(),
                              controller: lastSeenClothesCtrl,
                              hint: 'Contoh: Baju T biru, seluar hitam...'.tr(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Image Picker Section
                    Text('Gambar Bukti (Pilihan)'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 8),
                    if (pickedSOSImage == null)
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picker = ImagePicker();
                                final pickedFile = await picker.pickImage(
                                  source: ImageSource.camera,
                                  maxWidth: 800,
                                  imageQuality: 60,
                                );
                                if (pickedFile != null) {
                                  setModalState(() {
                                    pickedSOSImage = File(pickedFile.path);
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.camera_alt_rounded,
                                        color: AppColors.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text('Kamera'.tr(),
                                        style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final picker = ImagePicker();
                                final pickedFile = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  maxWidth: 800,
                                  imageQuality: 60,
                                );
                                if (pickedFile != null) {
                                  setModalState(() {
                                    pickedSOSImage = File(pickedFile.path);
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                height: 50,
                                decoration: BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.photo_library_rounded,
                                        color: AppColors.primary, size: 20),
                                    const SizedBox(width: 8),
                                    Text('Galeri'.tr(),
                                        style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Stack(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 140,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: FileImage(pickedSOSImage!),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () {
                                setModalState(() {
                                  pickedSOSImage = null;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.gps_fixed_rounded,
                            size: 14, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('Lokasi GPS akan dikesan secara automatik'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CheckboxListTile(
                      value: agreedPDPA,
                      onChanged: (val) {
                        setModalState(() => agreedPDPA = val ?? false);
                      },
                      title: Row(
                        children: [
                          Expanded(
                              child: Text(
                                  'Saya bersetuju berkongsi lokasi GPS ini bagi tujuan menyelamat mengikut Dasar Privasi & PDPA.'
                                      .tr(),
                                  style: GoogleFonts.inter(fontSize: 12))),
                          IconButton(
                            icon: const Icon(Icons.info_outline_rounded,
                                size: 16, color: AppColors.primary),
                            onPressed: () {
                              Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (context) =>
                                          const PrivacyPolicyScreen()));
                            },
                          ),
                        ],
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: SigapButton(
                            label: 'Batal'.tr(),
                            onPressed: () => Navigator.pop(ctx),
                            variant: SigapButtonVariant.outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SigapButton(
                            label: _isSubmittingSOS
                                ? 'Menghantar...'.tr()
                                : 'Hantar SOS'.tr(),
                            isLoading: _isSubmittingSOS,
                            onPressed: _isSubmittingSOS
                                ? null
                                : () async {
                                    if (!agreedPDPA) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                              content: Text(
                                                  'Anda perlu bersetuju dengan Dasar Privasi & PDPA sebelum menghantar SOS.'
                                                      .tr())));
                                      return;
                                    }
                                    setModalState(() {
                                      _isSubmittingSOS = true;
                                    });

                                    final Map<String, dynamic> specDetails = {};
                                    if (type == 'Banjir'.tr()) {
                                      specDetails['waterLevel'] = waterLevel;
                                      specDetails['trappedPeople'] =
                                          trappedPeople;
                                      specDetails['needBoat'] = needBoat;
                                    } else if (type == 'Tanah Runtuh'.tr()) {
                                      specDetails['accessBlocked'] =
                                          accessBlocked;
                                      specDetails['stillActive'] = stillActive;
                                    } else if (type == 'Kebakaran'.tr()) {
                                      specDetails['fireType'] = fireType;
                                      specDetails['hasTrapped'] =
                                          fireTrappedPeople;
                                    } else if (type == 'Perubatan'.tr()) {
                                      specDetails['victimCondition'] =
                                          victimCondition;
                                      specDetails['ageGroup'] = ageGroup;
                                    } else if (type == 'Orang Hilang'.tr()) {
                                      specDetails['missingName'] =
                                          missingNameCtrl.text.trim();
                                      specDetails['missingAge'] =
                                          missingAgeCtrl.text.trim();
                                      specDetails['lastSeenClothes'] =
                                          lastSeenClothesCtrl.text.trim();
                                    }

                                    final navigator = Navigator.of(ctx);
                                    await _submitSOS(
                                        type,
                                        descCtrl.text.trim(),
                                        urgency,
                                        skills,
                                        pickedSOSImage,
                                        specDetails);
                                    if (mounted) {
                                      setState(() {
                                        _isSubmittingSOS = false;
                                      });
                                    }
                                    navigator.pop();
                                  },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _submitSOS(
    String type,
    String description,
    String urgency,
    List<String> requiredSkills,
    File? imageFile,
    Map<String, dynamic> specificDetails,
  ) async {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) {
      _showErrorSnackbar('Sila log masuk untuk menghantar SOS'.tr());
      return;
    }

    // Use a completer to track loading state properly
    final navigator = Navigator.of(context);

    try {
      debugPrint('🚀 Starting SOS submission for: $type');

      // STEP 1: Get GPS Location with TIMEOUT
      debugPrint('📍 Getting GPS location...'.tr());
      Position? position;
      try {
        position = await _locationService.getCurrentPosition().timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            debugPrint('⚠️ GPS timeout after 15 seconds'.tr());
            throw Exception(
                'Gagal mendapatkan lokasi GPS. Sila pastikan GPS dihidupkan.'
                    .tr());
          },
        );
        debugPrint(
            '✅ GPS obtained: ${position.latitude}, ${position.longitude}');
      } catch (locError) {
        debugPrint('❌ Location error: $locError');
        _showErrorSnackbar('failedGetLocation'.tr(args: [locError.toString()]));
        return;
      }

      // STEP 2: Get address (don't let this hang)
      debugPrint('📍 Getting address...'.tr());
      String address = '';
      try {
        address = await _locationService
            .getAddressFromCoords(
              position.latitude,
              position.longitude,
            )
            .timeout(const Duration(seconds: 10));
        debugPrint('✅ Address: $address');
      } catch (addrError) {
        debugPrint('⚠️ Address lookup failed: $addrError');
        address = '${position.latitude}, ${position.longitude}';
      }

      // STEP 3: Get citizen profile (with timeout)
      debugPrint('📞 Getting citizen profile...'.tr());
      String phone = '';
      try {
        final citizenProfile = await _firestoreService
            .getCitizenProfile(authState.uid)
            .timeout(const Duration(seconds: 10));
        phone = citizenProfile?['phone'] as String? ?? '';
        debugPrint('✅ Phone: $phone');
      } catch (profileError) {
        debugPrint('⚠️ Profile fetch failed: $profileError');
        phone = '';
      }

      // STEP 4: Upload image (if any) with timeout
      String? imageUrl;
      if (imageFile != null) {
        debugPrint('📸 Uploading image...'.tr());
        try {
          final filename = 'sos_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final storageRef =
              FirebaseStorage.instance.ref().child('sos_evidence/$filename');

          // Compress image first to reduce upload time
          final bytes = await imageFile.readAsBytes();
          final compressedBytes = await _compressImage(bytes);

          final uploadTask = storageRef.putData(
            compressedBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );

          final snapshot =
              await uploadTask.timeout(const Duration(seconds: 30));
          imageUrl = await snapshot.ref.getDownloadURL();
          debugPrint('✅ Image uploaded: $imageUrl');
        } catch (storageError) {
          debugPrint('⚠️ Storage upload failed: $storageError');
          // Fallback to Base64 (no network dependency)
          try {
            final bytes = await imageFile.readAsBytes();
            final base64String = base64Encode(bytes);
            imageUrl = 'data:image/jpeg;base64,$base64String';
            debugPrint('✅ Image encoded to Base64 (${imageUrl.length} chars)');
          } catch (base64Error) {
            debugPrint('⚠️ Base64 encoding failed: $base64Error');
          }
        }
      }

      // STEP 5: Create SOS report in Firestore with timeout
      debugPrint('📤 Creating SOS in Firestore...'.tr());
      final reportData = SosReportModel(
        id: '',
        reporterId: authState.uid,
        reporterName: authState.displayName.isNotEmpty
            ? authState.displayName
            : 'Warga SIGAP'.tr(),
        reporterPhone: phone,
        type: type,
        description: description.isNotEmpty
            ? description
            : 'emergencyNeedHelp'.tr(args: [type]),
        urgency: urgency,
        latitude: position.latitude,
        longitude: position.longitude,
        address: address,
        requiredSkills: requiredSkills,
        imageUrl: imageUrl,
        specificDetails: specificDetails,
      ).toMap();

      await _firestoreService.createSOSReport(reportData).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('firestoreTimeout'.tr());
        },
      );
      debugPrint('✅ SOS created successfully!'.tr());

      // Close the loading dialog and show success
      if (mounted) {
        navigator.pop(); // Close the SOS form dialog

        // Show success
        final authority = AuthorityRoutingService.instance.getAuthority(type);
        _showAuthorityRoutedSheet(authority, type);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ SOS submission FAILED: $e');
      debugPrint('📚 Stack trace: $stackTrace');

      // Make sure to close any loading state
      if (mounted) {
        navigator.pop(); // Close the loading dialog if still open
        _showErrorSnackbar(
            'failedSendSos'.tr(args: [e.toString().split('\n').first]));
      }
    }
  }

  // Helper method to compress image
  Future<Uint8List> _compressImage(List<int> bytes) async {
    // Simple compression - you can add proper image compression here
    // For now, just return as-is or implement using image package
    return Uint8List.fromList(bytes);
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// Shows a bottom sheet confirming the authority routed for an SOS incident.
  void _showAuthorityRoutedSheet(
      AuthorityContact authority, String incidentType) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: authority.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(authority.icon, color: authority.color, size: 40),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: AppColors.safe, size: 20),
                const SizedBox(width: 8),
                Text(
                  'SOS Berjaya Dihantar!'.tr(),
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'sosRoutedTo'.tr(args: [incidentType]),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: authority.color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: authority.color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    authority.name,
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(authority.description,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.phone_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(authority.phone,
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(ctx);
                  AuthorityRoutingService.instance.callAuthority(authority);
                },
                icon: const Icon(Icons.phone_rounded),
                label: Text(
                    'contactAuthorityNow'.tr(args: [authority.shortName]),
                    style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: authority.color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Tutup'.tr(),
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Confirms and cancels a citizen's pending claim.
  void _confirmCancelClaim(String claimId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Batal Tuntutan?'.tr(),
            style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
        content: Text(
            'Adakah anda pasti mahu membatalkan tuntutan ini? Tindakan ini tidak boleh dibalikkan.'
                .tr(),
            style: GoogleFonts.inter(
                color: AppColors.textSecondary, fontSize: 13)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tidak'.tr(),
                style: GoogleFonts.inter(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _firestoreService.cancelClaim(claimId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Tuntutan telah dibatalkan.'.tr(),
                          style: GoogleFonts.inter()),
                      backgroundColor: AppColors.safe,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text('failedCancel'.tr(args: [e.toString()])),
                        backgroundColor: AppColors.danger),
                  );
                }
              }
            },
            child: Text('Ya, Batal'.tr(),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700, color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildCancelActiveSOSButton() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamMyActiveSOSReports(authState.uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        // Client-side filter: only show truly 'active' reports.
        final activeDocs = snapshot.data!.docs.where((d) {
          final s =
              (d.data() as Map<String, dynamic>)['status'] as String? ?? '';
          return s == SosReportModel.statusActive;
        }).toList();

        if (activeDocs.isEmpty) return const SizedBox.shrink();

        final activeCount = activeDocs.length;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.danger),
                  const SizedBox(width: 8),
                  Text('$activeCount laporan SOS aktif',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.danger)),
                ],
              ),
              const SizedBox(height: 12),
              ...activeDocs.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${data['type'] ?? '.tr()SOS'} — ${data['address'] ?? '.tr()Lokasi tidak diketahui'}',
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () {
                          Navigator.pop(context); // Pop the SOS Type Dialog first
                          _confirmCancelSOS(doc.id, data['type'] as String? ?? 'SOS');
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Batalkan'.tr(),
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  /// Confirm SOS cancellation with reason
  void _confirmCancelSOS(String docId, String type) {
    final reasonCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.cancel_rounded, color: AppColors.danger, size: 24),
            const SizedBox(width: 12),
            Text('cancelSosType'.tr(args: [type]),
                style: GoogleFonts.poppins(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Laporan SOS ini akan dibatalkan dan dibuang dari papan tugas sukarelawan.'
                    .tr(),
                style: GoogleFonts.inter(
                    fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: reasonCtrl,
              decoration: InputDecoration(
                hintText: 'Sebab pembatalan (pilihan)'.tr(),
                hintStyle:
                    GoogleFonts.inter(fontSize: 13, color: AppColors.textHint),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: AppColors.divider),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Tidak'.tr(),
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _firestoreService.cancelSOSReport(
                  docId,
                  reasonCtrl.text.trim().isNotEmpty
                      ? reasonCtrl.text.trim()
                      : 'Penggera palsu / Situasi terkawal'.tr(),
                );
                if (mounted) {
                  setState(() {
                    _isSirenActive = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('SOS berjaya dibatalkan.'.tr()),
                      backgroundColor: AppColors.safe,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('failedCancelSos'.tr(args: [e.toString()])),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              }
            },
            child: Text('Ya, Batalkan'.tr(),
                style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title,
      {String? actionLabel, VoidCallback? onAction}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
                minimumSize: Size.zero, padding: EdgeInsets.zero),
            child: Text(
              actionLabel,
              style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary),
            ),
          )
      ],
    );
  }

  Widget _buildLiveCrisisMap() {
    return StreamBuilder<QuerySnapshot>(
      stream: _firestoreService.streamDisasterZones(),
      builder: (context, zoneSnapshot) {
        final Set<Circle> circles = {
          Circle(
            circleId: const CircleId('danger_zone_1'),
            center: const LatLng(3.1390, 101.6869),
            radius: 1200,
            fillColor: Colors.red.withValues(alpha: 0.15),
            strokeColor: Colors.red,
            strokeWidth: 2,
          ),
        };

        if (zoneSnapshot.hasData) {
          for (final doc in zoneSnapshot.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            final lat = (data['epicenterLat'] as num).toDouble();
            final lng = (data['epicenterLng'] as num).toDouble();
            final rad = (data['radius'] as num).toDouble();
            circles.add(
              Circle(
                circleId: CircleId('fire_zone_${doc.id}'),
                center: LatLng(lat, lng),
                radius: rad,
                fillColor: Colors.red.withValues(alpha: 0.15),
                strokeColor: Colors.red,
                strokeWidth: 2,
              ),
            );
          }
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.streamActiveSOSReports(),
          builder: (context, sosSnapshot) {
            final Set<Marker> markers = {
              // Shelters
              Marker(
                markerId: const MarkerId('shelter_1'),
                position: const LatLng(3.1550, 101.7100),
                infoWindow: InfoWindow(
                    title: 'PPS Dewan Komuniti Ampang'.tr(),
                    snippet: 'Kapasiti: 150/300 orang | Status: Aktif'.tr()),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen),
              ),
              Marker(
                markerId: const MarkerId('shelter_2'),
                position: const LatLng(3.2000, 101.6800),
                infoWindow: InfoWindow(
                    title: 'PPS SK Selayang'.tr(),
                    snippet: 'Kapasiti: 80/200 orang | Status: Aktif'.tr()),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueGreen),
              ),
              // Relief Trucks
              Marker(
                markerId: const MarkerId('truck_1'),
                position: const LatLng(3.1450, 101.6950),
                infoWindow: InfoWindow(
                    title: 'Trak Bantuan Makanan APM'.tr(),
                    snippet: 'Status: Bergerak ke PPS Ampang'.tr()),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
              ),
              Marker(
                markerId: const MarkerId('truck_2'),
                position: const LatLng(3.1800, 101.6700),
                infoWindow: InfoWindow(
                    title: 'Lori Logistik SIGAP'.tr(),
                    snippet: 'Status: Mengedar selimut & khemah'.tr()),
                icon: BitmapDescriptor.defaultMarkerWithHue(
                    BitmapDescriptor.hueAzure),
              ),
            };

            final Set<Circle> mapCircles = Set<Circle>.from(circles);

            // Add halos for Shelters (Green)
            mapCircles.add(
              Circle(
                circleId: const CircleId('glow_shelter_1'),
                center: const LatLng(3.1550, 101.7100),
                radius: 350,
                fillColor: Colors.green.withValues(alpha: 0.15),
                strokeColor: Colors.green.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            );
            mapCircles.add(
              Circle(
                circleId: const CircleId('glow_shelter_2'),
                center: const LatLng(3.2000, 101.6800),
                radius: 350,
                fillColor: Colors.green.withValues(alpha: 0.15),
                strokeColor: Colors.green.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            );

            // Add halos for Relief Trucks (Blue)
            mapCircles.add(
              Circle(
                circleId: const CircleId('glow_truck_1'),
                center: const LatLng(3.1450, 101.6950),
                radius: 250,
                fillColor: Colors.blue.withValues(alpha: 0.15),
                strokeColor: Colors.blue.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            );
            mapCircles.add(
              Circle(
                circleId: const CircleId('glow_truck_2'),
                center: const LatLng(3.1800, 101.6700),
                radius: 250,
                fillColor: Colors.blue.withValues(alpha: 0.15),
                strokeColor: Colors.blue.withValues(alpha: 0.4),
                strokeWidth: 1,
              ),
            );

            if (sosSnapshot.hasData) {
              for (final doc in sosSnapshot.data!.docs) {
                final report = SosReportModel.fromDocument(doc);
                markers.add(
                  Marker(
                    markerId: MarkerId('sos_${report.id}'),
                    position: LatLng(report.latitude, report.longitude),
                    infoWindow: InfoWindow(
                      title: 'sosTypeUrgency'
                          .tr(args: [report.type, report.urgency]),
                      snippet: report.description.isNotEmpty
                          ? report.description
                          : report.address,
                    ),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed),
                  ),
                );
                // Glowing halo for active SOS report
                mapCircles.add(
                  Circle(
                    circleId: CircleId('glow_sos_${report.id}'),
                    center: LatLng(report.latitude, report.longitude),
                    radius: 300,
                    fillColor: Colors.red.withValues(alpha: 0.18),
                    strokeColor: Colors.red.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                );
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionHeader('Peta Krisis Langsung'.tr(),
                    actionLabel: 'Lihat Peta'.tr(), onAction: () {}),
                const SizedBox(height: 12),
                Container(
                  height: 480,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E3DF),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.divider),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Stack(
                    children: [
                      GoogleMap(
                        initialCameraPosition: const CameraPosition(
                          target: LatLng(3.1500, 101.6900),
                          zoom: 12.0,
                        ),
                        myLocationEnabled: true,
                        myLocationButtonEnabled: true,
                        markers: markers,
                        circles: mapCircles,
                        onMapCreated: (_) {},
                      ),
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                      color: Colors.greenAccent,
                                      shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text('Peta Masa Nyata'.tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _mapChip(Icons.home_work_rounded,
                                  'PPS (Shelter) 🟢'.tr(), Colors.green),
                              const SizedBox(width: 8),
                              _mapChip(Icons.local_shipping_rounded,
                                  'Trak Bantuan 🔵'.tr(), Colors.blue),
                              const SizedBox(width: 8),
                              _mapChip(Icons.dangerous_rounded,
                                  'Zon Bahaya 🔴'.tr(), Colors.red),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _mapChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildAwanisScreen() {
    return AwanisChatScreen();
  }

  Widget _buildFamilySafetyTracker(String uid) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Keselamatan Keluarga'.tr(),
            actionLabel: 'Urus'.tr(), onAction: () {
          context.push(AppRoutes.citizenProfile);
        }),
        const SizedBox(height: 16),
        StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('citizen_profiles')
              .doc(uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData || !snapshot.data!.exists) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Center(
                  child: Text(
                      'Sila kemaskini profil untuk menambah ahli keluarga.'
                          .tr(),
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
              );
            }

            final data = snapshot.data!.data() as Map<String, dynamic>;
            final members = (data['familyMembers'] as List<dynamic>?)
                    ?.map((e) => Map<String, dynamic>.from(e as Map))
                    .toList() ??
                [];

            if (members.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Center(
                  child: Text('Tiada rekod ahli keluarga.'.tr(),
                      style: GoogleFonts.inter(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
              );
            }

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: _cardDecoration(),
              child: Column(
                children: members.map((m) {
                  final name = m['name'] as String? ?? 'Tidak Diketahui'.tr();
                  final relation = m['relation'] as String? ?? '';
                  final status = m['status'] as String? ?? 'Selamat'.tr();
                  final location = m['lastKnownLocation'] as String? ??
                      'Belum dikemaskini'.tr();

                  Color color = AppColors.safe;
                  IconData icon = Icons.check_circle_rounded;
                  String displayStatus = 'Safe 🟢'.tr();

                  if (status == 'Berpindah'.tr()) {
                    color = AppColors.warning;
                    icon = Icons.home_work_rounded;
                    displayStatus = 'Evacuated 🟡'.tr();
                  } else if (status == 'Perlu Bantuan'.tr()) {
                    color = AppColors.danger;
                    icon = Icons.error_rounded;
                    displayStatus = 'Need Help 🔴'.tr();
                  } else {
                    color = AppColors.safe;
                    icon = Icons.check_circle_rounded;
                    displayStatus = 'Safe 🟢'.tr();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _familyMemberRow(
                        'nameRelation'.tr(args: [name, relation]),
                        displayStatus,
                        'locationStr'.tr(args: [location]),
                        color,
                        icon),
                  );
                }).toList(),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _familyMemberRow(
      String name, String status, String detail, Color color, IconData icon) {
    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(Icons.person_rounded, color: color, size: 24),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Text(detail,
                  style: GoogleFonts.inter(
                      fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.05),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Text(status,
                  style: GoogleFonts.inter(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildNearbyReliefCentre() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Pusat Pemindahan Terdekat'.tr()),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        color: AppColors.primaryLight.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(16)),
                    child: const Icon(Icons.home_work_rounded,
                        color: AppColors.primary, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Dewan Serbaguna UTM Skudai'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.location_on_rounded,
                                size: 14, color: AppColors.textSecondary),
                            const SizedBox(width: 6),
                            Text('2.5 km dari anda'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: AppColors.warningLight,
                        borderRadius: BorderRadius.circular(8)),
                    child: Text('Kapasiti 75%'.tr(),
                        style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.warning)),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                      child: _resourceIcon(
                          Icons.restaurant_rounded, 'Makanan'.tr())),
                  Expanded(
                      child:
                          _resourceIcon(Icons.local_drink_rounded, 'Air'.tr())),
                  Expanded(
                      child: _resourceIcon(
                          Icons.medical_services_rounded, 'Perubatan'.tr())),
                  Expanded(
                      child: _resourceIcon(
                          Icons.electrical_services_rounded, 'Elektrik'.tr())),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final url = Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=Dewan+Serbaguna+UTM+Skudai');
                    if (await canLaunchUrl(url)) {
                      await launchUrl(url);
                    }
                  },
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: Text('Navigasi Ke Pusat'.tr()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _resourceIcon(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 24, color: AppColors.textSecondary),
        const SizedBox(height: 8),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary),
            textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildReliefClaimTracker() {
    final authState = context.read<AuthBloc>().state;
    if (authState is! AuthAuthenticated) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Tuntutan Bantuan'.tr(),
            actionLabel: 'Mohon Baru'.tr(), onAction: _showSubmitClaimDialog),
        const SizedBox(height: 16),
        StreamBuilder<QuerySnapshot>(
          stream: _firestoreService.streamClaimsForCitizen(authState.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: _cardDecoration(),
                child: Center(
                  child: Text('Tiada tuntutan setakat ini.'.tr(),
                      style: GoogleFonts.inter(color: AppColors.textSecondary)),
                ),
              );
            }

            final allDocs = snapshot.data!.docs.toList();
            allDocs.sort((a, b) {
              final aData = a.data() as Map<String, dynamic>;
              final bData = b.data() as Map<String, dynamic>;
              final aTime = aData['createdAt'] as Timestamp?;
              final bTime = bData['createdAt'] as Timestamp?;
              if (aTime == null || bTime == null) return 0;
              return bTime.compareTo(aTime); // descending
            });

            final docs = allDocs.where((doc) {
              final status =
                  (doc.data() as Map<String, dynamic>)['status'] as String? ??
                      '';
              if (status == 'cancelled')
                return false; // Hide self-cancelled claims

              if (_selectedClaimFilter == 'Semua'.tr()) return true;
              if (_selectedClaimFilter == 'Dihantar'.tr() &&
                  (status == 'submitted' || status.toLowerCase() == 'dihantar'))
                return true;
              if (_selectedClaimFilter == 'Sedang Disemak'.tr() &&
                  (status == 'under_review' ||
                      status.toLowerCase() == 'sedang disemak'.tr()))
                return true;
              if (_selectedClaimFilter == 'Diluluskan'.tr() &&
                  (status == 'approved' ||
                      status.toLowerCase() == 'diluluskan')) return true;
              if (_selectedClaimFilter == 'Ditolak'.tr() &&
                  (status == 'rejected' || status.toLowerCase() == 'ditolak'))
                return true;
              return false;
            }).toList();

            final displayDocs = _showAllClaims ? docs : docs.take(3).toList();

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      'Semua'.tr(),
                      'Dihantar'.tr(),
                      'Sedang Disemak'.tr(),
                      'Diluluskan'.tr(),
                      'Ditolak'.tr()
                    ].map((filter) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text(filter,
                              style: GoogleFonts.inter(fontSize: 12)),
                          selected: _selectedClaimFilter == filter,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedClaimFilter = filter);
                            }
                          },
                          selectedColor:
                              AppColors.primary.withValues(alpha: 0.2),
                          checkmarkColor: AppColors.primary,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 16),
                if (docs.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: _cardDecoration(),
                    child: Center(
                      child: Text('Tiada tuntutan untuk status ini.'.tr(),
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondary)),
                    ),
                  )
                else
                  ...displayDocs.map((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final claim = ClaimModel.fromMap(doc.id, data);

                    Color statusColor = AppColors.warning;
                    String statusText = 'Dihantar'.tr();
                    double progress = 0.25;
                    String subText = 'Menunggu semakan pegawai'.tr();

                    if (claim.status == 'under_review') {
                      statusColor = Colors.purple;
                      statusText = 'Sedang Disemak'.tr();
                      progress = 0.5;
                      subText = 'Tuntutan sedang disemak oleh pegawai'.tr();
                    } else if (claim.status == 'approved') {
                      statusColor = AppColors.safe;
                      statusText = 'Diluluskan ✅'.tr();
                      progress = 1.0;
                      subText =
                          'Bantuan akan disalurkan dalam 7 hari bekerja'.tr();
                    } else if (claim.status == 'expired') {
                      statusColor = AppColors.textHint;
                      statusText = 'Tamat Tempoh'.tr();
                      progress = 1.0;
                      subText = 'Tuntutan tamat tempoh — hubungi pejabat'.tr();
                    } else if (claim.status == 'rejected') {
                      statusColor = AppColors.danger;
                      statusText = 'Ditolak'.tr();
                      progress = 1.0;
                      subText = claim.rejectReason ?? 'Tuntutan ditolak'.tr();
                    }

                    // Return a Column: main card + optional action banner (separate, no gesture conflict)
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Main claim card ──────────────────────────────
                        GestureDetector(
                          onTap: () => _showClaimDetailsDialog(claim),
                          child: Container(
                            margin: EdgeInsets.only(
                              bottom: (claim.status == 'under_review' &&
                                      claim.infoRequestReason != null &&
                                      claim.infoRequestReason!.isNotEmpty)
                                  ? 0
                                  : 12,
                            ),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: (claim.status == 'under_review' &&
                                        claim.infoRequestReason != null)
                                    ? Colors.orange.withValues(alpha: 0.5)
                                    : AppColors.divider,
                                width: (claim.status == 'under_review' &&
                                        claim.infoRequestReason != null)
                                    ? 1.5
                                    : 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                    color: AppColors.divider,
                                    blurRadius: 8,
                                    offset: const Offset(0, 2))
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        claim.type,
                                        style: GoogleFonts.inter(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.textPrimary),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(statusText,
                                        style: GoogleFonts.inter(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: statusColor)),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: LinearProgressIndicator(
                                      value: progress,
                                      minHeight: 10,
                                      backgroundColor: AppColors.divider,
                                      color: statusColor),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Icon(
                                      claim.status == 'rejected'
                                          ? Icons.error_outline_rounded
                                          : Icons.info_outline_rounded,
                                      size: 16,
                                      color: statusColor,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(subText,
                                          style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: AppColors.textSecondary)),
                                    ),
                                  ],
                                ),
                                if (claim.status == 'submitted') ...[
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      onPressed: () =>
                                          _confirmCancelClaim(claim.id),
                                      icon: const Icon(Icons.cancel_outlined,
                                          size: 16),
                                      label: Text('Batal Tuntutan'.tr()),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: AppColors.danger,
                                        side: const BorderSide(
                                            color: AppColors.danger),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),

                        // ── Action required banner (separate — no gesture conflict) ──
                        if (claim.status == 'under_review' &&
                            claim.infoRequestReason != null &&
                            claim.infoRequestReason!.isNotEmpty) ...[
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.07),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 14, color: Colors.orange),
                                    const SizedBox(width: 6),
                                    Text('⚠️  Tindakan Diperlukan'.tr(),
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.orange)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  claim.infoRequestReason!,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: AppColors.textPrimary,
                                      height: 1.4),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    // ← This is now OUTSIDE the GestureDetector — no conflict
                                    onPressed: () =>
                                        _showUpdateEvidenceDialog(claim),
                                    icon: const Icon(Icons.edit_note_rounded,
                                        size: 16),
                                    label:
                                        Text('Kemaskini Bukti & Maklumat'.tr()),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                      elevation: 0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ] else
                          const SizedBox(
                              height: 12), // spacing when no action banner
                      ],
                    );
                  }),
                if (docs.length > 3)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _showAllClaims = !_showAllClaims;
                      });
                    },
                    child: Text(
                        _showAllClaims
                            ? 'Tutup'.tr()
                            : 'seeAllCount'.tr(args: [docs.length.toString()]),
                        style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  void _showSubmitClaimDialog() {
    final formKey = GlobalKey<FormState>();
    final typeCtrl = TextEditingController();
    final locationCtrl = TextEditingController();
    final icCtrl = TextEditingController();
    final householdCtrl = TextEditingController(text: '1');
    final damageCtrl = TextEditingController();
    final bankNameCtrl = TextEditingController();
    final bankAccCtrl = TextEditingController();

    File? selectedImage;
    bool isUploading = false;

    // Compliance Checkboxes
    bool isKIR = false;
    bool isTruthful = false;
    bool agreedPDPA = false;

    final List<String> mockLocations = [
      'Taman Mutiara Rini, Johor Bahru, Johor'.tr(),
      'Ampang, Selangor'.tr(),
      'Hulu Langat, Selangor'.tr(),
      'Gombak, Selangor'.tr(),
      'Baling, Kedah'.tr(),
      'Kuantan, Pahang'.tr(),
      'Kota Bharu, Kelantan'.tr()
    ];

    showDialog(
      context: context,
      barrierDismissible: !isUploading,
      builder: (ctx) => StatefulBuilder(builder: (context, setState) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Mohon Tuntutan Baru'.tr(),
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: icCtrl,
                    decoration: InputDecoration(
                        labelText: 'No. Kad Pengenalan (IC)'.tr(),
                        hintText: 'xxxxxx-xx-xxxx'.tr()),
                    keyboardType: TextInputType.number,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sila isi ruangan ini'.tr()
                        : null,
                    onChanged: (value) {
                      // Auto format IC xxxxxx-xx-xxxx
                      String newValue = value.replaceAll('-', '.tr()');
                      if (newValue.length > 6) {
                        newValue =
                            '${newValue.substring(0, 6)}-${newValue.substring(6)}';
                      }
                      if (newValue.length > 9) {
                        newValue =
                            '${newValue.substring(0, 9)}-${newValue.substring(9)}';
                      }
                      if (newValue.length > 14) {
                        newValue = newValue.substring(0, 14);
                      }
                      if (icCtrl.text != newValue) {
                        icCtrl.value = TextEditingValue(
                          text: newValue,
                          selection:
                              TextSelection.collapsed(offset: newValue.length),
                        );
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: householdCtrl,
                    decoration: InputDecoration(
                        labelText: 'Saiz Isi Rumah (Bilangan)'.tr()),
                    keyboardType: TextInputType.number,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sila isi ruangan ini'.tr()
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: typeCtrl,
                    decoration: InputDecoration(
                        labelText:
                            'Jenis Bantuan (Cth: Makanan, Membaiki Rumah)'
                                .tr()),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sila isi ruangan ini'.tr()
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Autocomplete<String>(
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return const Iterable<String>.empty();
                      }
                      return mockLocations.where((String option) {
                        return option
                            .toLowerCase()
                            .contains(textEditingValue.text.toLowerCase());
                      });
                    },
                    onSelected: (String selection) {
                      locationCtrl.text = selection;
                    },
                    fieldViewBuilder: (context, textEditingController,
                        focusNode, onFieldSubmitted) {
                      // Sync internal autocomplete controller with our locationCtrl if needed,
                      // but actually we can just assign the listener.
                      locationCtrl.text = textEditingController.text;
                      textEditingController.addListener(() {
                        locationCtrl.text = textEditingController.text;
                      });
                      return TextFormField(
                        controller: textEditingController,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                            labelText: 'Lokasi / Zon Bencana'.tr(),
                            hintText: 'Mula menaip untuk carian...'.tr()),
                        validator: (value) => value == null || value.isEmpty
                            ? 'Sila isi ruangan ini'.tr()
                            : null,
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: damageCtrl,
                    decoration:
                        InputDecoration(labelText: 'Keterangan Kerosakan'.tr()),
                    maxLines: 3,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sila isi ruangan ini'.tr()
                        : null,
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: isUploading
                          ? null
                          : () async {
                              final ImagePicker picker = ImagePicker();
                              final XFile? image = await picker.pickImage(
                                  source: ImageSource.gallery,
                                  imageQuality: 70);
                              if (image != null) {
                                setState(
                                    () => selectedImage = File(image.path));
                              }
                            },
                      icon: Icon(
                          selectedImage != null
                              ? Icons.check_circle_rounded
                              : Icons.upload_rounded,
                          color: selectedImage != null
                              ? AppColors.safe
                              : AppColors.primary),
                      label: Text(selectedImage != null
                          ? 'Gambar Dipilih (Tukar)'.tr()
                          : 'Muat Naik Gambar Bukti'.tr()),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: selectedImage != null
                            ? AppColors.safe
                            : AppColors.primary,
                        side: BorderSide(
                            color: selectedImage != null
                                ? AppColors.safe
                                : AppColors.primary),
                      ),
                    ),
                  ),
                  if (selectedImage == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text('Sila muat naik gambar bukti kerosakan.'.tr(),
                          style: GoogleFonts.inter(
                              fontSize: 12, color: AppColors.danger)),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: bankNameCtrl,
                    decoration: InputDecoration(
                        labelText: 'Nama Bank (EFT BWI)'.tr(),
                        hintText: 'Cth: Maybank'.tr()),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sila isi ruangan ini'.tr()
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: bankAccCtrl,
                    decoration:
                        InputDecoration(labelText: 'No. Akaun Bank'.tr()),
                    keyboardType: TextInputType.number,
                    validator: (value) => value == null || value.isEmpty
                        ? 'Sila isi ruangan ini'.tr()
                        : null,
                  ),
                  const SizedBox(height: 16),
                  // Compliance Declarations
                  CheckboxListTile(
                    value: agreedPDPA,
                    onChanged: (val) {
                      setState(() => agreedPDPA = val ?? false);
                    },
                    title: Row(
                      children: [
                        Expanded(
                            child: Text(
                                'Saya bersetuju dengan Dasar Privasi & PDPA.'
                                    .tr(),
                                style: GoogleFonts.inter(fontSize: 12))),
                        IconButton(
                          icon: const Icon(Icons.info_outline_rounded,
                              size: 16, color: AppColors.primary),
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (context) =>
                                        const PrivacyPolicyScreen()));
                          },
                        ),
                      ],
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  CheckboxListTile(
                    value: isKIR,
                    onChanged: (val) {
                      setState(() => isKIR = val ?? false);
                    },
                    title: Text(
                        'Saya mengesahkan bahawa saya adalah Ketua Isi Rumah (KIR) dan ini adalah satu-satunya tuntutan bagi kediaman ini.'
                            .tr(),
                        style: GoogleFonts.inter(fontSize: 12)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                  CheckboxListTile(
                    value: isTruthful,
                    onChanged: (val) {
                      setState(() => isTruthful = val ?? false);
                    },
                    title: Text(
                        'Saya mengesahkan semua maklumat adalah benar. Maklumat palsu boleh didakwa di bawah Akta SPRM 2009.'
                            .tr(),
                        style: GoogleFonts.inter(fontSize: 12)),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading ? null : () => Navigator.pop(ctx),
              child: Text('Batal'.tr()),
            ),
            ElevatedButton(
              onPressed: isUploading
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      if (selectedImage == null) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content:
                                Text('Sila muat naik gambar bukti.'.tr())));
                        return;
                      }
                      if (!agreedPDPA || !isKIR || !isTruthful) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                'Sila tandakan semua kotak pengesahan dan persetujuan.'
                                    .tr())));
                        return;
                      }

                      setState(() => isUploading = true);

                      try {
                        // Duplicate Check for BWI (1 claim per IC)
                        final existingClaims = await FirebaseFirestore.instance
                            .collection('claims')
                            .where('icNumber', isEqualTo: icCtrl.text)
                            .get();
                        if (existingClaims.docs.isNotEmpty) {
                          setState(() => isUploading = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(
                                    'Nombor IC ini telah mendaftar tuntutan. Hanya satu tuntutan dibenarkan per KIR.'
                                        .tr())));
                          }
                          return;
                        }

                        final authState = context.read<AuthBloc>().state;
                        if (authState is AuthAuthenticated) {
                          String imageUrl =
                              await _firestoreService.uploadClaimEvidence(
                                  selectedImage!, authState.uid);

                          final claim = ClaimModel(
                            id: '',
                            citizenId: authState.uid,
                            citizenName: authState.displayName.isNotEmpty
                                ? authState.displayName
                                : 'Awam'.tr(),
                            icNumber: icCtrl.text,
                            householdSize:
                                int.tryParse(householdCtrl.text) ?? 1,
                            damageDescription: damageCtrl.text,
                            type: typeCtrl.text,
                            photoEvidence: imageUrl,
                            location: locationCtrl.text,
                            status: 'submitted',
                            bankName: bankNameCtrl.text,
                            bankAccountNumber: bankAccCtrl.text,
                            isKIR: isKIR,
                            agreedToPdpa: agreedPDPA,
                          );
                          await _firestoreService.submitClaim(claim.toMap());
                          if (mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content:
                                    Text('Tuntutan berjaya dihantar.'.tr())));
                          }
                        }
                      } catch (e) {
                        setState(() => isUploading = false);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content:
                                  Text('errorStr'.tr(args: [e.toString()]))));
                        }
                      }
                    },
              child: isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text('Hantar Tuntutan'.tr()),
            ),
          ],
        );
      }),
    );
  }

  void _showUpdateEvidenceDialog(ClaimModel claim, {bool closeParent = false}) {
    if (closeParent) {
      Navigator.of(context).pop();
    }
    final formKey = GlobalKey<FormState>();
    final damageCtrl = TextEditingController(text: claim.damageDescription);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (sheetCtx) {
        File? selectedImage;
        bool isUploading = false;

        return StatefulBuilder(
          builder: (_, setSheetState) {
            // Build current evidence preview
            Widget evidencePreview;
            if (claim.photoEvidence.startsWith('http')) {
              evidencePreview = Image.network(
                claim.photoEvidence,
                height: 140,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    _evidencePlaceholder('Gagal muat gambar'.tr()),
              );
            } else if (claim.photoEvidence.startsWith('data:image')) {
              try {
                evidencePreview = Image.memory(
                  base64Decode(claim.photoEvidence.split(',').last),
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                );
              } catch (_) {
                evidencePreview = _evidencePlaceholder('Gambar rosak'.tr());
              }
            } else {
              evidencePreview =
                  _evidencePlaceholder('Tiada gambar sedia ada'.tr());
            }

            return Padding(
              // Shift up when keyboard appears
              padding: EdgeInsets.only(
                  bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
              child: Container(
                decoration: const BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  child: Form(
                    key: formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Handle bar
                        Center(
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 12),
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: AppColors.divider,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),

                        // Title
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.edit_note_rounded,
                                  color: Colors.orange, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Text('Kemaskini Tuntutan'.tr(),
                                style: GoogleFonts.poppins(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Officer reason banner
                        if (claim.infoRequestReason != null &&
                            claim.infoRequestReason!.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.35)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(Icons.warning_amber_rounded,
                                        size: 16, color: Colors.orange),
                                    const SizedBox(width: 6),
                                    Text('Permintaan Pegawai:'.tr(),
                                        style: GoogleFonts.inter(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.orange)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(claim.infoRequestReason!,
                                    style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: AppColors.textPrimary,
                                        height: 1.4)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // Damage description field
                        Text('Keterangan Kerosakan'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: damageCtrl,
                          maxLines: 3,
                          enabled: !isUploading,
                          decoration: InputDecoration(
                            hintText:
                                'Terangkan kerosakan dengan lebih terperinci...'
                                    .tr(),
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10)),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(
                                  color: Colors.orange, width: 2),
                            ),
                            filled: true,
                            fillColor: AppColors.surface,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Sila isi keterangan kerosakan'.tr()
                              : null,
                        ),
                        const SizedBox(height: 20),

                        // Photo evidence
                        Text('Bukti Bergambar'.tr(),
                            style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary)),
                        const SizedBox(height: 8),

                        // Preview
                        Container(
                          height: 140,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: selectedImage != null
                                  ? AppColors.safe
                                  : AppColors.divider,
                              width: selectedImage != null ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: selectedImage != null
                              ? Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    Image.file(selectedImage!,
                                        fit: BoxFit.cover),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.safe,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.check_circle,
                                                color: Colors.white, size: 12),
                                            const SizedBox(width: 4),
                                            Text('Gambar Baru'.tr(),
                                                style: GoogleFonts.inter(
                                                    fontSize: 10,
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w600)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                )
                              : evidencePreview,
                        ),
                        const SizedBox(height: 10),

                        // Pick image button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: isUploading
                                ? null
                                : () async {
                                    final picker = ImagePicker();
                                    final XFile? img = await picker.pickImage(
                                      source: ImageSource.gallery,
                                      imageQuality: 75,
                                    );
                                    if (img != null) {
                                      setSheetState(
                                          () => selectedImage = File(img.path));
                                    }
                                  },
                            icon: Icon(
                              selectedImage != null
                                  ? Icons.swap_horiz_rounded
                                  : Icons.add_photo_alternate_rounded,
                              size: 18,
                            ),
                            label: Text(selectedImage != null
                                ? 'Tukar Gambar'.tr()
                                : 'Pilih Gambar Baru'.tr()),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: selectedImage != null
                                  ? AppColors.safe
                                  : AppColors.primary,
                              side: BorderSide(
                                  color: selectedImage != null
                                      ? AppColors.safe
                                      : AppColors.primary),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),

                        // Upload progress
                        if (isUploading) ...[
                          const SizedBox(height: 14),
                          const LinearProgressIndicator(color: Colors.orange),
                          const SizedBox(height: 6),
                          Center(
                            child: Text(
                                'Sedang memuat naik... sila tunggu'.tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary)),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Submit button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: isUploading
                                ? null
                                : () async {
                                    if (!formKey.currentState!.validate())
                                      return;

                                    setSheetState(() => isUploading = true);

                                    // Capture everything before await
                                    final sheetNav = Navigator.of(sheetCtx);
                                    final outerNav = Navigator.of(context);
                                    final outerMsg =
                                        ScaffoldMessenger.of(context);
                                    final authState =
                                        context.read<AuthBloc>().state;

                                    try {
                                      if (authState is AuthAuthenticated) {
                                        String finalUrl = claim.photoEvidence;
                                        if (selectedImage != null) {
                                          finalUrl = await _firestoreService
                                              .uploadClaimEvidence(
                                                  selectedImage!,
                                                  authState.uid);
                                        }

                                        await FirebaseFirestore.instance
                                            .collection('claims')
                                            .doc(claim.id)
                                            .update({
                                          'damageDescription':
                                              damageCtrl.text.trim(),
                                          'photoEvidence': finalUrl,
                                          'status': 'submitted',
                                          'infoRequestReason':
                                              FieldValue.delete(),
                                          'infoDeadline': FieldValue.delete(),
                                          'citizenUpdatedAt':
                                              FieldValue.serverTimestamp(),
                                          'updatedAt':
                                              FieldValue.serverTimestamp(),
                                        });

                                        // Close this sheet
                                        if (sheetCtx.mounted) sheetNav.pop();
                                        // Show success
                                        if (mounted) {
                                          outerMsg.showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  '✅ Tuntutan dikemaskini dan dihantar semula kepada pegawai.'
                                                      .tr()),
                                              backgroundColor: AppColors.safe,
                                              duration: Duration(seconds: 3),
                                            ),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      setSheetState(() => isUploading = false);
                                      if (sheetCtx.mounted) {
                                        ScaffoldMessenger.of(sheetCtx)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text('errorStr'
                                                .tr(args: [e.toString()])),
                                            backgroundColor: AppColors.danger,
                                          ),
                                        );
                                      }
                                    }
                                  },
                            icon: isUploading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2))
                                : const Icon(Icons.send_rounded, size: 18),
                            label: Text(
                                isUploading
                                    ? 'Menghantar...'.tr()
                                    : 'Hantar Kemaskini'.tr(),
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700, fontSize: 15)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) => damageCtrl.dispose());
  }

  Widget _evidencePlaceholder(String msg) {
    return Container(
      height: 140,
      color: Colors.grey[100],
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported_rounded,
                color: Colors.grey[400], size: 36),
            const SizedBox(height: 6),
            Text(msg,
                style:
                    GoogleFonts.inter(fontSize: 12, color: Colors.grey[500])),
          ],
        ),
      ),
    );
  }

  Widget _buildEmergencyAlerts() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Notis Terkini'.tr(),
            actionLabel: 'Lihat Semua'.tr(), onAction: () {
          showModalBottomSheet(
            context: context,
            shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            backgroundColor: AppColors.background,
            builder: (ctx) => Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Senarai Notis Terkini'.tr(),
                      style: GoogleFonts.poppins(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _alertItem(
                      'Jalan Ampang ditutup akibat air naik 1 meter.'.tr(),
                      AppColors.danger,
                      '10 minit lalu'),
                  _alertItem(
                      'Bekalan air di kawasan Gombak akan terputus jam 8 malam.'
                          .tr(),
                      AppColors.warning,
                      '30 minit lalu'),
                  _alertItem('Pusat pemindahan Balairaya Cheras dibuka.'.tr(),
                      AppColors.primary, '1 jam lalu'),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary),
                      child: Text('Tutup'.tr(),
                          style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 16),
        _alertItem('Jalan Ampang ditutup akibat air naik 1 meter.'.tr(),
            AppColors.danger, '10 minit lalu'),
        _alertItem(
            'Bekalan air di kawasan Gombak akan terputus jam 8 malam.'.tr(),
            AppColors.warning,
            '30 minit lalu'),
        _alertItem('Pusat pemindahan Balairaya Cheras dibuka.'.tr(),
            AppColors.primary, '1 jam lalu'),
      ],
    );
  }

  Widget _alertItem(String msg, Color color, String time) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.campaign_rounded, color: color, size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg,
                    style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                Text(time,
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppColors.textHint)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildOfflineToolkit() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Kit Bantuan Offline & FAQ'.tr(),
            actionLabel: 'Lihat Panduan'.tr(), onAction: () {
          Navigator.push(context,
              MaterialPageRoute(builder: (_) => const OfflineGuideScreen()));
        }),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const OfflineGuideScreen())),
                child: _toolkitCard(Icons.medical_services_rounded,
                    'Panduan Kecemasan'.tr(), Colors.red),
              ),
              GestureDetector(
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FAQScreen())),
                child: _toolkitCard(Icons.help_center_rounded,
                    'Pusat Bantuan / FAQ'.tr(), Colors.blue),
              ),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EmergencyBagScreen())),
                child: _toolkitCard(Icons.backpack_rounded, 'Beg Kecemasan'.tr(), Colors.green),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _toolkitCard(IconData icon, String title, Color color) {
    return Container(
      width: 120,
      height: 165,
      margin: const EdgeInsets.only(right: 16),
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.offline_pin_rounded,
                  size: 12, color: AppColors.safe),
              const SizedBox(width: 4),
              Text('Tersedia'.tr(),
                  style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textSecondary)),
            ],
          )
        ],
      ),
    );
  }

  // ─── Dynamic SOS Form Helper Widgets ────────────────────────────────────────

  Widget _buildDropdownField({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.divider),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: DropdownButton<String>(
            isExpanded: true,
            underline: const SizedBox(),
            value: value,
            style:
                GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
            dropdownColor: AppColors.background,
            items: items
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildSwitchField({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary),
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String hint = '',
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.inter(fontSize: 13, color: AppColors.textHint),
            filled: true,
            fillColor: AppColors.background,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.divider),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  void _showClaimDetailsDialog(ClaimModel claim) {
    Widget imageWidget = const SizedBox();
    if (claim.photoEvidence.isNotEmpty) {
      if (claim.photoEvidence.startsWith('data:image')) {
        try {
          final base64String = claim.photoEvidence.split(',').last;
          imageWidget = Image.memory(base64Decode(base64String),
              height: 160, width: double.infinity, fit: BoxFit.cover);
        } catch (_) {
          imageWidget = Container(
              height: 160,
              color: Colors.grey.shade200,
              child: const Center(
                  child: Icon(Icons.broken_image, color: Colors.grey)));
        }
      } else {
        imageWidget = Image.network(claim.photoEvidence,
            height: 160,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
                height: 160,
                color: Colors.grey.shade200,
                child: const Center(
                    child: Icon(Icons.broken_image, color: Colors.grey))));
      }
    }

    // Status display config
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (claim.status) {
      case 'submitted':
        statusColor = AppColors.warning;
        statusLabel = 'Dihantar — Menunggu Semakan'.tr();
        statusIcon = Icons.hourglass_empty_rounded;
        break;
      case 'under_review':
        statusColor = Colors.purple;
        statusLabel = 'Sedang Disemak oleh Pegawai'.tr();
        statusIcon = Icons.manage_search_rounded;
        break;
      case 'approved':
        statusColor = AppColors.safe;
        statusLabel = 'Diluluskan ✅'.tr();
        statusIcon = Icons.verified_rounded;
        break;
      case 'rejected':
        statusColor = AppColors.danger;
        statusLabel = 'Ditolak'.tr();
        statusIcon = Icons.cancel_rounded;
        break;
      case 'expired':
        statusColor = AppColors.textHint;
        statusLabel = 'Tamat Tempoh'.tr();
        statusIcon = Icons.timer_off_rounded;
        break;
      default:
        statusColor = AppColors.textSecondary;
        statusLabel = claim.status.toUpperCase();
        statusIcon = Icons.info_outline_rounded;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollCtrl,
            padding: EdgeInsets.zero,
            children: [
              // Handle bar
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 8),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),

              // Photo evidence banner
              if (claim.photoEvidence.isNotEmpty)
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(0)),
                  child: imageWidget,
                )
              else
                Container(
                  height: 100,
                  color: AppColors.primary.withValues(alpha: 0.07),
                  child: Center(
                    child: Icon(Icons.receipt_long_rounded,
                        size: 48,
                        color: AppColors.primary.withValues(alpha: 0.4)),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: statusColor.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 14, color: statusColor),
                              const SizedBox(width: 6),
                              Text(statusLabel,
                                  style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    Text(claim.type,
                        style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(claim.location,
                        style: GoogleFonts.inter(
                            fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 20),

                    // Progress stepper
                    _buildClaimProgressStepper(claim.status),
                    const SizedBox(height: 24),

                    // ── APPROVED NEXT STEPS PANEL ──
                    if (claim.status == 'approved') ...[
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.safe.withValues(alpha: 0.08),
                              AppColors.safe.withValues(alpha: 0.02)
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: AppColors.safe.withValues(alpha: 0.35)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.safe.withValues(alpha: 0.15),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.celebration_rounded,
                                      size: 20, color: AppColors.safe),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('Tuntutan Anda Diluluskan!'.tr(),
                                      style: GoogleFonts.poppins(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.safe)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            _nextStepItem(
                                Icons.schedule_rounded,
                                AppColors.safe,
                                'Penyaluran Bantuan'.tr(),
                                'Bantuan akan disalurkan dalam 7 hari bekerja dari tarikh kelulusan.'
                                    .tr()),
                            const SizedBox(height: 10),
                            _nextStepItem(
                                Icons.email_rounded,
                                AppColors.primary,
                                'Makluman melalui E-mel'.tr(),
                                'Anda akan menerima e-mel rasmi berkenaan kaedah & jadual penyaluran bantuan. Semak peti masuk anda secara berkala.'
                                    .tr()),
                            const SizedBox(height: 10),
                            _nextStepItem(
                                Icons.phone_in_talk_rounded,
                                AppColors.warning,
                                'Dihubungi Melalui Telefon'.tr(),
                                'Pegawai kami mungkin menghubungi nombor telefon berdaftar anda untuk pengesahan sebelum penyaluran.'
                                    .tr()),
                            const SizedBox(height: 10),
                            _nextStepItem(
                                Icons.location_on_rounded,
                                AppColors.danger,
                                'Sila Kekal di Lokasi Berdaftar'.tr(),
                                'Pastikan anda mudah dihubungi di alamat yang telah didaftarkan semasa permohonan.'
                                    .tr()),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Hotline info
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.support_agent_rounded,
                                size: 20, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Talian Bantuan SIGAP'.tr(),
                                      style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary)),
                                  Text(
                                      '1-800-88-SIGAP (74427)  •  Isnin–Jumaat, 8pg–5ptg'
                                          .tr(),
                                      style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── UNDER REVIEW PANEL ──
                    if (claim.status == 'under_review') ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.purple.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: Colors.purple.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.manage_search_rounded,
                                    size: 20, color: Colors.purple),
                                const SizedBox(width: 10),
                                Text('Tuntutan Sedang Disemak'.tr(),
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.purple)),
                              ],
                            ),
                            if (claim.infoRequestReason != null &&
                                claim.infoRequestReason!.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                      color:
                                          Colors.orange.withValues(alpha: 0.3)),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(Icons.warning_amber_rounded,
                                            size: 16, color: Colors.orange),
                                        const SizedBox(width: 6),
                                        Text(
                                            'Pegawai Meminta Maklumat Tambahan'
                                                .tr(),
                                            style: GoogleFonts.inter(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.orange)),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(claim.infoRequestReason!,
                                        style: GoogleFonts.inter(
                                            fontSize: 13,
                                            color: AppColors.textPrimary)),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => _showUpdateEvidenceDialog(
                                      claim,
                                      closeParent: true),
                                  icon: const Icon(Icons.edit_note_rounded,
                                      color: Colors.white),
                                  label:
                                      Text('Kemaskini Bukti & Maklumat'.tr()),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purple,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                ),
                              ),
                            ] else ...[
                              const SizedBox(height: 8),
                              Text(
                                  'Pegawai sedang menyemak bukti yang anda hantar. Tiada tindakan diperlukan buat masa ini.'
                                      .tr(),
                                  style: GoogleFonts.inter(
                                      fontSize: 13,
                                      color: AppColors.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── REJECTED PANEL ──
                    if (claim.status == 'rejected') ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                              color: AppColors.danger.withValues(alpha: 0.25)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.cancel_rounded,
                                    size: 20, color: AppColors.danger),
                                const SizedBox(width: 10),
                                Text('Sebab Penolakan'.tr(),
                                    style: GoogleFonts.inter(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.danger)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                                claim.rejectReason ??
                                    'Maklumat tidak lengkap atau tidak memenuhi syarat.'
                                        .tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: AppColors.textPrimary)),
                            const SizedBox(height: 12),
                            Text(
                                'Anda boleh memfailkan tuntutan baru dengan maklumat yang lebih lengkap.'
                                    .tr(),
                                style: GoogleFonts.inter(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── CLAIM DETAILS ──
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Maklumat Tuntutan'.tr(),
                              style: GoogleFonts.inter(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary)),
                          const SizedBox(height: 12),
                          _detailRow('No. IC'.tr(), claim.icNumber),
                          _detailRow('Saiz Isi Rumah'.tr(),
                              '${claim.householdSize} orang'),
                          _detailRow('Lokasi / Zon'.tr(), claim.location),
                          _detailRow('Jenis Bantuan'.tr(), claim.type),
                          _detailRow('Keterangan Kerosakan'.tr(),
                              claim.damageDescription),
                          if (claim.createdAt != null)
                            _detailRow('Tarikh Permohonan'.tr(),
                                '${claim.createdAt!.day}/${claim.createdAt!.month}/${claim.createdAt!.year}'),
                          if (claim.reviewedAt != null)
                            _detailRow('Tarikh Semakan'.tr(),
                                '${claim.reviewedAt!.day}/${claim.reviewedAt!.month}/${claim.reviewedAt!.year}'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Close button
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: Text('Tutup'.tr(),
                            style:
                                GoogleFonts.inter(fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Small icon+text row for the approved next-steps panel.
  Widget _nextStepItem(IconData icon, Color color, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(desc,
                  style: GoogleFonts.inter(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  /// 4-step progress stepper for claim flow.
  Widget _buildClaimProgressStepper(String status) {
    final steps = [
      ('Dihantar'.tr(), Icons.upload_rounded),
      ('Disemak'.tr(), Icons.manage_search_rounded),
      ('Diputuskan'.tr(), Icons.gavel_rounded),
    ];
    int currentStep;
    switch (status) {
      case 'submitted':
        currentStep = 0;
        break;
      case 'under_review':
        currentStep = 1;
        break;
      case 'approved':
      case 'rejected':
      case 'expired':
        currentStep = 2;
        break;
      default:
        currentStep = 0;
    }
    final isRejected = status == 'rejected';
    final stepColor = isRejected ? AppColors.danger : AppColors.safe;

    return Row(
      children: List.generate(steps.length, (i) {
        final isActive = i == currentStep;
        final isDone = i < currentStep;
        final color = (isActive || isDone)
            ? (i == currentStep && isRejected
                ? AppColors.danger
                : AppColors.safe)
            : AppColors.divider;
        return Expanded(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color:
                            (isActive || isDone) ? color : Colors.transparent,
                        border: Border.all(color: color, width: 2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isDone ? Icons.check_rounded : steps[i].$2,
                        size: 14,
                        color: (isActive || isDone) ? Colors.white : color,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(steps[i].$1,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight:
                              isActive ? FontWeight.w700 : FontWeight.w500,
                          color:
                              (isActive || isDone) ? color : AppColors.textHint,
                        ),
                        textAlign: TextAlign.center),
                  ],
                ),
              ),
              if (i < steps.length - 1)
                Expanded(
                  child: Container(
                    height: 2,
                    margin: const EdgeInsets.only(bottom: 20),
                    color: i < currentStep ? stepColor : AppColors.divider,
                  ),
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600)),
          Text(value,
              style: GoogleFonts.inter(
                  fontSize: 14, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
