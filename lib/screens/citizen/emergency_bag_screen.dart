import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../core/constants/app_colors.dart';

class EmergencyBagScreen extends StatelessWidget {
  const EmergencyBagScreen({super.key});

  static const List<Map<String, dynamic>> _items = [
    {
      'icon': Icons.badge_rounded,
      'color': Color(0xFF2563EB),
      'name': 'Dokumen Penting',
      'nameEn': 'Important Documents',
      'desc': 'IC, pasport, sijil lahir, buku kesihatan, polis insurans',
      'descEn': 'IC, passport, birth certificate, health booklet, insurance policy',
    },
    {
      'icon': Icons.water_drop_rounded,
      'color': Color(0xFF0891B2),
      'name': 'Air Minuman',
      'nameEn': 'Drinking Water',
      'desc': 'Sekurang-kurangnya 3 liter per orang untuk 3 hari',
      'descEn': 'At least 3 litres per person for 3 days',
    },
    {
      'icon': Icons.restaurant_rounded,
      'color': Color(0xFFD97706),
      'name': 'Makanan Kering',
      'nameEn': 'Dry Food',
      'desc': 'Biskut, makanan tin, mi segera untuk 3 hari',
      'descEn': 'Biscuits, canned food, instant noodles for 3 days',
    },
    {
      'icon': Icons.medical_services_rounded,
      'color': Color(0xFFDC2626),
      'name': 'Kit Pertolongan Cemas',
      'nameEn': 'First Aid Kit',
      'desc': 'Plaster, ubat demam, antiseptik, perban, gunting',
      'descEn': 'Plasters, fever medicine, antiseptic, bandage, scissors',
    },
    {
      'icon': Icons.medication_rounded,
      'color': Color(0xFF7C3AED),
      'name': 'Ubat Peribadi',
      'nameEn': 'Personal Medication',
      'desc': 'Stok ubat kronik mencukupi sekurang-kurangnya untuk seminggu',
      'descEn': 'Sufficient chronic medication supply for at least one week',
    },
    {
      'icon': Icons.flashlight_on_rounded,
      'color': Color(0xFFD97706),
      'name': 'Lampu Suluh / Lilin',
      'nameEn': 'Flashlight / Candles',
      'desc': 'Lampu suluh dengan bateri ganti atau lampu picit',
      'descEn': 'Flashlight with spare batteries or squeeze light',
    },
    {
      'icon': Icons.phone_android_rounded,
      'color': Color(0xFF059669),
      'name': 'Power Bank & Kabel',
      'nameEn': 'Power Bank & Cable',
      'desc': 'Power bank bersisah penuh dan kabel cas telefon',
      'descEn': 'Fully charged power bank and phone charging cable',
    },
    {
      'icon': Icons.radio_rounded,
      'color': Color(0xFF1D4ED8),
      'name': 'Radio Bateri',
      'nameEn': 'Battery Radio',
      'desc': 'Untuk menerima berita kecemasan tanpa internet',
      'descEn': 'To receive emergency news without internet',
    },
    {
      'icon': Icons.cleaning_services_rounded,
      'color': Color(0xFF0891B2),
      'name': 'Peralatan Kebersihan',
      'nameEn': 'Hygiene Supplies',
      'desc': 'Sabun, tuala, tisu basah, pek sanitari, ubat gigi',
      'descEn': 'Soap, towel, wet wipes, sanitary pads, toothpaste',
    },
    {
      'icon': Icons.checkroom_rounded,
      'color': Color(0xFF7C3AED),
      'name': 'Pakaian Ganti',
      'nameEn': 'Change of Clothes',
      'desc': 'Sekurang-kurangnya 2 set pakaian lengkap per orang',
      'descEn': 'At least 2 complete sets of clothing per person',
    },
    {
      'icon': Icons.attach_money_rounded,
      'color': Color(0xFF16A34A),
      'name': 'Wang Tunai',
      'nameEn': 'Cash',
      'desc': 'Wang tunai secukupnya kerana ATM mungkin tidak berfungsi',
      'descEn': 'Sufficient cash as ATMs may not be operational',
    },
    {
      'icon': Icons.child_care_rounded,
      'color': Color(0xFFEA580C),
      'name': 'Keperluan Kanak-kanak',
      'nameEn': 'Child Essentials',
      'desc': 'Lampin pakai buang, susu formula, makanan bayi',
      'descEn': 'Disposable diapers, formula milk, baby food',
    },
    {
      'icon': Icons.elderly_rounded,
      'color': Color(0xFF2563EB),
      'name': 'Keperluan Warga Emas',
      'nameEn': 'Elderly Essentials',
      'desc': 'Tongkat, ubat kronik, cermin mata, alat bantu dengar',
      'descEn': 'Walking stick, chronic medicine, spectacles, hearing aid',
    },
    {
      'icon': Icons.map_rounded,
      'color': Color(0xFF0F766E),
      'name': 'Peta Kawasan Tempatan',
      'nameEn': 'Local Area Map',
      'desc': 'Peta fizikal kawasan dan lokasi pusat pemindahan berdekatan',
      'descEn': 'Physical map of the area and nearby evacuation centre locations',
    },
    {
      'icon': Icons.security_rounded,
      'color': Color(0xFFDC2626),
      'name': 'Wisel Kecemasan',
      'nameEn': 'Emergency Whistle',
      'desc': 'Wisel untuk memberi isyarat lokasi anda jika terperangkap',
      'descEn': 'Whistle to signal your location if trapped',
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: const Color(0xFF16A34A),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'Beg Kecemasan'.tr(),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 18),
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF16A34A), Color(0xFF22C55E)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF16A34A).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  )
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
                    child: const Icon(Icons.backpack_rounded, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sediakan Beg Kecemasan Anda'.tr(),
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Sediakan beg ini sebelum bencana berlaku. Simpan di tempat yang mudah dicapai.'.tr(),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.offline_pin_rounded, size: 14, color: AppColors.safe),
                  const SizedBox(width: 6),
                  Text(
                    'Maklumat ini tersedia walaupun tanpa internet.'.tr(),
                    style: GoogleFonts.inter(fontSize: 12, color: AppColors.safe, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = _items[index];
                final Color color = item['color'] as Color;
                return Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(item['icon'] as IconData, color: color, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item['name'] as String,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              item['desc'] as String,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${index + 1}',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              childCount: _items.length,
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tips_and_updates_rounded, color: AppColors.warning, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tips Penyimpanan'.tr(),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _tipItem('Guna beg yang kalis air / beg sandang yang besar.'.tr()),
                  _tipItem('Simpan di tempat yang mudah dicapai dalam masa kurang 2 minit.'.tr()),
                  _tipItem('Semak & gantikan item yang tamat tempoh setiap 6 bulan.'.tr()),
                  _tipItem('Beritahu semua ahli keluarga tentang lokasi beg kecemasan.'.tr()),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _tipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 5),
            width: 5,
            height: 5,
            decoration: const BoxDecoration(
              color: AppColors.warning,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
