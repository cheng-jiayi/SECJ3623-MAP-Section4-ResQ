import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/constants/app_keys.dart';

class AwanisService {
  static const String _systemPrompt =
      '''You are AWANIS (Automated Welfare & Alert Navigation Intelligence System), an AI assistant embedded in the SIGAP disaster response app used in Malaysia. 

You assist three types of users:
1. Citizens affected by disasters (floods, landslides, fires, medical emergencies)
2. Volunteers responding to SOS reports and missions
3. Officers monitoring and coordinating disaster operations

Always respond in the same language as the user's message (Malay or English). Keep responses concise, helpful, and practical. Focus ONLY on disaster management, emergency response, safety advice, relief claims, SOS procedures, evacuation guidance, and SIGAP app usage.

If asked about unrelated topics (entertainment, politics, general knowledge, etc.), politely explain that you are only able to assist with emergency and disaster-related matters, and redirect the user to the relevant SIGAP features.

Key Malaysia emergency numbers:
- MERS 999: Police, Fire, Ambulance
- NADMA: 03-8064 2400
- Flood info: 1-800-88-2727

Available SIGAP app features:
- SOS button: bottom center of screen (red button)
- Claims tab: submit flood/disaster relief claims
- Map tab: view nearby disaster zones and relief centres
- AWANIS tab: this AI chat
- Safety Status: update your evacuation status in your profile header''';

  late final GenerativeModel _model;
  final List<Content> _citizenHistory = [];

