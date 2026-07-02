import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants/app_colors.dart';
import '../../widgets/common/sigap_button.dart';
import '../../services/certificate_service.dart';
import 'package:printing/printing.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/auth/auth_bloc.dart';

class CertificateRedemptionSuccessScreen extends StatelessWidget {
  final String certTitle;
  final String volunteerName;

  const CertificateRedemptionSuccessScreen({
    super.key, 
    required this.certTitle,
    required this.volunteerName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              
              // Success Icon
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppColors.safe.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_rounded,
                  color: AppColors.safe,
                  size: 100,
                ),
              ),
              const SizedBox(height: 32),
              
              // Title
              Text(
                'Tahniah!'.tr(),
                style: GoogleFonts.poppins(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Description
              Text(
                'Anda berjaya menebus sijil:'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              
              // Certificate Name Highlight
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  certTitle,
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              
              const SizedBox(height: 24),
              
              Text(
                'Sijil ini kini tersedia untuk dimuat turun di bahagian Profil anda.'.tr(),
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              
              const Spacer(),
              
              // Actions
              SigapButton(
                label: 'Muat Turun PDF'.tr(),
                onPressed: () async {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Row(
                        children: [
                          const Icon(Icons.download_done_rounded, color: Colors.white),
                          const SizedBox(width: 12),
                          Expanded(child: Text('Menjana PDF sijil...'.tr())),
                        ],
                      ),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                    ),
                  );

                  try {
                    final pdfBytes = await CertificateService.generateCertificatePDF(
                      volunteerName: volunteerName,
                      certificateTitle: certTitle,
                      date: DateTime.now(),
                    );
                    await Printing.layoutPdf(
                      onLayout: (format) async => pdfBytes,
                      name: 'Sijil_$certTitle.pdf',
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Gagal menjana sijil: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.download_rounded),
              ),
              const SizedBox(height: 16),
              SigapButton(
                label: 'Kembali'.tr(),
                variant: SigapButtonVariant.outlined,
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
