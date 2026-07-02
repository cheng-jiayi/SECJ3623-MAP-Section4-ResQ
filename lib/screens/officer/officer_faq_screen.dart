import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';
import 'package:easy_localization/easy_localization.dart';

class OfficerFAQScreen extends StatelessWidget {
  const OfficerFAQScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(
          'FAQ Pegawai Operasi'.tr(),
          style: GoogleFonts.poppins(color: AppColors.textPrimary, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildCategory(
            title: 'Pengurusan Zon Darurat'.tr(),
            items: [
              _buildFaqItem(
                'Bagaimanakah cara mengisytiharkan zon darurat baru?'.tr(),
                'Pergi ke tab Peta, klik ikon tambah (+) di bahagian bawah skrin, lukis sempadan geofencing kawasan bencana, dan tetapkan tahap bahaya.'.tr(),
              ),
              _buildFaqItem(
                'Bagaimanakah cara menutup zon bencana?'.tr(),
                'Pilih zon bencana aktif pada peta atau senarai zon, klik butang "Tutup Zon", dan sahkan penutupan. Laporan penutupan akan dijana oleh AWANIS secara automatik.'.tr(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategory(
            title: 'Kelulusan Tuntutan Bantuan'.tr(),
            items: [
              _buildFaqItem(
                'Apakah kriteria utama untuk meluluskan tuntutan bantuan?'.tr(),
                'Pastikan dokumen lengkap: salinan IC, bukti kerosakan (gambar), dan pastikan lokasi pemohon berada dalam zon bencana yang sah.'.tr(),
              ),
              _buildFaqItem(
                'Bolehkah kelulusan tuntutan dibuat secara pukal?'.tr(),
                'Ya, untuk kawasan yang diisytiharkan bencana merah, anda boleh memilih berbilang tuntutan dari zon tersebut dan klik "Luluskan Pukal".'.tr(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategory(
            title: 'Penyelarasan Sukarelawan'.tr(),
            items: [
              _buildFaqItem(
                'Bagaimanakah cara mobilisasi sukarelawan kecemasan?'.tr(),
                'Di tab Kawalan, pilih "Mobilisasi Sukarelawan", tentukan keperluan kemahiran (cth: Rescue, Medic), dan hantar notifikasi amaran mobilisasi.'.tr(),
              ),
              _buildFaqItem(
                'Apakah tindakan jika tiada sukarelawan menerima tugasan SOS?'.tr(),
                'Sekiranya tiada maklum balas dalam 5 minit, hubungi talian sokongan NADMA (03-8064 2400) atau Bomba (994) untuk bantuan aset fizikal.'.tr(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildCategory(
            title: 'Analitik & Laporan'.tr(),
            items: [
              _buildFaqItem(
                'Bagaimanakah cara memuat turun laporan PDF bencana?'.tr(),
                'Masuk ke tab AWANIS, klik butang "Jana Laporan". Selepas laporan dirumus oleh AI, tekan "Muat Turun" untuk menyimpan fail PDF.'.tr(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCategory({required String title, required List<Widget> items}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
        ),
        const SizedBox(height: 8),
        ...items,
      ],
    );
  }

  Widget _buildFaqItem(String question, String answer) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: ExpansionTile(
        title: Text(
          question,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              answer,
              style: GoogleFonts.inter(fontSize: 12, color: AppColors.textSecondary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