  AwanisService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: AppKeys.geminiApiKey,
      systemInstruction: Content.system(_systemPrompt),
      generationConfig: GenerationConfig(
        temperature: 0.7,
        maxOutputTokens: 512,
      ),
    );
  }

  // ── Public API ──────────────────────────────────────────────────────────

  /// Citizen chat — maintains conversation history for context.
  Future<String> chatWithCitizen(String message) async {
    // 1. Check exact quick-chip answers first (always works offline)
    final quickAnswer = getQuickChipResponse(message);
    if (quickAnswer != null) return quickAnswer;

    // 2. Guard off-topic before hitting the API
    final offTopicGuard = _checkOffTopic(message);
    if (offTopicGuard != null) return offTopicGuard;

    try {
      _citizenHistory.add(Content.text(message));
      final response = await _model.generateContent(_citizenHistory);
      final reply = response.text ??
          'Maaf, saya tidak dapat memproses permintaan anda. Sila cuba lagi.';
      _citizenHistory.add(Content.model([TextPart(reply)]));
      return reply;
    } catch (e) {
      if (_citizenHistory.isNotEmpty) _citizenHistory.removeLast();
      return _fallbackCitizenResponse(message);
    }
  }

  // ── Quick-Chip Exact Lookup ─────────────────────────────────────────────

  /// Returns a guaranteed hardcoded answer for every known quick-chip query,
  /// or null if the message is not a known quick chip (allow normal processing).
  /// Call this BEFORE the AI and BEFORE keyword matching.
  String? getQuickChipResponse(String message) {
    // Normalise: trim + collapse whitespace + lowercase for matching
    final norm = message.trim().replaceAll(RegExp(r'\s+'), ' ');
    final lower = norm.toLowerCase();

    // ── CITIZEN QUICK CHIPS ─────────────────────────────────────────────

    // Chip 1: "Hantar SOS" → "Macam mana nak hantar SOS?"
    if (_exactMatch(lower, [
      'macam mana nak hantar sos?',
      'how to send sos?',
      'how do i send sos?',
      'cara hantar sos',
    ])) {
      return '🚨 CARA MENGHANTAR SOS DI SIGAP\n\n'
          '1️⃣  Tekan butang merah SOS di bahagian tengah menu bawah skrin.\n'
          '2️⃣  Pilih jenis insiden:\n'
          '    • 🌊 Banjir\n'
          '    • 🔥 Kebakaran\n'
          '    • 🏥 Perubatan\n'
          '    • 🔍 Orang Hilang\n'
          '3️⃣  Lokasi GPS anda akan dikesan secara automatik.\n'
          '4️⃣  Tambah butiran tambahan jika perlu.\n'
          '5️⃣  Tekan "Hantar" — laporan terus dihantar ke agensi berkaitan.\n\n'
          '✅ Selepas dihantar, sukarelawan berdekatan akan dimaklumkan.\n\n'
          '📞 Untuk kecemasan segera: MERS 999';
    }

    // Chip 2: "Keluarga saya" → "Bagaimana nak kesan keselamatan keluarga saya?"
    if (_exactMatch(lower, [
      'bagaimana nak kesan keselamatan keluarga saya?',
      'how to track my family safety?',
      'track family safety',
      'keselamatan keluarga',
    ])) {
      return '👨\u200d👩\u200d👧\u200d👦 CARA SEMAK KESELAMATAN KELUARGA\n\n'
          'LANGKAH UNTUK ANDA:\n'
          '1️⃣  Pergi ke profil anda (ikon pengguna di penjuru kanan atas).\n'
          '2️⃣  Tekan "Status Keselamatan".\n'
          '3️⃣  Pilih status semasa anda:\n'
          '    • 🟢 Selamat — anda dalam keadaan baik\n'
          '    • 🟡 Dipindahkan — berada di PPS / tempat selamat\n'
          '    • 🔴 Perlukan Bantuan — dalam bahaya, perlu pertolongan\n\n'
          'UNTUK KELUARGA ANDA:\n'
          '• Pastikan setiap ahli keluarga memasang aplikasi SIGAP.\n'
          '• Mereka perlu mengemas kini status masing-masing.\n'
          '• Anda boleh lihat status ahli keluarga yang berdaftar dalam profil anda.\n\n'
          '💡 Tip: Kemas kini status anda setiap 2-3 jam semasa bencana berlaku.';
    }

    // Chip 3: "Pusat pemindahan" → "Di mana pusat pemindahan (PPS) terdekat?"
    if (_exactMatch(lower, [
      'di mana pusat pemindahan (pps) terdekat?',
      'di mana pusat pemindahan terdekat?',
      'where is the nearest evacuation centre?',
      'nearest evacuation center',
      'pusat pemindahan terdekat',
      'pps terdekat',
    ])) {
      return '📍 PUSAT PEMINDAHAN (PPS) TERDEKAT\n\n'
          'CARA CARI MELALUI SIGAP:\n'
          '1️⃣  Tekan tab Peta (🗺️) di menu bawah.\n'
          '2️⃣  PPS aktif berdekatan akan dipaparkan pada peta.\n'
          '3️⃣  Tekan ikon PPS untuk lihat kapasiti & arah perjalanan.\n\n'
          'PPS BIASANYA TERLETAK DI:\n'
          '🏫 Sekolah Kebangsaan / Menengah\n'
          '🏟️ Dewan olahraga & balai raya\n'
          '🕌 Masjid & surau berdaftar\n'
          '🏢 Bangunan kerajaan tempatan (MBPJ, DBKL dll)\n\n'
          'BARANGAN YANG PERLU DIBAWA:\n'
          '📄 IC / MyKad\n'
          '💊 Ubat-ubatan peribadi\n'
          '👕 Pakaian 3 hari\n'
          '🔌 Pengecas telefon & power bank\n\n'
          '📞 Maklumat PPS: NADMA 03-8064 2400\n'
          '📞 Hotline Banjir: 1-800-88-2727';
    }

    // Chip 4: "Status cuaca" → "Boleh berikan amaran cuaca terkini?"
    if (_exactMatch(lower, [
      'boleh berikan amaran cuaca terkini?',
      'boleh bagi amaran cuaca?',
      'what is the current weather warning?',
      'weather warning',
      'amaran cuaca terkini',
      'status cuaca',
    ])) {
      return '🌧️ AMARAN CUACA & BENCANA\n\n'
          'CARA SEMAK DALAM SIGAP:\n'
          '• Tab Peta (🗺️) akan tunjukkan amaran banjir aktif berdekatan anda secara automatik.\n'
          '• Pop-up Amaran Banjir akan muncul jika kawasan anda berisiko.\n\n'
          'PARAS AMARAN RASMI:\n'
          '🟡 AWAS — Bersedia untuk pindah, pantau keadaan\n'
          '🟠 BERJAGA-JAGA — Mula berpindah jika diarahkan\n'
          '🔴 BAHAYA — Pindah SEGERA, hubungi 999\n\n'
          'SUMBER CUACA TERKINI:\n'
          '🌐 Jabatan Met Malaysia: met.gov.my\n'
          '📱 App MyWeather (JMM)\n'
          '📺 RTM1 & Bernama TV (siaran kecemasan)\n\n'
          '📞 Info Banjir: 1-800-88-2727\n'
          '📞 NADMA: 03-8064 2400\n\n'
          '⚠️ Jangan tunggu air naik — pindah lebih awal lebih selamat!';
    }

    // ── OFFICER QUICK CHIPS ─────────────────────────────────────────────

    // Officer Chip 1: "Statistik SOS" → "Berapa banyak SOS yang belum diselesaikan hari ini?"
    if (_exactMatch(lower, [
      'berapa banyak sos yang belum diselesaikan hari ini?',
      'berapa sos aktif?',
      'how many active sos today?',
      'sos statistics',
    ])) {
      return null; // Let the officer handler resolve with live Firestore data
    }

    // Officer Chip 2: "Jumlah Mangsa" → "Berapa jumlah mangsa di kawasan Gombak?"
    if (_exactMatch(lower, [
      'berapa jumlah mangsa di kawasan gombak?',
      'how many victims in gombak?',
      'jumlah mangsa gombak',
    ])) {
      return '📊 LAPORAN MANGSA — KAWASAN GOMBAK\n\n'
          'Maklumat bilangan mangsa mengikut kawasan boleh dilihat melalui:\n\n'
          '1️⃣  Tab Peta → klik zon bencana untuk lihat kluster SOS\n'
          '2️⃣  Tab SOS → tapis mengikut lokasi "Gombak"\n\n'
          'AGENSI TEMPATAN GOMBAK:\n'
          '• MPKj (Majlis Perbandaran Kajang): 03-8737 8000\n'
          '• Balai Bomba Gombak: 03-6189 9444\n'
          '• Pejabat Daerah Gombak: 03-6189 1000\n\n'
          '💡 Tip: Gunakan tab Peta untuk visualisasi kluster SOS realtime di kawasan Gombak & sekitarnya.\n\n'
          '📞 NADMA: 03-8064 2400';
    }

    // Officer Chip 3: "Status Skuad" → "Berapa ramai sukarelawan aktif sekarang?"
    if (_exactMatch(lower, [
      'berapa ramai sukarelawan aktif sekarang?',
      'how many active volunteers now?',
      'volunteer status',
      'status skuad',
    ])) {
      return null; // Let the officer handler resolve with live Firestore data
    }

    // Officer Chip 4: "Tuntutan BWI" → "Berapa jumlah dana tuntutan yang telah diluluskan?"
    if (_exactMatch(lower, [
      'berapa jumlah dana tuntutan yang telah diluluskan?',
      'how much claims approved?',
      'tuntutan diluluskan',
      'tuntutan bwi',
    ])) {
      return '💰 LAPORAN TUNTUTAN BANTUAN BENCANA\n\n'
          'Untuk data tuntutan terkini, semak tab "Tuntutan" dalam dashboard pegawai.\n\n'
          'KATEGORI TUNTUTAN:\n'
          '📋 Tertunda — menunggu semakan pegawai\n'
          '✅ Diluluskan — bayaran sedang diproses\n'
          '❌ Ditolak — maklumat tidak lengkap / tidak layak\n\n'
          'SOP KELULUSAN TUNTUTAN:\n'
          '1️⃣  Semak kelengkapan dokumen (IC, gambar kerosakan, bukti alamat)\n'
          '2️⃣  Sahkan pemohon berada dalam zon bencana berdaftar\n'
          '3️⃣  Luluskan tuntutan yang memenuhi kriteria\n'
          '4️⃣  Bayaran diproses dalam 3-5 hari bekerja\n\n'
          '⏱️ Sasaran: Selesaikan semakan dalam 48 jam dari tarikh hantar.\n'
          '📞 Bantuan Teknikal: NADMA 03-8064 2400';
    }

    return null; // Not a known quick chip — proceed to normal handling
  }

  /// Clear chat history (call when starting a new session).
  void clearHistory() => _citizenHistory.clear();

  /// Volunteer mission briefing using AI.
  Future<String> generateVolunteerBriefing(
      String sosType, String location, int victimCount) async {
    try {
      final prompt =
          '''Generate a concise pre-mission briefing in Malay for a SIGAP volunteer.
Mission details:
- Incident type: $sosType
- Location: $location
- Estimated victims: $victimCount

Include: safety precautions, recommended equipment, coordination tips, and a motivational closing. Keep it under 200 words.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ??
          _fallbackVolunteerBriefing(sosType, location, victimCount);
    } catch (e) {
      return _fallbackVolunteerBriefing(sosType, location, victimCount);
    }
  }

  /// General volunteer briefing (no specific mission).
  Future<String> getVolunteerBriefing() async {
    try {
      int activeSosCount = 0;
      try {
        final snap = await FirebaseFirestore.instance
            .collection('sos_reports')
            .where('status', whereIn: ['active', 'responded']).get();
        activeSosCount = snap.docs.length;
      } catch (_) {}

      final prompt =
          '''Generate a brief pre-mission status update in Malay for SIGAP volunteers.
Current system status: $activeSosCount active/responded SOS reports.
Include: readiness reminder, safety tips, team coordination reminder. Keep under 150 words.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? _fallbackGeneralBriefing(activeSosCount);
    } catch (e) {
      return _fallbackGeneralBriefing(0);
    }
  }

  /// Volunteer interactive chat (Grab-style accept/decline screen).
  Future<String> chatWithVolunteer(String message, {int activeSos = 0}) async {
    final offTopicGuard = _checkOffTopic(message);
    if (offTopicGuard != null) return offTopicGuard;

    try {
      final prompt =
          '''You are AWANIS assisting a SIGAP volunteer. There are currently $activeSos active SOS reports.
Volunteer's message: $message
Respond concisely in the same language as the message. Focus on mission briefing, safety tips, equipment guidance, or SIGAP app usage.''';
      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? _fallbackVolunteerChat(message, activeSos);
    } catch (e) {
      return _fallbackVolunteerChat(message, activeSos);
    }
  }

  /// Officer analytics query using AI with real Firestore data as context.
  Future<String> queryOfficerAnalytics(
      String question, Map<String, dynamic> firestoreData) async {
    // 1. Check quick-chip exact answers first (data-injected where needed)
    final quickAnswer = _getOfficerQuickChipWithData(question, firestoreData);
    if (quickAnswer != null) return quickAnswer;

    // 2. Guard off-topic
    final offTopicGuard = _checkOffTopic(question);
    if (offTopicGuard != null) return offTopicGuard;

    try {
      final prompt =
          '''You are the SIGAP Operations AI for a duty officer.
Current live data:
- Active SOS reports: ${firestoreData['jumlah_sos_aktif'] ?? 0}
- Active volunteers: ${firestoreData['jumlah_sukarelawan_aktif'] ?? 0}
- Pending claims: ${firestoreData['jumlah_tuntutan'] ?? 0}
- Active disaster zones: ${firestoreData['jumlah_zon_bencana'] ?? 0}

Officer's question: $question

Provide a concise, data-driven operational answer in the same language as the question. Be specific with the numbers provided.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? _fallbackOfficerResponse(question, firestoreData);
    } catch (e) {
      return _fallbackOfficerResponse(question, firestoreData);
    }
  }

  /// Handles officer quick chips that require live Firestore data injected.
  String? _getOfficerQuickChipWithData(
      String question, Map<String, dynamic> data) {
    final lower = question.trim().toLowerCase();
    final sosCount = data['jumlah_sos_aktif'] ?? 0;
    final volCount = data['jumlah_sukarelawan_aktif'] ?? 0;

    // Officer Chip 1: SOS statistics
    if (_exactMatch(lower, [
      'berapa banyak sos yang belum diselesaikan hari ini?',
      'berapa sos aktif?',
      'how many active sos today?',
    ])) {
      final urgency = sosCount == 0
          ? '✅ Tiada SOS aktif buat masa ini. Sistem tenang.'
          : sosCount <= 5
              ? '🟡 Situasi terkawal. Pantau perkembangan.'
              : sosCount <= 15
                  ? '🟠 Situasi sibuk. Pertimbangkan mobilisasi sukarelawan tambahan.'
                  : '🔴 KRITIKAL: Bilangan SOS tinggi! Aktifkan protokol darurat.';
      return '📊 STATISTIK SOS SEMASA\n\n'
          '🚨 SOS Belum Diselesaikan: $sosCount laporan\n'
          '👷 Sukarelawan Bertugas: $volCount orang\n'
          '📈 Nisbah Beban: ${volCount > 0 ? (sosCount / volCount).toStringAsFixed(1) : "∞"} SOS/sukarelawan\n\n'
          '$urgency\n\n'
          'TINDAKAN DISYORKAN:\n'
          '1️⃣  Semak tab Peta untuk visualisasi kluster SOS\n'
          '2️⃣  Agihkan sukarelawan mengikut kepekatan insiden\n'
          '3️⃣  Utamakan SOS kategori Perubatan & Kebakaran\n\n'
          '📞 Bantuan tambahan: NADMA 03-8064 2400';
    }

    // Officer Chip 3: Volunteer status
    if (_exactMatch(lower, [
      'berapa ramai sukarelawan aktif sekarang?',
      'how many active volunteers now?',
    ])) {
      final volStatus = volCount == 0
          ? '🔴 KRITIKAL: Tiada sukarelawan aktif! Hubungi NADMA segera.'
          : volCount < 5
              ? '🟡 Bilangan rendah. Pertimbangkan mobilisasi tambahan.'
              : '🟢 Kapasiti mencukupi untuk respons semasa.';
      return '👷 STATUS SUKARELAWAN SIGAP\n\n'
          '✅ Sukarelawan Aktif: $volCount orang bertugas\n'
          '🚨 SOS Memerlukan Respons: $sosCount kes\n\n'
          '$volStatus\n\n'
          'MAKLUMAT PASUKAN:\n'
          '• Sukarelawan aktif boleh dilihat pada tab Peta (ikon kuning)\n'
          '• Untuk mobilisasi sukarelawan: Gunakan fitur "Hantar Notifikasi" dalam tab Kawalan\n'
          '• Sukarelawan tersedia dalam 5km radius akan dimaklumkan secara automatik\n\n'
          'CARA AKTIFKAN SUKARELAWAN TAMBAHAN:\n'
          '1️⃣  Tab Kawalan → "Mobilisasi Sukarelawan"\n'
          '2️⃣  Tetapkan kawasan & kategori insiden\n'
          '3️⃣  Hantar notifikasi push kepada semua sukarelawan berdaftar\n\n'
          '📞 Pangkalan Data Sukarelawan: NADMA 03-8064 2400';
    }

    return null; // Not a data-dependent quick chip
  }

  /// Incident summary for zone closing.
  Future<String> generateIncidentSummary(Map<String, dynamic> zoneData) async {
    try {
      final prompt =
          '''Generate a formal closing report in Malay for a disaster zone.
Zone data: $zoneData
Include: operation summary, total victims assisted, resources deployed, and recovery recommendations. Keep under 200 words.''';

      final response = await _model.generateContent([Content.text(prompt)]);
      return response.text ?? _fallbackIncidentSummary(zoneData);
    } catch (e) {
      return _fallbackIncidentSummary(zoneData);
    }
  }

  // ── Off-Topic Guard ─────────────────────────────────────────────────────

  /// Returns a redirect response if the message is clearly off-topic,
  /// or null if the message is relevant and should be passed to the AI/fallback.
  String? _checkOffTopic(String message) {
    final lower = message.toLowerCase().trim();

    // Allow anything that mentions SIGAP, emergency, or disaster keywords
    final _relevantKeywords = [
      'sos', 'banjir', 'flood', 'flood', 'api', 'fire', 'kebakaran',
      'gempa', 'earthquake', 'tanah runtuh', 'landslide', 'kecemasan',
      'emergency', 'mangsa', 'victim', 'sukarelawan', 'volunteer',
      'pegawai', 'officer', 'tuntutan', 'claim', 'bantuan', 'aid', 'relief',
      'pemindahan', 'evacuation', 'pindah', 'evakuasi', 'pusat pps',
      'safe', 'selamat', 'bahaya', 'danger', 'help', 'tolong', 'minta',
      'nadma', 'bomba', 'pdrm', 'ambulan', 'ambulance', 'hospital',
      'mers', '999', '994', 'hotline', 'nombor', 'number',
      'awanis', 'sigap', 'app', 'aplikasi', 'butang', 'button',
      'laporan', 'report', 'peta', 'map', 'zon', 'zone',
      'rescue', 'selamatkan', 'cari', 'search', 'missing', 'hilang',
      'ubat', 'medicine', 'medical', 'perubatan', 'doktor', 'doctor',
      'bencana', 'disaster', 'kemarau', 'drought', 'ribut', 'storm',
      'mata', 'points', 'sijil', 'certificate', 'misi', 'mission',
      'checklist', 'senarai', 'kit', 'peralatan', 'equipment',
      'geofencing', 'kawasan', 'area', 'kawalan', 'control',
      'status', 'keselamatan', 'safety', 'cuaca', 'weather', 'amaran',
      'warning', 'alert', 'notifikasi', 'notification',
      'air', 'water', 'level', 'paras', 'bumbung', 'roof',
      'keluarga', 'family', 'adik', 'ibu', 'bapa', 'anak',
      'donation', 'derma', 'tabung', 'fund', 'food', 'makanan',
      'tent', 'khemah', 'boat', 'bot', 'boat', 'jambatan', 'bridge',
      'jalan', 'road', 'traffic', 'lalu lintas',
    ];

    final isRelevant = _relevantKeywords.any((kw) => lower.contains(kw));
    if (isRelevant) return null; // Let it through

    // If message is very short (like greetings), let it through
    final wordCount = lower.split(RegExp(r'\s+')).length;
    if (wordCount <= 3) return null;

    // Detect common off-topic categories
    final _offTopicKeywords = [
      'siapa perdana', 'prime minister', 'politik', 'politik', 'politik',
      'pilihan raya', 'election', 'party', 'parti',
      'cerita', 'filem', 'movie', 'film', 'drama', 'lagu', 'music', 'muzik',
      'sukan', 'sports', 'bola', 'football', 'basketball', 'badminton',
      'masak', 'resepi', 'recipe', 'food recipe', 'cara buat',
      'matematik', 'physics', 'math', 'science', 'subjek', 'exam', 'periksa',
      'kerja', 'resume', 'cv', 'interview', 'career',
      'kahwin', 'marry', 'boyfriend', 'girlfriend', 'cinta', 'love',
      'lawak', 'joke', 'funny', 'lucu', 'meme',
      'bitcoin', 'crypto', 'saham', 'stock', 'invest',
      'travel', 'pelancongan', 'hotel', 'kapal terbang', 'flight',
      'beli', 'shopping', 'kedai', 'shop', 'harga', 'price',
      'game', 'permainan', 'netflix', 'youtube', 'tiktok', 'instagram',
      'siapa awak', 'who are you', 'apa itu ai', 'what is ai',
    ];

    final isOffTopic = _offTopicKeywords.any((kw) => lower.contains(kw));
    if (!isOffTopic) return null; // Unknown topic — let AI handle

    // Return bilingual redirect
    final isMalay = lower.contains(RegExp(
        r'\b(saya|anda|boleh|tidak|ya|bagaimana|kenapa|apa|di mana|siapa|tolong)\b'));
    if (isMalay) {
      return 'Maaf, saya AWANIS dan saya hanya boleh membantu dengan perkara yang berkaitan kecemasan dan bencana. '
          'Sila tanya saya tentang:\n'
          '• 🚨 Cara menghantar SOS\n'
          '• 🌊 Panduan banjir / bencana\n'
          '• 📋 Tuntutan bantuan bencana\n'
          '• 🏥 Nombor kecemasan (999, NADMA)\n'
          '• 📍 Pusat pemindahan berdekatan\n\n'
          'Boleh saya bantu dengan sesuatu di atas?';
    } else {
      return 'Sorry, I\'m AWANIS and I can only assist with emergency and disaster-related matters. '
          'Please ask me about:\n'
          '• 🚨 How to send an SOS\n'
          '• 🌊 Flood / disaster safety guidance\n'
          '• 📋 Disaster relief claims\n'
          '• 🏥 Emergency numbers (999, NADMA)\n'
          '• 📍 Nearby evacuation centres\n\n'
          'Can I help you with any of the above?';
    }
  }

  // ── Citizen Fallbacks ────────────────────────────────────────────────────

  String _fallbackCitizenResponse(String message) {
    final lower = message.toLowerCase();

    // SOS / Help
    if (_matches(lower, ['sos', 'hantar sos', 'send sos', 'help', 'tolong', 'minta bantuan'])) {
      return '🚨 Cara Hantar SOS:\n'
          '1. Tekan butang merah SOS di tengah menu bawah aplikasi.\n'
          '2. Pilih jenis insiden (Banjir, Kebakaran, Perubatan, dll).\n'
          '3. Lokasi anda akan dikesan secara automatik.\n'
          '4. Tekan "Hantar" — laporan akan dihantar ke agensi berkaitan.\n\n'
          '📞 Kecemasan segera: Hubungi MERS 999';
    }

    // Flood
    if (_matches(lower, ['banjir', 'flood', 'air naik', 'water rise', 'banjir kilat', 'flash flood'])) {
      return '🌊 Panduan Kecemasan Banjir:\n'
          '1. Segera berpindah ke kawasan tinggi atau tingkat atas.\n'
          '2. Jangan cuba merentasi air yang mengalir deras.\n'
          '3. Bawa dokumen penting (IC, buku bank) dalam beg kalis air.\n'
          '4. Patuhi arahan pihak berkuasa dan pergi ke PPS terdekat.\n'
          '5. Hantar SOS melalui SIGAP jika memerlukan bantuan segera.\n\n'
          '📞 Info banjir: 1-800-88-2727 | NADMA: 03-8064 2400';
    }

    // Fire
    if (_matches(lower, ['api', 'fire', 'kebakaran', 'terbakar', 'asap', 'smoke'])) {
      return '🔥 Panduan Kecemasan Kebakaran:\n'
          '1. Keluar dari bangunan dengan segera — jangan gunakan lif.\n'
          '2. Rendahkan badan jika ada asap tebal.\n'
          '3. Tutup pintu (jangan kunci) untuk melambatkan merebaknya api.\n'
          '4. Berkumpul di titik perhimpunan yang ditetapkan.\n'
          '5. Hubungi Bomba segera: 994\n\n'
          '📞 Bomba: 994 | MERS: 999';
    }

    // Medical / Ambulance
    if (_matches(lower, ['ambulan', 'ambulance', 'perubatan', 'medical', 'sakit', 'injured', 'cedera', 'lemas', 'drowning', 'pengsan', 'fainted', 'heart', 'jantung'])) {
      return '🏥 Kecemasan Perubatan:\n'
          '1. Hubungi ambulans segera: 999\n'
          '2. Pastikan pesakit selamat dan selesa.\n'
          '3. Jangan alihkan mangsa yang disyaki kecederaan tulang belakang.\n'
          '4. Jika pesakit tidak sedar, periksa pernafasan.\n'
          '5. Lakukan CPR jika terlatih dan pesakit tidak bernafas.\n\n'
          '📞 Ambulans: 999 | Hospital Terdekat: Semak tab Peta dalam SIGAP';
    }

    // Evacuation centre / PPS
    if (_matches(lower, ['pps', 'pusat pemindahan', 'evacuation centre', 'evacuation center', 'shelter', 'tempat selamat', 'safe place'])) {
      return '🏠 Pusat Pemindahan (PPS) Terdekat:\n'
          'Pergi ke tab Peta (🗺️) dalam aplikasi SIGAP untuk melihat senarai PPS berdekatan.\n\n'
          'Biasanya PPS ditempatkan di:\n'
          '• Sekolah kebangsaan dan menengah\n'
          '• Dewan olahraga dan balai raya\n'
          '• Masjid dan surau berdaftar\n\n'
          '📞 Maklumat PPS: NADMA 03-8064 2400 | Flood Hotline: 1-800-88-2727';
    }

    // Claims / Relief
    if (_matches(lower, ['tuntutan', 'claim', 'bantuan', 'relief', 'wang', 'money', 'duit', 'pampasan', 'compensation', 'banjir bantuan'])) {
      return '📋 Cara Membuat Tuntutan Bantuan Bencana:\n'
          '1. Pergi ke tab "Tuntutan" dalam aplikasi SIGAP.\n'
          '2. Isi borang dengan: nombor IC, saiz isi rumah, dan gambar kerosakan.\n'
          '3. Hantar borang — pegawai akan menyemak dalam 24-48 jam.\n'
          '4. Status tuntutan boleh dipantau dalam tab yang sama.\n\n'
          '💡 Dokumen yang diperlukan: IC, gambar kerosakan harta, bukti alamat';
    }

    // Family / Safety status
    if (_matches(lower, ['keluarga', 'family', 'adik', 'abang', 'ibu', 'bapa', 'anak', 'selamat', 'status keselamatan', 'safety status', 'track family'])) {
      return '👨‍👩‍👧‍👦 Cara Semak Keselamatan Keluarga:\n'
          '1. Pergi ke profil anda (ikon pengguna di atas kanan).\n'
          '2. Kemas kini status keselamatan anda: Selamat / Dipindahkan / Perlukan Bantuan.\n'
          '3. Tambah ahli keluarga dalam tetapan profil untuk pemantauan bersama.\n\n'
          '📍 Keluarga anda juga perlu memasang SIGAP dan mengemas kini status mereka.';
    }

    // Donation
    if (_matches(lower, ['derma', 'donation', 'tabung', 'fund', 'sumbang', 'contribute'])) {
      return '💙 Cara Membuat Derma Melalui SIGAP:\n'
          '1. Pergi ke tab "Derma" dalam aplikasi.\n'
          '2. Pilih kempen yang ingin disokong.\n'
          '3. Bayar melalui FPX atau kad kredit.\n'
          '4. Resit PDF akan dihantar ke emel anda.\n\n'
          '✅ Semua derma adalah telus — anda boleh lihat laporan penggunaan dana.';
    }

    // Weather / Warning
    if (_matches(lower, ['cuaca', 'weather', 'amaran', 'warning', 'hujan', 'rain', 'ribut', 'storm', 'angin', 'wind'])) {
      return '🌧️ Amaran Cuaca & Bencana:\n'
          'SIGAP memaparkan amaran banjir aktif secara automatik berdasarkan lokasi anda.\n\n'
          'Untuk maklumat cuaca terkini:\n'
          '• Semak tab Peta dalam SIGAP untuk amaran berdekatan.\n'
          '• Pantau laman web Jabatan Meteorologi Malaysia (met.gov.my)\n'
          '• Hotline banjir: 1-800-88-2727\n\n'
          '⚠️ Sekiranya ada amaran merah, sila bersedia untuk pindah.';
    }

    // Missing person
    if (_matches(lower, ['hilang', 'missing', 'cari orang', 'search person', 'lost', 'sesat'])) {
      return '🔍 Laporan Orang Hilang:\n'
          '1. Hubungi PDRM (999) untuk membuat laporan rasmi.\n'
          '2. Hantar SOS melalui SIGAP dengan memilih kategori "Orang Hilang".\n'
          '3. Berikan maklumat: nama, pakaian terakhir, lokasi terakhir dilihat.\n\n'
          '📞 PDRM: 999 | Ibu Pejabat Polis Diraja: 03-2262 6222';
    }

    // Offline guide / checklist
    if (_matches(lower, ['offline', 'panduan', 'guide', 'checklist', 'senarai', 'kit', 'beg kecemasan', 'emergency bag'])) {
      return '📚 Panduan Luar Talian (Offline Guide):\n'
          'Walaupun tanpa internet, anda boleh akses panduan kecemasan.\n\n'
          'Pergi ke: Menu → Panduan Luar Talian\n\n'
          'Kandungan termasuk:\n'
          '• Senarai semak beg kecemasan\n'
          '• Pertolongan cemas asas\n'
          '• Prosedur pemindahan\n'
          '• Nombor kecemasan penting\n\n'
          '💡 Muat turun panduan ini semasa ada internet supaya boleh diakses bila-bila masa.';
    }

    // App navigation help
    if (_matches(lower, ['guna', 'use', 'cara guna', 'how to use', 'navigate', 'navigasi', 'butang', 'button', 'menu', 'tab'])) {
      return '📱 Panduan Navigasi Aplikasi SIGAP:\n'
          '• 🔴 SOS — Butang merah di tengah menu bawah\n'
          '• 🗺️ Peta — Lihat bencana & PPS berdekatan\n'
          '• 📋 Tuntutan — Hantar permohonan bantuan\n'
          '• 💙 Derma — Sumbang kepada mangsa bencana\n'
          '• 🤖 AWANIS — Chat kecemasan AI (halaman ini)\n'
          '• 👤 Profil — Kemas kini status keselamatan anda\n\n'
          'Sebarang soalan, tanya saya di sini!';
    }

    // Generic emergency numbers
    if (_matches(lower, ['nombor', 'number', 'telefon', 'call', 'hubungi', 'contact', 'hotline', 'emergency number'])) {
      return '📞 Nombor Kecemasan Penting Malaysia:\n'
          '• 🚨 MERS 999 — Polis, Bomba, Ambulans\n'
          '• 🚒 Bomba — 994\n'
          '• 🌊 NADMA — 03-8064 2400\n'
          '• 🌧️ Info Banjir — 1-800-88-2727\n'
          '• 🏥 Hospital Kuala Lumpur — 03-2615 5555\n'
          '• 👮 Ibu Pejabat PDRM — 03-2262 6222\n\n'
          'Simpan nombor-nombor ini untuk kegunaan segera!';
    }

    // NADMA
    if (_matches(lower, ['nadma', 'jabatan', 'kerajaan', 'government', 'agensi', 'agency'])) {
      return '🏛️ Agensi Pengurusan Bencana Malaysia:\n'
          '• NADMA (Agensi Pengurusan Bencana Negara): 03-8064 2400\n'
          '• Bomba Malaysia: 994\n'
          '• PDRM: 999\n'
          '• KKM (Kementerian Kesihatan): 03-8883 3888\n\n'
          'SIGAP berhubung dengan agensi-agensi ini secara automatik apabila anda menghantar SOS.';
    }

    // Generic safety tips
    if (_matches(lower, ['tip', 'tips', 'nasihat', 'advice', 'cara', 'how', 'apa yang', 'what should', 'sebelum', 'before', 'semasa', 'during', 'selepas', 'after'])) {
      return '✅ Tips Keselamatan Semasa Bencana:\n'
          '\n🔴 SEBELUM:\n'
          '• Sediakan beg kecemasan (dokumen, ubat, air, makanan 3 hari)\n'
          '• Kenalpasti laluan pemindahan\n'
          '• Simpan nombor kecemasan\n'
          '\n🟡 SEMASA:\n'
          '• Ikut arahan pihak berkuasa\n'
          '• Jangan balik jika sudah dipindah\n'
          '• Kemas kini status di SIGAP\n'
          '\n🟢 SELEPAS:\n'
          '• Periksa keselamatan bangunan sebelum masuk\n'
          '• Laporkan kerosakan untuk tuntutan bantuan\n'
          '• Dapatkan pemeriksaan kesihatan jika perlu';
    }

    // Default fallback
    return '🤖 AWANIS Luar Talian (Mod Terhad)\n\n'
        'Maaf, sambungan AI tidak tersedia buat masa ini.\n\n'
        'Saya boleh bantu dengan topik berikut — cuba tanya:\n'
        '• "Cara hantar SOS"\n'
        '• "Panduan banjir"\n'
        '• "Nombor kecemasan"\n'
        '• "Pusat pemindahan terdekat"\n'
        '• "Cara buat tuntutan bantuan"\n\n'
        '📞 Kecemasan segera: MERS 999';
  }

  // ── Volunteer Fallbacks ─────────────────────────────────────────────────

  String _fallbackVolunteerChat(String message, int activeSos) {
    final lower = message.toLowerCase();

    if (_matches(lower, ['briefing', 'taklimat', 'misi', 'mission', 'tugas', 'task'])) {
      return _fallbackGeneralBriefing(activeSos);
    }

    if (_matches(lower, ['peralatan', 'equipment', 'kit', 'bawa', 'bring', 'barang', 'items'])) {
      return '🎒 Peralatan Wajib Sukarelawan SIGAP:\n'
          '• Jaket keselamatan (life jacket) untuk bencana banjir\n'
          '• Lampu suluh + bateri ganti\n'
          '• Kit pertolongan cemas asas\n'
          '• Tali & karabiner (untuk rescue)\n'
          '• Air bersih & makanan tenaga (energy bar) untuk 8 jam\n'
          '• Telefon bercas penuh + power bank\n'
          '• Pelitup muka & sarung tangan\n'
          '• Kasut boot / kasut keselamatan\n\n'
          '💡 Pastikan semua peralatan diperiksa sebelum misi bermula.';
    }

    if (_matches(lower, ['keselamatan', 'safety', 'bahaya', 'danger', 'risk', 'risiko', 'protect', 'lindung'])) {
      return '🛡️ Protokol Keselamatan Sukarelawan:\n'
          '1. Jangan masuk kawasan berbahaya tanpa backup.\n'
          '2. Sentiasa maklumkan lokasi anda kepada ketua pasukan.\n'
          '3. Utamakan keselamatan diri — anda tidak boleh menyelamatkan orang lain jika anda sendiri dalam bahaya.\n'
          '4. Tarik diri jika situasi melampaui kemampuan — minta bantuan profesional.\n'
          '5. Kemas kini status misi dalam SIGAP secara berkala.\n\n'
          '📞 Kecemasan: 999 | Ketua Pasukan: Hubungi terus';
    }

    if (_matches(lower, ['mangsa', 'victim', 'rescue', 'selamatkan', 'tolong orang', 'evacuate', 'pindah'])) {
      return '🚁 Prosedur Menyelamat Mangsa:\n'
          '1. Nilai keselamatan kawasan sebelum mendekati mangsa.\n'
          '2. Hubungi mangsa secara lisan — nilai tahap kesedaran.\n'
          '3. Jangan alihkan mangsa jika ada kecurigaan kecederaan tulang belakang.\n'
          '4. Gunakan bot atau tali untuk mangsa dalam air.\n'
          '5. Catat bilangan mangsa dan hantar kemas kini melalui SIGAP.\n'
          '6. Bawa mangsa ke PPS atau hospital terdekat.\n\n'
          '📋 Log semua tindakan dalam checklist misi SIGAP.';
    }

    if (_matches(lower, ['mata', 'points', 'sijil', 'certificate', 'reward', 'hadiah', 'ganjaran'])) {
      return '⭐ Sistem SIGAP Mata (Rewards):\n'
          '• Terima mata untuk setiap misi yang diselesaikan.\n'
          '• Misi lebih kritikal = mata lebih tinggi.\n'
          '• Tebus mata untuk sijil pengiktirafan sukarelawan.\n'
          '• Sijil diendors oleh NADMA / Bomba untuk pengiktirafan rasmi.\n\n'
          '📊 Semak jumlah mata anda dalam tab Profil → SIGAP Mata';
    }

    if (_matches(lower, ['checklist', 'senarai semak', 'langkah', 'step', 'procedure', 'prosedur'])) {
      return '📋 Checklist Pra-Misi Sukarelawan:\n'
          '☐ Aktifkan status "Aktif" dalam profil anda\n'
          '☐ Semak lokasi & jenis insiden\n'
          '☐ Pastikan telefon bercas penuh\n'
          '☐ Pasang kit kecemasan\n'
          '☐ Maklumkan keluarga tentang misi anda\n'
          '☐ Sahkan transport ke lokasi kejadian\n'
          '☐ Baca taklimat AWANIS untuk misi berkenaan\n\n'
          '✅ Selesai semua? Anda bersedia untuk misi!';
    }

    if (_matches(lower, ['sos', 'laporan', 'report', 'terima', 'accept', 'decline', 'tolak'])) {
      return '📲 Cara Terima / Tolak Laporan SOS:\n'
          '1. Laporan SOS baharu akan muncul dalam senarai dispatch anda.\n'
          '2. Semak butiran: lokasi, jenis insiden, bilangan mangsa.\n'
          '3. Tekan "Terima" untuk ambil misi atau "Tolak" jika tidak dapat hadir.\n'
          '4. Selepas diterima, navigasi ke lokasi menggunakan peta dalam SIGAP.\n'
          '5. Kemas kini progress melalui checklist misi.\n\n'
          '⚡ Bertindak pantas — setiap saat penting!';
    }

    return '🤖 AWANIS (Mod Luar Talian):\n\n'
        'Terdapat $activeSos laporan SOS aktif pada masa ini.\n\n'
        'Saya boleh bantu dengan:\n'
        '• "Peralatan misi"\n'
        '• "Protokol keselamatan"\n'
        '• "Cara menyelamat mangsa"\n'
        '• "Mata & sijil SIGAP"\n\n'
        'Sentiasa utamakan keselamatan diri! 💪';
  }

  String _fallbackVolunteerBriefing(
      String sosType, String location, int victimCount) {
    final sosEmoji = _getSosTypeEmoji(sosType);
    return '''$sosEmoji TAKLIMAT PRA-MISI SIGAP

📍 Lokasi: $location
⚠️ Jenis Insiden: $sosType  
👥 Anggaran Mangsa: $victimCount orang

🎒 PERALATAN DISYORKAN:
${_getEquipmentForType(sosType)}

🛡️ LANGKAH KESELAMATAN:
1. Pantau keadaan sekeliling sebelum mendekati zon bahaya.
2. Bekerja dalam pasukan — jangan pergi bersendirian.
3. Pakai peralatan pelindung diri (PPE) yang sesuai.
4. Hubungi ketua komander jika situasi melampaui kapasiti anda.

🤝 PENYELARASAN PASUKAN:
• Semak lokasi melalui tab Peta SIGAP.
• Kemas kini status misi anda secara berkala.
• Catat semua tindakan dalam checklist SIGAP.

💪 Anda adalah harapan mangsa. Selamat bertugas!
📞 Kecemasan: MERS 999 | NADMA: 03-8064 2400''';
  }

  String _fallbackGeneralBriefing(int activeSos) {
    final timestamp = DateTime.now();
    final timeStr =
        '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    return '''🤖 TAKLIMAT SISTEM SIGAP — $timeStr

📊 STATUS SEMASA:
• Laporan SOS Aktif: $activeSos kes
• Sistem: Beroperasi

✅ SENARAI SEMAK PRA-MISI:
☐ Status anda ditetapkan kepada "Aktif"
☐ Telefon bercas penuh + internet aktif
☐ Kit kecemasan tersedia
☐ Kenderaan dalam keadaan baik
☐ Keluarga dimaklumkan

🛡️ PERINGATAN KESELAMATAN:
• Utamakan keselamatan diri pada setiap masa.
• Jangan masuk kawasan berbahaya tanpa sokongan.
• Sentiasa kemas kini status dalam aplikasi SIGAP.
• Hubungi ketua pasukan jika ada keraguan.

💪 Terima kasih kerana menjadi sukarelawan SIGAP. Anda membuat perbezaan!
📞 Kecemasan: 999 | NADMA: 03-8064 2400''';
  }

  // ── Officer Fallbacks ────────────────────────────────────────────────────

  String _fallbackOfficerResponse(
      String question, Map<String, dynamic> data) {
    final lower = question.toLowerCase();
    final sosCount = data['jumlah_sos_aktif'] ?? 0;
    final volCount = data['jumlah_sukarelawan_aktif'] ?? 0;
    final claimCount = data['jumlah_tuntutan'] ?? 0;
    final zoneCount = data['jumlah_zon_bencana'] ?? 0;

    // Status / summary questions
    if (_matches(lower, ['status', 'situation', 'situasi', 'semak', 'check', 'summary', 'ringkasan', 'laporan', 'report', 'overview'])) {
      return '📊 RINGKASAN STATUS OPERASI SEMASA:\n\n'
          '🚨 SOS Aktif: $sosCount laporan\n'
          '👷 Sukarelawan Bertugas: $volCount orang\n'
          '📋 Tuntutan Tertunda: $claimCount permohonan\n'
          '🗺️ Zon Bencana Aktif: $zoneCount kawasan\n\n'
          '${sosCount > 10 ? '⚠️ Amaran: Bilangan SOS tinggi. Pertimbangkan pengaktifan protokol darurat tambahan.' : '✅ Situasi dalam kawalan.'}\n\n'
          'Semak tab Peta untuk visualisasi kluster SOS.';
    }

    // SOS related
    if (_matches(lower, ['sos', 'laporan', 'report', 'berapa', 'how many', 'bilangan', 'count'])) {
      return '🚨 STATUS SOS:\n\n'
          '• SOS Aktif: $sosCount laporan\n'
          '• Sukarelawan tersedia: $volCount orang\n'
          '• Nisbah SOS:Sukarelawan: ${volCount > 0 ? (sosCount / volCount).toStringAsFixed(1) : "N/A"}\n\n'
          '${sosCount > volCount ? '⚠️ Permintaan melebihi kapasiti sukarelawan. Sila aktifkan sukarelawan tambahan atau hubungi NADMA.' : '✅ Kapasiti respons mencukupi.'}\n\n'
          'Perincian lokasi: Semak tab Peta dalam dashboard.';
    }

    // Volunteer related
    if (_matches(lower, ['sukarelawan', 'volunteer', 'aktif', 'active', 'available', 'tersedia', 'pasukan', 'team'])) {
      return '👷 STATUS SUKARELAWAN:\n\n'
          '• Sukarelawan Aktif: $volCount orang bertugas\n'
          '• SOS memerlukan respons: $sosCount kes\n\n'
          '${volCount == 0 ? '🔴 KRITIKAL: Tiada sukarelawan aktif. Hubungi pangkalan data sukarelawan NADMA segera.' : volCount < 5 ? '🟡 Bilangan sukarelawan rendah. Pertimbangkan mobilisasi tambahan.' : '🟢 Kapasiti sukarelawan mencukupi.'}\n\n'
          'Untuk mobilisasi tambahan: Hubungi NADMA 03-8064 2400';
    }

    // Claims related
    if (_matches(lower, ['tuntutan', 'claim', 'permohonan', 'application', 'approve', 'lulus', 'pending', 'tertunda'])) {
      return '📋 STATUS TUNTUTAN BANTUAN:\n\n'
          '• Tuntutan Tertunda: $claimCount permohonan\n\n'
          'Tindakan Disyorkan:\n'
          '1. Pergi ke tab "Tuntutan" untuk semak permohonan.\n'
          '2. Utamakan tuntutan dari zon bencana aktif.\n'
          '3. Luluskan tuntutan yang lengkap dokumentasinya.\n'
          '4. Hubungi pemohon jika maklumat tidak lengkap.\n\n'
          '⏱️ Sasaran: Selesaikan semua tuntutan dalam 48 jam.';
    }

    // Zone / geofencing
    if (_matches(lower, ['zon', 'zone', 'kawasan', 'area', 'geofencing', 'sempadan', 'boundary', 'declare', 'isytihar'])) {
      return '🗺️ STATUS ZON BENCANA:\n\n'
          '• Zon Aktif: $zoneCount kawasan diisytiharkan\n\n'
          'Cara Mengurus Zon:\n'
          '1. Pergi ke tab Peta → ikon "+" untuk tambah zon baharu.\n'
          '2. Lukis sempadan zon menggunakan geofencing tool.\n'
          '3. Tetapkan tahap amaran (Awas / Berjaga-jaga / Darurat).\n'
          '4. Notifikasi akan dihantar kepada warga dalam zon secara automatik.\n\n'
          '⚠️ Pastikan zon dikemas kini apabila situasi berubah.';
    }

    // Resource / inventory
    if (_matches(lower, ['sumber', 'resource', 'inventori', 'inventory', 'bekalan', 'supply', 'makanan', 'food', 'khemah', 'tent', 'bot', 'boat'])) {
      return '📦 PENGURUSAN SUMBER & BEKALAN:\n\n'
          'Status bekalan boleh disemak dalam tab "Sumber" dashboard.\n\n'
          'Bekalan kritikal untuk dipantau:\n'
          '• 🍱 Makanan & air bersih (sasaran: 3 hari bekalan)\n'
          '• ⛺ Khemah & selimut (berdasarkan bilangan mangsa)\n'
          '• 🚤 Bot penyelamat (untuk banjir)\n'
          '• 💊 Ubat-ubatan kecemasan\n'
          '• ⚡ Penjana elektrik & bahan api\n\n'
          'Untuk permintaan bekalan tambahan: Hubungi NADMA 03-8064 2400';
    }

    // Emergency numbers / contacts
    if (_matches(lower, ['hubungi', 'contact', 'nombor', 'number', 'talian', 'hotline', 'call'])) {
      return '📞 DIREKTORI HUBUNGAN PEGAWAI:\n\n'
          '• NADMA HQ: 03-8064 2400\n'
          '• Bomba Negara: 994\n'
          '• PDRM: 999\n'
          '• KKM Darurat: 03-8883 3888\n'
          '• Jabatan Meteorologi (Cuaca): 03-7967 8000\n'
          '• Jabatan Pengairan & Saliran: 03-2616 3700\n\n'
          '💡 Tip: Simpan nombor-nombor ini untuk kegunaan operasi segera.';
    }

    // Report generation
    if (_matches(lower, ['laporan', 'report', 'generate', 'jana', 'pdf', 'dokumen', 'document'])) {
      return '📄 Jana Laporan Insiden:\n\n'
          'Untuk menjana laporan PDF rasmi:\n'
          '1. Pergi ke tab AWANIS dalam dashboard anda.\n'
          '2. Tekan butang "Jana Laporan Insiden".\n'
          '3. AWANIS akan meringkaskan data semasa.\n'
          '4. Laporan PDF boleh dikongsi atau dimuat turun.\n\n'
          'Data dalam laporan:\n'
          '• Jumlah SOS: $sosCount\n'
          '• Sukarelawan aktif: $volCount\n'
          '• Tuntutan tertunda: $claimCount\n'
          '• Zon aktif: $zoneCount';
    }

    // Default officer response with data
    return '📊 RINGKASAN DATA OPERASI:\n\n'
        '🚨 SOS Aktif: $sosCount\n'
        '👷 Sukarelawan: $volCount\n'
        '📋 Tuntutan: $claimCount\n'
        '🗺️ Zon Bencana: $zoneCount\n\n'
        '🤖 AWANIS (Luar Talian): Sambungan AI tidak tersedia buat masa ini. Data di atas adalah data langsung dari sistem.\n\n'
        'Cuba tanya saya tentang:\n'
        '• "Status operasi semasa"\n'
        '• "Berapa SOS aktif?"\n'
        '• "Status sukarelawan"\n'
        '• "Tuntutan tertunda"\n'
        '• "Zon bencana aktif"';
  }

  String _fallbackIncidentSummary(Map<String, dynamic> zoneData) {
    final sosCount = zoneData['jumlah_sos_aktif'] ?? 0;
    final volCount = zoneData['sukarelawan_aktif'] ?? 0;
    final zoneName = zoneData['nama_zon'] ?? 'Zon Darurat';
    final timestamp = DateTime.now();
    final dateStr =
        '${timestamp.day}/${timestamp.month}/${timestamp.year} ${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';

    return '''LAPORAN PENUTUPAN ZON BENCANA
Dijana oleh AWANIS — Sistem AI SIGAP
Tarikh/Masa: $dateStr

━━━━━━━━━━━━━━━━━━━━━━━━━
ZON: $zoneName
━━━━━━━━━━━━━━━━━━━━━━━━━

RINGKASAN OPERASI:
Operasi di zon $zoneName telah berjaya dilaksanakan dengan penuh dedikasi oleh pasukan sukarelawan dan pegawai SIGAP.

STATISTIK OPERASI:
• Laporan SOS diproses: $sosCount kes
• Sukarelawan yang terlibat: $volCount orang
• Status zon: Ditutup secara rasmi

TINDAKAN YANG DIAMBIL:
• Mangsa berjaya dipindahkan ke pusat pemindahan
• Bantuan makanan, air dan keperluan asas diedarkan
• Pemantauan berterusan oleh pasukan darat

PERAKUAN:
Semua laporan SOS dalam zon ini telah direspons dan diselesaikan. Zon ini kini selamat untuk fasa pemulihan.

PENGESYORAN SUSULAN:
• Teruskan pemantauan selama 72 jam selepas penutupan.
• Pastikan mangsa mendapat akses kepada bantuan psikologi.
• Mulakan proses pemulihan dan pembinaan semula.
• Semak dan lulus tuntutan bantuan yang tertunda.

━━━━━━━━━━━━━━━━━━━━━━━━━
Laporan ini dijana oleh AWANIS (Sistem AI SIGAP)
Untuk pertanyaan: NADMA 03-8064 2400''';
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Substring keyword match — any keyword found anywhere in text.
  bool _matches(String text, List<String> keywords) {
    return keywords.any((kw) => text.contains(kw));
  }

  /// Exact match — text must equal one of the given strings (case-insensitive,
  /// already normalised before calling). Used for quick-chip lookup.
  bool _exactMatch(String normalisedLower, List<String> exactStrings) {
    return exactStrings.any((s) => normalisedLower == s.toLowerCase());
  }

  String _getSosTypeEmoji(String sosType) {
    final lower = sosType.toLowerCase();
    if (_matches(lower, ['flood', 'banjir', 'air'])) return '🌊';
    if (_matches(lower, ['fire', 'kebakaran', 'api'])) return '🔥';
    if (_matches(lower, ['medical', 'perubatan', 'cedera', 'ambulan'])) return '🏥';
    if (_matches(lower, ['missing', 'hilang', 'orang hilang'])) return '🔍';
    if (_matches(lower, ['landslide', 'tanah runtuh'])) return '⛰️';
    return '🚨';
  }

  String _getEquipmentForType(String sosType) {
    final lower = sosType.toLowerCase();
    if (_matches(lower, ['flood', 'banjir'])) {
      return '• Jaket keselamatan (life jacket)\n'
          '• Bot inflatable / bot penyelamat\n'
          '• Tali penyelamat 20m\n'
          '• Lampu suluh kalis air\n'
          '• Kit pertolongan cemas';
    }
    if (_matches(lower, ['fire', 'kebakaran'])) {
      return '• Alat pernafasan (SCBA) jika tersedia\n'
          '• Helmet tahan api\n'
          '• Selimut tahan api\n'
          '• Pelitup muka N95\n'
          '• Kit pertolongan cemas';
    }
    if (_matches(lower, ['medical', 'perubatan'])) {
      return '• Kit pertolongan cemas lengkap\n'
          '• AED (defibrillator) jika tersedia\n'
          '• Tandu / stretcher\n'
          '• Oksigen mudah alih\n'
          '• Sarung tangan perubatan';
    }
    return '• Kit pertolongan cemas\n'
        '• Lampu suluh + bateri ganti\n'
        '• Air bersih & makanan tenaga\n'
        '• Tali penyelamat\n'
        '• Alat komunikasi (radio/telefon)';
  }
}
