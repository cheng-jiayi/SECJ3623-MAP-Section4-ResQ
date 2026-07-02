import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/auth/auth_bloc.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_strings.dart';
import '../../services/firestore_service.dart';
import '../../widgets/common/sigap_button.dart';
import 'package:easy_localization/easy_localization.dart';

class RoleOnboardingScreen extends StatefulWidget {
  const RoleOnboardingScreen({super.key});

  @override
  State<RoleOnboardingScreen> createState() => _RoleOnboardingScreenState();
}

class _RoleOnboardingScreenState extends State<RoleOnboardingScreen> {
  bool _isLoading = false;

  Future<void> _completeOnboarding(
      BuildContext context, String uid, String role) async {
    setState(() => _isLoading = true);
    try {
      final firestore = FirestoreService();
      switch (role) {
        case 'volunteer':
          await firestore.createVolunteerProfile(uid, {
            'skills': <String>[],
            'availabilityStart': '08:00',
            'availabilityEnd': '18:00',
            'isActive': false,
            'sigapMataPoints': 1250,
            'certifications': <String>[],
          }).timeout(const Duration(seconds: 30));
          break;
        case 'officer':
          await firestore.createOfficerProfile(uid, {
            'agencyName': '',
            'designation': '',
            'badgeNumber': '',
            'district': '',
          }).timeout(const Duration(seconds: 30));
          break;
        default:
          await firestore.createCitizenProfile(uid, {
            'icNumber': '',
            'phoneNumber': '',
            'address': '',
            'householdSize': 1,
            'emergencyContacts': <Map>[],
          }).timeout(const Duration(seconds: 30));
          break;
      }
      if (context.mounted) {
        context.read<AuthBloc>().add(const AuthProfileCompleted());
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(e.toString()), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: (context, state) {
        String uid = '';
        String role = 'citizen';
        String displayName = '';

        if (state is AuthRegistrationSuccess) {
          uid = state.uid;
          role = state.role;
          displayName = state.displayName;
        } else if (state is AuthAuthenticated) {
          uid = state.uid;
          role = state.role;
          displayName = state.displayName;
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 40),
                  _buildWelcomeHeader(displayName),
                  const SizedBox(height: 40),
                  _buildRoleCard(role),
                  const SizedBox(height: 40),
                  SigapButton(
                    label: AppStrings.continueButton,
                    isLoading: _isLoading,
                    onPressed: _isLoading
                        ? null
                        : () => _completeOnboarding(context, uid, role),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWelcomeHeader(String displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child:
                const Icon(Icons.bolt_rounded, color: Colors.white, size: 44),
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Selamat Datang ke SIGAP!'.tr(),
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
        ),
        if (displayName.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: Text(
              displayName,
              style: GoogleFonts.inter(
                  fontSize: 15, color: AppColors.textSecondary),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildRoleCard(String role) {
    final roleData = _getRoleData(role);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: (roleData['color'] as Color).withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: (roleData['color'] as Color).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: (roleData['color'] as Color).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(roleData['icon'] as IconData,
                color: roleData['color'] as Color, size: 32),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: (roleData['color'] as Color).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Text(
              roleData['role'] as String,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: roleData['color'] as Color,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            roleData['title'] as String,
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            roleData['desc'] as String,
            style: GoogleFonts.inter(
                fontSize: 14, color: AppColors.textSecondary, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          _buildFeaturesList(
              roleData['features'] as List<String>, roleData['color'] as Color),
        ],
      ),
    );
  }

  Widget _buildFeaturesList(List<String> features, Color color) {
    return Column(
      children: features.map((f) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, color: color, size: 12),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  f,
                  style: GoogleFonts.inter(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Map<String, dynamic> _getRoleData(String role) {
    switch (role) {
      case 'volunteer':
        return {
          'role': AppStrings.volunteerRole,
          'title': 'Sukarelawan SIGAP'.tr(),
          'desc': AppStrings.volunteerDesc,
          'icon': Icons.handshake_rounded,
          'color': AppColors.volunteerAccent,
          'features': [
            'Terima misi bantuan bencana'.tr(),
            'Kumpul mata SIGAP untuk sijil'.tr(),
            'Toggle status aktif / tidak aktif'.tr(),
            'Log tugas lapangan'.tr(),
          ],
        };
      case 'officer':
        return {
          'role': AppStrings.officerRole,
          'title': 'Pegawai Kerajaan'.tr(),
          'desc': AppStrings.officerDesc,
          'icon': Icons.shield_rounded,
          'color': AppColors.officerAccent,
          'features': [
            'Pantau kluster SOS secara langsung'.tr(),
            'Urus sumber dan inventori'.tr(),
            'Lulus tuntutan bantuan'.tr(),
            'Selaraskan tindak balas bencana'.tr(),
          ],
        };
      default:
        return {
          'role': AppStrings.citizenRole,
          'title': 'Warga SIGAP'.tr(),
          'desc': AppStrings.citizenDesc,
          'icon': Icons.home_rounded,
          'color': AppColors.citizenAccent,
          'features': [
            'Hantar SOS satu ketikan'.tr(),
            'Tandakan status keselamatan'.tr(),
            'Mohon bantuan dan tuntutan'.tr(),
            'Akses panduan kecemasan offline'.tr(),
          ],
        };
    }
  }
}
