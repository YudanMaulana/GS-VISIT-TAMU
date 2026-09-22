import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'pose_window.dart';
import 'sidecar_client.dart';
import 'theme.dart';
import 'widgets/signature_pad.dart';

/// Jendela kedua: layar sentuh yang diserahkan ke tamu tanpa HP supaya ia
/// mengisi datanya sendiri.
///
/// Tamu ber-HP mengisi formulirnya di app Android; tamu tanpa HP selama ini
/// tidak punya jalan masuk sama sekali. Layar ini menyamakan keduanya —
/// yang mengetik tetap tamu itu sendiri, bukan operator yang menyalin dari
/// ucapan, sehingga salah dengar tidak menjadi salah data.
///
/// Jendela ini **tidak pernah memegang wajah siapa pun**: foto tetap di
/// jendela operator, dan yang menyeberang lewat channel hanya isian formulir,
/// satu arah. Katalog (kategori tamu, wilayah) diambil sendiri dari sidecar
/// di mesin yang sama, jadi daftar panjang tidak perlu dipompa lewat channel.
class GuestKioskWindowApp extends StatelessWidget {
  final int sidecarPort;

  const GuestKioskWindowApp({super.key, required this.sidecarPort});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garudashield Visit — Pendaftaran Tamu',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: GuestKioskPage(sidecarPort: sidecarPort),
    );
  }
}

class GuestKioskPage extends StatefulWidget {
  final int sidecarPort;

  const GuestKioskPage({super.key, required this.sidecarPort});

  @override
  State<GuestKioskPage> createState() => _GuestKioskPageState();
}

class _GuestKioskPageState extends State<GuestKioskPage> {
  static const _channel = WindowMethodChannel(
    'garudafood_visit/kiosk',
    mode: ChannelMode.unidirectional,
  );

  late final SidecarClient _client = SidecarClient(widget.sidecarPort);

  final _nama = TextEditingController();
  final _perusahaan = TextEditingController();
  final _keperluan = TextEditingController();
  final _alamatDetail = TextEditingController();

  String _kategori = '';

  List<String> _kategoriPilihan = const [];

  /// Server menandai peran mana yang wajib memilih kategori (Tamu dan Vendor
  /// wajib, Magang tidak). Dipakai supaya tombol kirim tidak menjanjikan
  /// sesuatu yang akan ditolak server.
  bool _kategoriWajib = false;
  final Map<String, List<Region>> _wilayah = {};
  final Map<String, Region?> _terpilih = {
    'province': null,
    'regency': null,
    'district': null,
    'village': null,
  };

  /// Langkah alur mandiri: diisi saat tamu mendaftar sendiri tanpa petugas.
  /// Kalau null, kiosk mengikuti fase dari jendela petugas (alur lama, saat
  /// petugas yang mengambilkan wajah).
  String? _langkah;

  /// Peran yang tamu pilih di cabang non-mobile.
  String _peran = 'tamu';

  /// Frame kamera + hasil pose, dipoles kiosk sendiri lewat sidecar. Tanpa ini
  /// tamu tidak bisa mengambil wajahnya sendiri.
  DetectionState _kamera = DetectionState();
  Timer? _pollKamera;
  final Map<String, String> _sudut = {};
  int _stabil = 0;
  DateTime _jedaSampai = DateTime.fromMillisecondsSinceEpoch(0);
  bool _mengambil = false;

  /// Layar mana yang sedang dibuka di kiosk. Terpisah dari `_phase` (fase
  /// pendaftaran milik jendela utama): navigasi kiosk urusan layar ini
  /// sendiri, dan menyatukan keduanya membuat tombol "kembali" mustahil.
  String _layar = 'awal';

  Timer? _poll;
  String _phase = 'idle';
  String _visitorCode = '';
  int _visitorId = 0;
  int _visitId = 0;
  final _padTtd = GlobalKey<SignaturePadState>();
  bool _adaGoresan = false;
  String _guestName = '';
  bool _punyaRencana = false;
  String _statusRencana = '';
  bool _sudahTtd = false;
  String _error = '';
  bool _mengirim = false;

  /// Kuis safety: soal dari server, jawaban tamu, dan hasilnya.
  List<Map<String, dynamic>> _soal = const [];
  final Map<int, int> _jawaban = {};
  String _materi = '';
  bool _memuatSafety = false;
  String _hasilKuis = '';

  /// Versi materi safety yang tamu setujui, dibaca dari balasan kuis dan
  /// diteruskan ke rencana kunjungan.
  String _versiSafety = '';

  /// Nomor rencana yang baru dibuat; baris muatan menempel padanya.
  int _planId = 0;

  /// Baris muatan yang sudah tersimpan di server untuk rencana ini.
  List<Map<String, dynamic>> _muatan = const [];

  /// Ringkasan hasil kuis yang lulus. Tanpa ini tamu berpindah layar tanpa
  /// pernah tahu skornya — dan skor itu yang tercatat di kartu tamunya.
  String _ringkasanSkor = '';

  /// Rencana kunjungan.
  final _pic = TextEditingController();

  /// Data sopir. SIM wajib untuk transporter (server menolak tanpa itu), dan
  /// masa berlakunya dipakai papan patroli untuk menandai yang kedaluwarsa --
  /// ditandai, bukan ditolak, karena menahan truk itu keputusan petugas.
  final _sim = TextEditingController();
  DateTime? _simBerlaku;

  /// Plat + muatan: milik satu kedatangan, bukan sifat orangnya.
  final _plat = TextEditingController();
  final _jenisKendaraan = TextEditingController();
  final _barang = TextEditingController();
  final _jumlah = TextEditingController();
  final _shipment = TextEditingController();
  final _kontainer = TextEditingController();
  final _seal = TextEditingController();
  final _rombongan = TextEditingController();
  List<Map<String, dynamic>> _area = const [];
  int? _areaId;
  bool _masukProduksi = false;
  bool _setujuKesehatan = false;

  /// 'bongkar' | 'muat', null sebelum dipilih. Sama seperti app Android:
  /// server menolak 422 tanpa ini untuk transporter.
  String? _loadType;

  @override
  void initState() {
    super.initState();
    _muatKategori();
    _muatWilayah('province', null);
    // Jendela ini pasif: ia menanyakan keadaan ke jendela utama, bukan
    // sebaliknya. Pola yang sama dengan jendela pratinjau kamera.
    _poll = Timer.periodic(const Duration(milliseconds: 400), (_) => _tarikState());
    _tarikState();
  }

  void _mulaiKamera() {
    _pollKamera?.cancel();
    // 90 ms: sama dengan konsol petugas. Cukup untuk panduan pose, tidak
    // sampai membanjiri sidecar yang juga sedang melayani deteksi.
    _pollKamera = Timer.periodic(const Duration(milliseconds: 90), (_) async {
      try {
        final st = await _client.fetchState();
        if (!mounted) return;
        setState(() => _kamera = st);
        _autoAmbil();
      } catch (_) {
        // transient
      }
    });
  }

  void _hentikanKamera() {
    _pollKamera?.cancel();
    _pollKamera = null;
  }

  /// Sudut berikutnya yang belum terambil.
  String? get _sudutBerikutnya {
    for (final (key, _, _) in PoseWindow.steps) {
      if (!_sudut.containsKey(key)) return key;
    }
    return null;
  }

  /// Ambil sendiri begitu pose tepat — tamu tidak punya petugas yang menekan
  /// tombol untuknya, jadi kameranya yang harus tahu kapan saatnya.
  Future<void> _autoAmbil() async {
    if (_mengambil || DateTime.now().isBefore(_jedaSampai)) return;
    final sudut = _sudutBerikutnya;
    final yaw = _kamera.yaw;
    final pitch = _kamera.pitch;
    if (sudut == null || yaw == null || pitch == null || _kamera.faceCount < 1) {
      if (_stabil != 0) setState(() => _stabil = 0);
      return;
    }
    if (!PoseWindow.inTarget(sudut, yaw, pitch)) {
      if (_stabil != 0) setState(() => _stabil = 0);
      return;
    }
    setState(() => _stabil++);
    if (_stabil < PoseWindow.stableReadings) return;

    _stabil = 0;
    _jedaSampai = DateTime.now().add(const Duration(milliseconds: 1200));
    setState(() => _mengambil = true);
    try {
      final cap = await _client.capture();
      if (!cap.ok || !cap.sharp) return;
      final still = await _client.lastStill();
      final b64 = still['jpeg_b64'];
      if (b64 is String && b64.isNotEmpty) {
        setState(() => _sudut[sudut] = b64);
      }
    } catch (_) {
      // Gagal sekali bukan alasan menghentikan tamu; pose berikutnya dicoba lagi.
    } finally {
      if (mounted) setState(() => _mengambil = false);
    }
  }

  @override
  void dispose() {
    _pollKamera?.cancel();
    _poll?.cancel();
    for (final c in [
      _nama, _perusahaan, _keperluan, _alamatDetail, _pic, _rombongan,
      _sim, _plat, _jenisKendaraan, _barang, _jumlah, _shipment, _kontainer,
      _seal,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _tarikState() async {
    // Alur mandiri memegang sendiri identitas tamunya (didaftarkan dari kiosk
    // ini, bukan dari jendela petugas). Menyalin snapshot petugas di tengah
    // alur itu justru menimpa `visitor_id` dengan 0 -- dan pemeriksaan diam
    // di _kirimKuis lalu membatalkan pengiriman tanpa satu pun pesan, persis
    // seperti tombol yang tidak berfungsi.
    if (_langkah != null) return;
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('state');
      if (!mounted || raw == null) return;
      final map = Map<String, dynamic>.from(raw);
      setState(() {
        final fase = map['phase']?.toString() ?? 'idle';
        if (fase != _phase) {
          // Muat bahan tiap tahap sekali saat masuk, bukan tiap polling.
          if (fase == 'safety') _muatSafety();
          if (fase == 'plan') _muatArea();
        }
        _phase = fase;
        _visitorCode = map['visitor_code']?.toString() ?? '';
        _visitorId = (map['visitor_id'] as num?)?.toInt() ?? 0;
        _visitId = (map['visit_id'] as num?)?.toInt() ?? 0;
        _guestName = map['guest_name']?.toString() ?? '';
        _punyaRencana = map['has_plan'] == true;
        _statusRencana = map['plan_status']?.toString() ?? '';
        _sudahTtd = map['signed'] == true;
        _error = map['error']?.toString() ?? '';
        if (_phase != 'submitting') _mengirim = false;
      });
    } catch (_) {
      // Jendela utama belum siap; coba lagi di tik berikutnya.
    }
  }

  // --- Kuis safety ---------------------------------------------------------
  // Bukan tahap tambahan yang bisa dilewat: rencana kunjungan membawa
  // `safety_version_agreed`, dan tamu ber-HP wajib lulus sekali per akun.
  // Melewatkannya di sini berarti data tamu tanpa HP tidak setara.

  Future<void> _muatSafety() async {
    setState(() {
      _memuatSafety = true;
      _jawaban.clear();
      _hasilKuis = '';
    });
    try {
      final materi = await _client.safetyInduction();
      final kuis = await _client.safetyQuiz();
      if (!mounted) return;
      final isi = materi['body'];
      final ind = isi is Map ? isi['induction'] : null;
      final kb = kuis['body'];
      final soal = kb is Map ? kb['questions'] : null;
      setState(() {
        _materi = ind is Map ? (ind['content']?.toString() ?? '') : '';
        _soal = soal is List
            ? [for (final q in soal) if (q is Map) Map<String, dynamic>.from(q)]
            : const [];
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memuat materi safety: $e');
    } finally {
      if (mounted) setState(() => _memuatSafety = false);
    }
  }

  Future<void> _kirimKuis() async {
    if (_jawaban.length < _soal.length) {
      setState(() => _hasilKuis = 'Masih ada soal yang belum dijawab.');
      return;
    }
    if (_visitorId == 0) {
      // Berhenti diam di sini pernah tampak persis seperti tombol rusak.
      setState(() => _hasilKuis =
          'Pendaftaran belum selesai — panggil petugas (identitas tamu belum terbaca).');
      return;
    }
    setState(() {
      _mengirim = true;
      _hasilKuis = '';
    });
    try {
      final res = await _client.submitSafetyQuiz(
        visitorId: _visitorId,
        answers: _jawaban,
      );
      final body = res['body'];
      if (!mounted) return;
      // Balasan tanpa `passed` berarti jawabannya TIDAK dinilai (ditolak
      // server, mis. bentuk payload atau tamu tak dikenal). Menyebutnya
      // "belum lulus" menuduh tamu salah menjawab padahal soalnya tidak
      // pernah sampai ke penilaian -- dan menyembunyikan sebab yang benar.
      if (body is! Map || !body.containsKey('passed')) {
        setState(() => _hasilKuis = 'Jawaban tidak bisa dinilai: '
            '${(body is Map ? body['message'] : null) ?? res['error'] ?? 'server menolak permintaan'}'
            '${res['status'] != null ? ' (HTTP ${res['status']})' : ''}');
        return;
      }
      if (body['passed'] == true) {
        final v = body['visitor'];
        if (v is Map && v['safety_quiz_version'] != null) {
          _versiSafety = '${v['safety_quiz_version']}';
        }
        final skor = body['score'];
        final benar = body['correct_count'];
        final total = body['total_questions'];
        _ringkasanSkor = 'Skor safety Anda: $skor'
            '${benar != null && total != null ? ' ($benar dari $total benar)' : ''}';
        await _tahapSelesai('safety_passed', 'tanya');
      } else {
        final skor = body['score'];
        final benar = body['correct_count'];
        final total = body['total_questions'];
        setState(() => _hasilKuis = 'Skor $skor'
            '${benar != null && total != null ? ' ($benar dari $total benar)' : ''}'
            ' — belum lulus. Silakan baca materinya lagi dan ulangi.');
      }
    } catch (e) {
      if (mounted) setState(() => _hasilKuis = 'Gagal mengirim jawaban: $e');
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  // --- Rencana kunjungan ---------------------------------------------------

  Future<void> _muatArea() async {
    try {
      final res = await _client.areas();
      final body = res['body'];
      final list = body is List ? body : (body is Map ? body['areas'] : null);
      if (!mounted || list is! List) return;
      setState(() => _area = [
            for (final a in list) if (a is Map) Map<String, dynamic>.from(a),
          ]);
    } catch (_) {
      // Area opsional di server; formulir tetap bisa dikirim tanpanya.
    }
  }

  /// Syarat rencana per peran. Sopir wajib plat; tamu wajib PIC (dan kategori
  /// bila server menandainya wajib).
  bool get _rencanaSiap {
    if (_peran == 'transporter') {
      return _plat.text.trim().isNotEmpty && _loadType != null;
    }
    if (_kategoriWajib && _kategori.isEmpty) return false;
    return _pic.text.trim().isNotEmpty;
  }

  Future<void> _kirimRencana() async {
    if (_visitorId == 0) {
      setState(() => _error =
          'Identitas tamu belum terbaca — panggil petugas sebelum melanjutkan.');
      return;
    }
    if (_masukProduksi && !_setujuKesehatan) {
      setState(() => _error = 'Deklarasi kesehatan wajib untuk masuk area produksi.');
      return;
    }
    setState(() {
      _mengirim = true;
      _error = '';
    });
    try {
      // branch_id sengaja tidak dikirim: sidecar mengisinya dari cabang POS.
      final res = await _client.createVisitPlan({
        'visitor_id': _visitorId,
        'visit_date': DateTime.now().toIso8601String().split('T').first,
        if (_areaId != null) 'area_id': _areaId,
        'company': _perusahaan.text.trim(),
        'pic_target': _pic.text.trim(),
        // Server mengharap DAFTAR nama, bukan satu baris teks. Mengirim
        // string membuatnya membalas 422 -- gagal yang di layar tamu hanya
        // terbaca sebagai "gagal membuat rencana".
        'companion_names': [
          for (final n in _rombongan.text.split(','))
            if (n.trim().isNotEmpty) n.trim(),
        ],
        if (_peran == 'transporter') 'vehicle_plate': _plat.text.trim(),
        if (_peran == 'transporter' && _jenisKendaraan.text.trim().isNotEmpty)
          'vehicle_type': _jenisKendaraan.text.trim(),
        if (_peran == 'transporter' && _loadType != null)
          'load_type': _loadType,
        'enters_production': _masukProduksi,
        'health_declaration_agreed': _setujuKesehatan,
        'purpose': _keperluan.text.trim(),
        if (_kategori.isNotEmpty) 'guest_category': _kategori,
        // Versi kuis yang baru saja dilalui tamu — sama seperti yang dikirim
        // app Android dari profil tamunya.
        if (_versiSafety.isNotEmpty) 'safety_version_agreed': _versiSafety,
      });
      final body = res['body'];
      final sukses = res['ok'] == true &&
          body is Map &&
          (body['success'] == true || body['plan'] != null);
      if (!mounted) return;
      if (sukses) {
        // Perusahaan dan kategori disimpan di rencana; kartu tamu di konsol
        // membaca dari data TAMU. Tanpa penyalinan ini, operator melihat kolom
        // kosong untuk tamu yang barusan mengisinya sendiri.
        await _perbaruiProfilTamu();
        // Nomor rencana disimpan: baris muatan menempel padanya, bukan pada
        // orangnya -- satu sopir bisa datang lagi hari ini dengan muatan lain.
        final b = body;
        final plan = b['plan'];
        if (plan is Map) _planId = (plan['id'] as num?)?.toInt() ?? 0;
        // Hanya sopir BONGKAR yang mengisi data barang di sini -- ia sudah
        // memegang surat jalan. Sopir MUAT diteruskan seperti tamu: barangnya
        // dicatat petugas dari E-Patrol setelah truknya dikonfirmasi masuk.
        if (_peran == 'transporter' && _loadType == 'bongkar') {
          _lanjut('muatan');
        } else {
          await _tahapSelesai('plan_created', 'checkin');
        }
      } else {
        setState(() => _error = 'Rencana kunjungan ditolak: '
            '${(body is Map ? (body['message'] ?? body['detail']) : null) ?? res['error'] ?? 'server tidak memberi keterangan'}'
            '${res['status'] != null ? ' (HTTP ${res['status']})' : ''}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal membuat rencana: $e');
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  Future<void> _muatKategori() async {
    try {
      final res = await _client.guestCategories();
      final body = res['body'];
      if (!mounted || body is! Map) return;
      final cats = body['categories'];
      if (cats is! List) return;
      // Balasannya berjenjang: tiap peran (Tamu/Vendor/Magang) membawa daftar
      // kategorinya sendiri. Yang tampil di dropdown harus daftar DALAM milik
      // peran yang dipilih -- bukan nama perannya, yang tamu sudah pilih di
      // layar sebelumnya.
      // Dicari dengan perulangan, bukan firstWhere+orElse: orElse harus
      // mengembalikan tipe elemen daftarnya, dan itu pecah begitu daftarnya
      // datang bertipe lebih sempit daripada List<dynamic>.
      Map? cocok;
      for (final c in cats) {
        if (c is Map && '${c['name']}'.toLowerCase() == _peran.toLowerCase()) {
          cocok = c;
          break;
        }
      }
      final entri = cocok;
      if (entri == null) return;
      final daftar = entri['categories'];
      setState(() {
        _kategoriPilihan = [
          for (final k in (daftar is List ? daftar : const []))
            if (k != null) '$k',
        ];
        _kategoriWajib = entri['category_required'] == true;
      });
    } catch (_) {
      // Kategori kosong = dropdown kosong; tamu tetap bisa mengisi sisanya.
    }
  }

  Future<void> _muatWilayah(String tingkat, String? parentCode) async {
    try {
      final res = await _client.regions(parentCode: parentCode);
      final body = res['body'];
      if (!mounted) return;
      final list = body is List
          ? body
          : (body is Map ? (body['regions'] as List? ?? const []) : const []);
      setState(() {
        _wilayah[tingkat] = [
          for (final r in list)
            if (r is Map) Region.fromJson(Map<String, dynamic>.from(r)),
        ];
      });
    } catch (_) {
      // Biarkan kosong; alamat detail masih bisa diisi bebas.
    }
  }

  /// Wilayah berjenjang: memilih ulang tingkat atas membuang pilihan di
  /// bawahnya. Tanpa ini, mengganti provinsi meninggalkan desa dari provinsi
  /// lama — alamat yang tampak lengkap tapi tidak pernah ada.
  void _pilihWilayah(String tingkat, Region? nilai) {
    const urutan = ['province', 'regency', 'district', 'village'];
    final i = urutan.indexOf(tingkat);
    setState(() {
      _terpilih[tingkat] = nilai;
      for (final bawah in urutan.skip(i + 1)) {
        _terpilih[bawah] = null;
        _wilayah.remove(bawah);
      }
    });
    if (nilai != null && i + 1 < urutan.length) {
      _muatWilayah(urutan[i + 1], nilai.code);
    }
  }

  bool get _bisaKirim {
    if (_mengirim) return false;
    if (_nama.text.trim().isEmpty) return false;
    if (!_alamatLengkap) return false;
    // Magang: sekolah dan jurusan wajib, sama seperti di app Android.
    if (_peran == 'magang' &&
        (_perusahaan.text.trim().isEmpty || _keperluan.text.trim().isEmpty)) {
      return false;
    }
    // Server menolak transporter tanpa nomor SIM dan masa berlakunya; menahan
    // tombolnya di sini supaya tamu tidak mengetik seluruh formulir untuk
    // ditolak di ujung.
    if (_peran == 'transporter' &&
        (_sim.text.trim().isEmpty ||
            _simBerlaku == null ||
            _perusahaan.text.trim().isEmpty)) {
      return false;
    }
    return _langkah == 'data' || _phase == 'guestFilling';
  }

  Future<void> _kirim() async {
    if (!_bisaKirim) return;
    // Alur mandiri: datanya belum dikirim ke mana pun -- wajahnya diambil
    // dulu, baru semuanya berangkat sebagai satu pendaftaran.
    if (_langkah == 'data') {
      _lanjut('wajah');
      return;
    }
    setState(() => _mengirim = true);
    // Satu definisi field untuk dua jalur (mandiri dan lewat petugas):
    // dua salinan yang pelan-pelan berbeda adalah cara paling mudah membuat
    // data tamu tidak setara tergantung siapa yang mendaftarkannya.
    final fields = _fieldPendaftaran();
    try {
      await _channel.invokeMethod('submit', fields);
    } catch (e) {
      if (mounted) {
        setState(() {
          _mengirim = false;
          _error = 'Tidak bisa mengirim ke petugas: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(child: _isi()),
      ),
    );
  }

  Widget _isi() {
    // Alur mandiri (tamu tanpa petugas) memegang langkahnya sendiri; kalau
    // sedang berjalan, fase dari jendela petugas tidak dipakai sama sekali —
    // dua sumber kebenaran untuk satu layar hanya menghasilkan layar yang
    // berkedip antara dua tahap.
    final langkah = _langkah;
    if (langkah != null) {
      return switch (langkah) {
        'peran' => _layarPeran(),
        'data' => _formulir(),
        'wajah' => _layarWajah(),
        'safety' => _layarKuis(),
        'tanya' => _layarTanyaRencana(),
        'rencana' => _layarRencana(),
        'muatan' => _layarMuatan(),
        'checkin' => _layarCheckin(),
        'ttd' => _layarTtd(),
        _ => _layarSelesai(),
      };
    }
    // Fase dari jendela petugas hanya boleh mengambil alih layar SETELAH
    // petugas benar-benar menyerahkannya (guestFilling dan seterusnya).
    // Sebelum itu -- termasuk saat petugas sedang mengambil foto -- layar ini
    // tetap menu Pengguna Mobile / non-mobile, karena itulah pintu masuk
    // tamu yang datang sendiri. Kalau tidak, satu klik "Bantu ambil wajah" di
    // sisi petugas mengunci layar tamu jadi "Menunggu petugas".
    const faseMilikPetugas = {
      'guestFilling',
      'submitting',
      'safety',
      'plan',
      'done',
      'failed',
    };
    if (!faseMilikPetugas.contains(_phase)) {
      return switch (_layar) {
        'mobile' => _menuMobile(),
        'mobile_tamu' => _layarStatusTamu(),
        'nonmobile' => _menuNonMobile(),
        _ => _menuAwal(),
      };
    }
    switch (_phase) {
      case 'idle':
        return switch (_layar) {
          'mobile' => _menuMobile(),
          'mobile_tamu' => _layarStatusTamu(),
          'nonmobile' => _menuNonMobile(),
          _ => _menuAwal(),
        };
      case 'guestFilling':
        return _formulir();
      case 'safety':
        return _layarKuis();
      case 'askPlan':
        return _layarTanyaRencana();
      case 'plan':
        return _layarRencana();
      case 'checkin':
        return _layarCheckin();
      case 'signature':
        return _layarTtd();
      case 'submitting':
        return _pesanBesar(
          Icons.hourglass_top,
          'Sedang didaftarkan…',
          'Mohon tunggu sebentar.',
        );
      case 'done':
        return _selesai();
      case 'failed':
        return _pesanBesar(
          Icons.error_outline,
          'Pendaftaran gagal',
          _error.isEmpty ? 'Silakan hubungi petugas.' : _error,
          tone: AppTheme.badRed,
        );
      default:
        return _pesanBesar(
          Icons.badge_outlined,
          'Menunggu petugas',
          'Petugas sedang mengambil foto wajah Anda.',
        );
    }
  }

  /// Layar pembuka: satu pertanyaan saja, karena dua cabangnya benar-benar
  /// berbeda. Tamu ber-HP sudah punya identitas dan rencananya di aplikasi —
  /// yang dia butuhkan di sini cuma gerbang. Tamu tanpa HP belum punya apa
  /// pun, dan layar ini menggantikan aplikasinya.
  Widget _menuAwal() {
    return _bingkai(
      judul: 'Selamat datang',
      keterangan: 'Silakan pilih sesuai keadaan Anda.',
      anak: [
        _tombolMenu(Icons.smartphone, 'Pengguna Mobile',
            'Saya sudah punya aplikasi Garudashield Visit di HP',
            () => setState(() => _layar = 'mobile')),
        _tombolMenu(Icons.person_outline, 'Pengguna non-mobile',
            'Saya tidak membawa/menggunakan aplikasi di HP',
            () => setState(() => _layar = 'nonmobile')),
      ],
    );
  }

  Widget _menuMobile() {
    return _bingkai(
      judul: 'Pengguna Mobile',
      keterangan: 'Pilih keperluan Anda.',
      kembali: () => setState(() => _layar = 'awal'),
      anak: [
        _tombolMenu(Icons.person, 'Tamu', 'Check-in atau check-out kunjungan',
            () => setState(() => _layar = 'mobile_tamu')),
        _tombolMenu(Icons.local_shipping_outlined, 'Transporter',
            'Belum diatur — server belum punya modulnya', null),
        _tombolMenu(Icons.badge_outlined, 'Absensi',
            'Belum diatur — server belum punya modulnya', null),
      ],
    );
  }

  /// Cabang tamu ber-HP: wajah dulu, baru tombol.
  ///
  /// Tombolnya tidak pernah menyala berdasarkan tebakan. Check-out digerbang
  /// tanda tangan tamu di server, jadi menyalakannya sebelum tanda tangan itu
  /// ada hanya memindahkan penolakan ke depan wajah tamu.
  Widget _layarStatusTamu() {
    final belumDeteksi = _visitorId == 0;
    final bolehCheckin = !belumDeteksi && _punyaRencana && _statusRencana == 'planned';
    final sudahCheckin = _statusRencana == 'checked_in' || _statusRencana == 'signed';
    final bolehCheckout = sudahCheckin && _sudahTtd;

    String pesan;
    if (belumDeteksi) {
      pesan = 'Hadapkan wajah Anda ke kamera petugas, lalu tekan tombol di bawah.';
    } else if (!_punyaRencana) {
      pesan = 'Belum ada rencana kunjungan hari ini. Buat dulu di aplikasi HP Anda.';
    } else if (_statusRencana == 'checked_out') {
      pesan = 'Anda sudah check-out hari ini. Terima kasih.';
    } else if (sudahCheckin && !_sudahTtd) {
      pesan = 'Anda sudah check-in, tetapi tanda tangan belum ada. '
          'Silakan tanda tangan di aplikasi HP Anda sebelum check-out.';
    } else if (sudahCheckin) {
      pesan = 'Anda sudah check-in dan sudah tanda tangan. Silakan check-out '
          'bila kunjungan selesai.';
    } else {
      pesan = 'Rencana kunjungan Anda hari ini ditemukan. Silakan check-in.';
    }

    return _bingkai(
      judul: belumDeteksi ? 'Tamu — Pengguna Mobile' : _guestName,
      keterangan: pesan,
      kembali: () => setState(() => _layar = 'mobile'),
      anak: [
        if (belumDeteksi)
          _tombolMenu(Icons.face_retouching_natural, 'Deteksi wajah saya',
              'Petugas akan mengambil satu foto dari kamera pos',
              () => _mulai('status_tamu'))
        else ...[
          _tombolMenu(Icons.login, 'Check-in',
              bolehCheckin
                  ? 'Masuk sekarang'
                  : (sudahCheckin
                      ? 'Anda sudah check-in'
                      : 'Perlu rencana kunjungan hari ini'),
              bolehCheckin ? () => _mulai('checkin_tamu') : null),
          _tombolMenu(Icons.logout, 'Check-out',
              bolehCheckout
                  ? 'Selesai berkunjung'
                  : (sudahCheckin
                      ? 'Menunggu tanda tangan Anda di aplikasi'
                      : 'Belum check-in'),
              bolehCheckout ? () => _mulai('checkout_tamu') : null),
          _tombolMenu(Icons.refresh, 'Deteksi ulang',
              'Bukan Anda? Ulangi pengenalan wajah', () => _mulai('status_tamu')),
        ],
      ],
    );
  }

  Widget _menuNonMobile() {
    return _bingkai(
      judul: 'Pengguna non-mobile',
      keterangan: 'Apakah Anda sudah pernah registrasi wajah di sini?',
      kembali: () => setState(() => _layar = 'awal'),
      anak: [
        _tombolMenu(Icons.person_add_alt, 'Belum, saya baru pertama kali',
            'Registrasi sendiri: peran, data diri, foto wajah, safety induction',
            () => setState(() => _langkah = 'peran')),
        _tombolMenu(Icons.event_available, 'Sudah pernah registrasi',
            'Wajah Anda dicek dulu, lalu lanjut ke rencana kunjungan',
            () => _mulai('register_tamu')),
        _tombolMenu(Icons.local_shipping_outlined, 'Transporter / Absensi',
            'Belum diatur — server belum punya modulnya', null),
      ],
    );
  }

  /// Rangka seragam untuk layar-layar menu: judul besar, satu kalimat
  /// penjelas, tombol-tombol, dan tombol kembali kalau bukan layar pertama.
  // --- Alur mandiri: tamu mengerjakan sendiri, tanpa petugas ---------------
  // Bedanya dengan alur lama bukan tampilan, melainkan siapa yang memegang
  // kendali: di sini kiosk yang memanggil sidecar langsung (kamera,
  // pendaftaran, check-in, tanda tangan), bukan menitipkannya ke jendela
  // petugas. Petugas tidak selalu ada di meja, dan alur yang menunggu
  // seseorang menekan tombol di layar lain akan berhenti di situ.

  /// Tahap selesai: di alur mandiri pindah langkah lokal, di alur petugas
  /// lapor lewat channel.
  ///
  /// Dua alur ini punya sumber kebenaran berbeda (langkah lokal vs fase dari
  /// jendela petugas), dan memakai channel di alur mandiri berarti fase yang
  /// berpindah adalah fase yang tidak sedang digambar -- tamu melihat layar
  /// yang diam padahal jawabannya sudah terkirim dan lulus.
  Future<void> _tahapSelesai(String aksiChannel, String langkahBerikut) async {
    if (_langkah != null) {
      _lanjut(langkahBerikut);
      return;
    }
    await _channel.invokeMethod(aksiChannel);
  }

  /// Pindah langkah. Di alur mandiri cukup mengganti langkah lokal; di alur
  /// lama (petugas yang mengambilkan wajah) tetap lewat channel.
  void _lanjut(String langkah) {
    if (_langkah == null) return;
    setState(() {
      _langkah = langkah;
      _error = '';
    });
    // Kamera dipakai di dua langkah: registrasi wajah dan check-in. Tanpa
    // pratinjau di langkah check-in, tamu tidak tahu apakah wajahnya masuk
    // bingkai — dan pengambilan fotonya tampak seperti tidak terjadi.
    // Langkah 'checkin' menampilkan layar menunggu antrian untuk sopir, bukan
    // pratinjau kamera -- lihat _layarCheckin. Menyalakan kamera di sana
    // berarti menahan perangkatnya menyala tanpa satu pun gambar yang dipakai,
    // dan kiosk yang ditinggal di layar itu akan memegang kamera terus sampai
    // orang berikutnya datang.
    final butuhKamera = langkah == 'wajah' ||
        (langkah == 'checkin' && _peran != 'transporter');
    if (butuhKamera) {
      _mulaiKamera();
    } else {
      _hentikanKamera();
    }
    if (langkah == 'safety') _muatSafety();
    if (langkah == 'rencana') {
      _muatArea();
      // Kategorinya bergantung pada peran, jadi baru bisa dimuat setelah
      // perannya dipilih -- bukan saat kiosk pertama kali dibuka.
      _muatKategori();
    }
  }

  Widget _layarPeran() {
    return _bingkai(
      judul: 'Anda mendaftar sebagai apa?',
      keterangan: 'Pilih peran Anda hari ini.',
      kembali: () => setState(() {
        _langkah = null;
        _layar = 'nonmobile';
      }),
      anak: [
        _tombolMenu(Icons.person, 'Tamu', 'Kunjungan ke Garudafood', () {
          setState(() => _peran = 'tamu');
          _lanjut('data');
        }),
        _tombolMenu(Icons.local_shipping_outlined, 'Transporter',
            'Sopir bongkar muat — perlu No SIM dan plat kendaraan', () {
          setState(() => _peran = 'transporter');
          _lanjut('data');
        }),
        _tombolMenu(Icons.badge_outlined, 'Absensi',
            'Belum diatur — server belum punya modulnya', null),
      ],
    );
  }

  /// Pengambilan tiga sudut wajah, dijalankan tamu sendiri.
  ///
  /// Tidak ada tombol rana: pose yang tepat ditahan sebentar dan fotonya
  /// diambil sendiri (aturan pose sama persis dengan app Android, lihat
  /// [PoseWindow]). Tamu yang sedang memutar kepala tidak bisa sekaligus
  /// menekan tombol di layar yang sama.
  Widget _layarWajah() {
    final sudut = _sudutBerikutnya;
    final selesai = sudut == null;
    final (_, judul, petunjuk) = selesai
        ? ('', 'Selesai', 'Ketiga sudut sudah terambil.')
        : PoseWindow.steps.firstWhere((e) => e.$1 == sudut);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 28, 40, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Registrasi wajah',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('$judul — $petunjuk',
              style: const TextStyle(color: AppTheme.brandGold, fontSize: 17)),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.panelAlt),
              ),
              clipBehavior: Clip.antiAlias,
              child: _kamera.frameBytes == null
                  ? const Center(
                      child: Text('menunggu kamera…',
                          style:
                              TextStyle(color: AppTheme.muted, fontSize: 15)))
                  : Image.memory(_kamera.frameBytes!,
                      gaplessPlayback: true, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 10),
          if (!selesai)
            LinearProgressIndicator(
              value: _stabil / PoseWindow.stableReadings,
              minHeight: 8,
              backgroundColor: AppTheme.panelAlt,
              color: AppTheme.okGreen,
            ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final (key, label, _) in PoseWindow.steps)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    children: [
                      Container(
                        width: 92,
                        height: 92,
                        decoration: BoxDecoration(
                          color: AppTheme.panelAlt,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _sudut.containsKey(key)
                                ? AppTheme.okGreen
                                : AppTheme.panelAlt,
                            width: 2,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: _sudut.containsKey(key)
                            ? Image.memory(base64Decode(_sudut[key]!),
                                fit: BoxFit.cover, cacheWidth: 184)
                            : const Icon(Icons.face_outlined,
                                color: AppTheme.muted, size: 34),
                      ),
                      const SizedBox(height: 6),
                      Text(label,
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          if (selesai)
            SizedBox(
              height: 66,
              child: FilledButton(
                onPressed: _mengirim ? null : _daftarMandiri,
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: AppTheme.brandBlueDeep,
                ),
                child: Text(_mengirim ? 'Mendaftarkan…' : 'Lanjut',
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
              ),
            )
          else
            TextButton(
              onPressed: () => setState(_sudut.clear),
              child: const Text('Ulangi dari awal',
                  style: TextStyle(color: AppTheme.muted, fontSize: 15)),
            ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 15)),
          ],
        ],
      ),
    );
  }

  Future<void> _daftarMandiri() async {
    setState(() {
      _mengirim = true;
      _error = '';
    });
    try {
      final res = await _client.registerWalkIn(
        frontalB64: _sudut['frontal']!,
        leftB64: _sudut['left']!,
        rightB64: _sudut['right']!,
        fields: _fieldPendaftaran(),
      );
      final hasil = WalkInResult.fromEnvelope(res);
      if (!mounted) return;
      if (!hasil.success) {
        setState(() => _error = hasil.message);
        return;
      }
      // embeddings_saved diperiksa terpisah dari success: tiga sudut yang
      // gagal terkirim sebagai field berulang tetap dibalas sukses dengan satu
      // embedding, dan itu baru terasa saat wajahnya sulit dikenali.
      if (!hasil.allAnglesSaved) {
        setState(() => _error =
            'Hanya ${hasil.embeddingsSaved} dari 3 sudut wajah tersimpan. '
            'Panggil petugas sebelum melanjutkan.');
        return;
      }
      setState(() {
        _visitorId = hasil.visitorId;
        _visitorCode = hasil.visitorCode;
      });
      _hentikanKamera();
      _lanjut('safety');
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal mendaftar: $e');
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  Map<String, String> _fieldPendaftaran() => {
        'full_name': _nama.text.trim(),
        'phone': '',
        'visitor_type': _peran,
        // Persis pemetaan app Android: untuk magang, sekolah masuk ke `company`
        // dan jurusan ke `purpose`. Untuk peran lain keduanya kosong dan diisi
        // di rencana kunjungan.
        if (_peran == 'magang') 'company': _perusahaan.text.trim(),
        if (_peran == 'magang') 'purpose': _keperluan.text.trim(),
        if (_peran == 'transporter') 'company': _perusahaan.text.trim(),
        if (_peran == 'transporter') 'sim_number': _sim.text.trim(),
        if (_peran == 'transporter' && _simBerlaku != null)
          'sim_expires_at': _tanggalIso(_simBerlaku!),
        if (_terpilih['province'] != null)
          'address_province_code': _terpilih['province']!.code,
        if (_terpilih['regency'] != null)
          'address_regency_code': _terpilih['regency']!.code,
        if (_terpilih['district'] != null)
          'address_district_code': _terpilih['district']!.code,
        if (_terpilih['village'] != null)
          'address_village_code': _terpilih['village']!.code,
        if (_alamatDetail.text.trim().isNotEmpty)
          'address_detail': _alamatDetail.text.trim(),
      };

  /// Salin perusahaan + kategori dari rencana ke profil tamu.
  ///
  /// Keduanya memang milik kunjungan (satu orang bisa datang dengan keperluan
  /// berbeda), tapi konsol Manajemen Tamu menampilkan data tamu — jadi nilai
  /// terakhir disalin ke sana agar kartunya tidak tampak kosong. Gagal
  /// menyalin tidak membatalkan rencana yang sudah jadi.
  Future<void> _perbaruiProfilTamu() async {
    // HANYA field yang diterima UpdateVisitorRequest di server: address,
    // company, date_of_birth, full_name, guest_category, phone, visitor_type.
    // Menyelipkan `purpose` (yang milik rencana, bukan tamu) membuat SELURUH
    // permintaan ditolak 422 -- dan karena kegagalan di sini sengaja tidak
    // menghentikan tamu, penolakannya tidak terlihat oleh siapa pun.
    final fields = <String, String>{
      if (_perusahaan.text.trim().isNotEmpty) 'company': _perusahaan.text.trim(),
      if (_kategori.isNotEmpty) 'guest_category': _kategori,
    };
    if (fields.isEmpty) return;
    try {
      await _client.updateVisitor(_visitorId, fields);
    } catch (_) {
      // Rencana sudah terbuat; kartu tamu yang kurang lengkap bukan alasan
      // menghentikan tamu di depan gerbang.
    }
  }

  /// Tahap 3: data kendaraan & barang.
  ///
  /// Barisnya bisa lebih dari satu — satu truk bisa membawa beberapa jenis
  /// barang sekaligus — dan tiap baris dikirim begitu ditambahkan, bukan
  /// ditumpuk lalu dikirim sekaligus di akhir. Kalau layar mati di tengah,
  /// yang sudah masuk tetap tercatat dan sopir tidak mengulang dari nol.
  Widget _layarMuatan() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Data Kendaraan & Barang',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Kendaraan: ${_plat.text.trim()}',
              style: const TextStyle(color: AppTheme.brandGold, fontSize: 16)),
          const SizedBox(height: 18),
          if (_muatan.isNotEmpty) ...[
            for (var i = 0; i < _muatan.length; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.panel.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        color: AppTheme.okGreen, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        [
                          '${i + 1}. ${_muatan[i]['goods_name'] ?? ''}',
                          if ('${_muatan[i]['quantity'] ?? ''}'.isNotEmpty)
                            'qty ${_muatan[i]['quantity']}',
                          if ('${_muatan[i]['shipment_no'] ?? ''}'.isNotEmpty)
                            'SI ${_muatan[i]['shipment_no']}',
                          if ('${_muatan[i]['container_no'] ?? ''}'.isNotEmpty)
                            'kontainer ${_muatan[i]['container_no']}',
                          if ('${_muatan[i]['seal_no'] ?? ''}'.isNotEmpty)
                            'seal ${_muatan[i]['seal_no']}',
                        ].join(' · '),
                        style: const TextStyle(color: AppTheme.fg, fontSize: 15),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
          ],
          _isian('Nama barang *', _barang),
          _isian('Quantity (mis. 20 pallet)', _jumlah),
          _isian('No Shipment / SI', _shipment),
          _isian('No Kontainer', _kontainer),
          _isian('No Seal', _seal),
          const SizedBox(height: 14),
          SizedBox(
            height: 62,
            child: OutlinedButton.icon(
              onPressed: (_barang.text.trim().isEmpty || _mengirim)
                  ? null
                  : _tambahMuatan,
              icon: const Icon(Icons.add, size: 22),
              label: Text(_mengirim ? 'Menyimpan…' : 'Tambah baris muatan',
                  style: const TextStyle(fontSize: 18)),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.fg),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 66,
            child: FilledButton(
              onPressed: (_muatan.isEmpty || _mengirim)
                  ? null
                  : () => _lanjut('checkin'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandGold,
                foregroundColor: AppTheme.brandBlueDeep,
              ),
              child: Text(
                  _muatan.isEmpty
                      ? 'Tambahkan minimal satu baris muatan'
                      : 'Selesai — lanjut ke pos',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(_error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 15)),
          ],
        ],
      ),
    );
  }

  Future<void> _tambahMuatan() async {
    if (_planId == 0) {
      setState(() => _error =
          'Rencana bongkar muat belum tersimpan — panggil petugas.');
      return;
    }
    setState(() {
      _mengirim = true;
      _error = '';
    });
    try {
      final res = await _client.addLoad(planId: _planId, load: {
        'goods_name': _barang.text.trim(),
        'quantity': _jumlah.text.trim(),
        'shipment_no': _shipment.text.trim(),
        'container_no': _kontainer.text.trim(),
        'seal_no': _seal.text.trim(),
      });
      final body = res['body'];
      if (res['ok'] != true || (body is Map && body['success'] == false)) {
        setState(() => _error = 'Muatan ditolak: '
            '${(body is Map ? body['message'] : null) ?? res['error'] ?? 'server tidak memberi keterangan'}'
            '${res['status'] != null ? ' (HTTP ${res['status']})' : ''}');
        return;
      }
      // Dibaca ulang dari server, bukan ditambahkan ke daftar lokal: yang
      // ditampilkan ke sopir harus yang benar-benar tersimpan.
      final segar = await _client.loads(_planId);
      if (!mounted) return;
      setState(() {
        _muatan = segar;
        for (final c in [_barang, _jumlah, _shipment, _kontainer, _seal]) {
          c.clear();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan muatan: $e');
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  /// Check-in mandiri: satu foto dari kamera yang sama, dikirim ke server.
  Future<void> _checkinMandiri() async {
    setState(() {
      _mengirim = true;
      _error = '';
    });
    try {
      final cap = await _client.capture();
      if (!cap.ok || !cap.sharp) {
        setState(() => _error = 'Foto kurang jelas. Menghadap kamera lalu coba lagi.');
        return;
      }
      final r = await _client.submit('checkin');
      final res = RecognitionResult.fromJson(r);
      if (!mounted) return;
      if (!res.success) {
        // Pesan server apa adanya: ia menyebut sebabnya (salah cabang, salah
        // hari, sudah check-in) -- petunjuk yang tamu butuhkan.
        setState(() => _error = res.message);
        return;
      }
      setState(() => _visitId = int.tryParse('${res.visitId ?? ''}') ?? 0);
      _hentikanKamera();
      _lanjut('ttd');
    } catch (e) {
      if (mounted) setState(() => _error = 'Check-in gagal: $e');
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  /// Penutup alur mandiri: kode tamu, lalu jalan kembali ke menu untuk orang
  /// berikutnya. Tanpa tombol itu kiosk tersangkut menampilkan kode milik tamu
  /// sebelumnya.
  Widget _layarSelesai() {
    return _bingkai(
      judul: 'Selesai',
      keterangan: _visitorCode.isEmpty
          ? 'Terima kasih.'
          : 'Kode tamu Anda: $_visitorCode. Sebutkan kepada petugas bila diperlukan.',
      anak: [
        _tombolMenu(Icons.home_outlined, 'Kembali ke menu',
            'Untuk tamu berikutnya', _bersihkanSesi),
      ],
    );
  }

  /// Buang seluruh sisa tamu sebelumnya — foto, isian, kode, dan jawaban kuis.
  /// Sisa satu orang yang terbawa ke pendaftaran orang lain adalah data yang
  /// salah nama.
  void _bersihkanSesi() {
    _hentikanKamera();
    for (final c in [_nama, _perusahaan, _keperluan, _alamatDetail, _pic, _rombongan]) {
      c.clear();
    }
    setState(() {
      _langkah = null;
      _layar = 'awal';
      _sudut.clear();
      _jawaban.clear();
      _soal = const [];
      _visitorId = 0;
      _visitId = 0;
      _visitorCode = '';
      _kategori = '';
      _areaId = null;
      _masukProduksi = false;
      _setujuKesehatan = false;
      _loadType = null;
      _terpilih.updateAll((_, _) => null);
      _error = '';
      _hasilKuis = '';
    });
  }

  /// Setelah kuis: ditanya, bukan diasumsikan.
  ///
  /// Sebagian tamu mendaftar untuk kunjungan lain hari — membuatkan rencana
  /// hari ini untuk mereka berarti rencana yang harus dibatalkan orang lain
  /// nanti, dan sampai dibatalkan ia menghalangi rencana yang benar.
  Widget _layarTanyaRencana() {
    return _bingkai(
      judul: 'Safety induction selesai',
      keterangan: _ringkasanSkor.isEmpty
          ? 'Apakah Anda akan berkunjung hari ini juga?'
          : '$_ringkasanSkor — lulus.\n'
              'Apakah Anda akan berkunjung hari ini juga?',
      anak: [
        _tombolMenu(Icons.event_available, 'Ya, hari ini',
            'Lanjut mengisi rencana kunjungan',
            () => _langkah != null ? _lanjut('rencana') : _mulai('plan_wanted')),
        _tombolMenu(Icons.schedule, 'Belum, lain hari',
            'Registrasi Anda tetap tersimpan; rencananya dibuat nanti',
            () => _langkah != null ? _lanjut('selesai') : _mulai('finish')),
      ],
    );
  }

  Widget _layarCheckin() {
    // Sopir TIDAK boleh ditawari check-in mandiri.
    //
    // Server mensyaratkan tanda tangan PETUGAS pada check-in transporter
    // (visit_rules.checkin_requires_officer_signature), sedangkan kiosk ini
    // mengirim check-in tanpa tanda tangan sama sekali. Jadi tombol itu
    // dijamin ditolak, selalu -- dan yang menerima penolakannya adalah sopir
    // yang tidak punya cara apa pun untuk memenuhinya. Yang ia butuhkan
    // bukan tombol, melainkan tahu bahwa gilirannya sedang ditunggu petugas.
    if (_peran == 'transporter') return _layarMenungguAntrian();

    return _bingkai(
      judul: 'Rencana kunjungan dibuat',
      keterangan: 'Hadapkan wajah Anda ke kamera, lalu tekan Check-in.',
      anak: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.panelAlt),
            ),
            clipBehavior: Clip.antiAlias,
            child: _kamera.frameBytes == null
                ? const Center(
                    child: Text('menunggu kamera…',
                        style: TextStyle(color: AppTheme.muted, fontSize: 15)))
                : Image.memory(_kamera.frameBytes!,
                    gaplessPlayback: true, fit: BoxFit.contain),
          ),
        ),
        if (_kamera.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_kamera.message,
                style: TextStyle(color: _kamera.color, fontSize: 15)),
          ),
        _tombolMenu(Icons.login, 'Check-in sekarang',
            'Wajah Anda akan dicocokkan dengan yang tadi didaftarkan',
            _mengirim
                ? null
                : () => _langkah != null
                    ? _checkinMandiri()
                    : _mulai('walkin_checkin')),
      ],
    );
  }

  /// Penutup alur sopir di kiosk: rencananya sudah tercatat, sisanya di
  /// tangan petugas.
  ///
  /// Bukan layar kosong bertuliskan "tunggu": yang paling sering ditanyakan
  /// sopir di titik ini adalah apakah datanya benar-benar masuk. Karena itu
  /// plat dan tujuan kedatangannya ditampilkan kembali sebagai bukti.
  Widget _layarMenungguAntrian() {
    final muat = _loadType == 'muat';
    return _bingkai(
      judul: 'Menunggu antrian',
      keterangan: 'Rencana Anda sudah tercatat. Tunggu panggilan petugas.',
      anak: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.panelAlt,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(muat ? Icons.upload_outlined : Icons.download_outlined,
                      size: 30, color: AppTheme.brandGold),
                  const SizedBox(width: 12),
                  Text(muat ? 'Muat' : 'Bongkar',
                      style: const TextStyle(
                          color: AppTheme.fg,
                          fontSize: 24,
                          fontWeight: FontWeight.w900)),
                ],
              ),
              const SizedBox(height: 12),
              if (_plat.text.trim().isNotEmpty)
                Text('Nomor polisi: ${_plat.text.trim()}',
                    style: const TextStyle(color: AppTheme.fg, fontSize: 18)),
              const SizedBox(height: 14),
              Text(
                muat
                    ? 'Petugas akan memeriksa wajah Anda lalu mengonfirmasi '
                        'masuk. Data barang dicatat petugas setelah truk masuk '
                        '— Anda tidak perlu mengisinya.'
                    : 'Petugas akan memeriksa wajah Anda lalu mengonfirmasi '
                        'masuk.',
                style: const TextStyle(color: AppTheme.muted, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Kiosk dipakai bergantian: tanpa jalan kembali, layar ini menyangkut
        // menampilkan data sopir tadi kepada orang berikutnya yang datang.
        SizedBox(
          height: 62,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _langkah = null),
            icon: const Icon(Icons.done, size: 22),
            label: const Text('Selesai', style: TextStyle(fontSize: 18)),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.fg),
          ),
        ),
      ],
    );
  }

  /// Tanda tangan tamu. Server menggerbang check-out dengan ini, jadi tanpa
  /// layar ini tamu tanpa HP tidak akan pernah bisa keluar.
  Widget _layarTtd() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Tanda tangan',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text(
              'Tanda tangani di kotak putih di bawah. Tanpa tanda tangan, '
              'check-out tidak bisa dilakukan.',
              style: TextStyle(color: AppTheme.muted, fontSize: 16, height: 1.5)),
          const SizedBox(height: 18),
          SizedBox(
            height: 260,
            child: SignaturePad(
              key: _padTtd,
              onChanged: (ada) => setState(() => _adaGoresan = ada),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    _padTtd.currentState?.clear();
                    setState(() => _adaGoresan = false);
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Ulangi', style: TextStyle(fontSize: 18)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.fg,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: (_adaGoresan && !_mengirim) ? _kirimTtd : null,
                  icon: const Icon(Icons.check),
                  label: Text(_mengirim ? 'Mengirim…' : 'Simpan tanda tangan',
                      style: const TextStyle(
                          fontSize: 19, fontWeight: FontWeight.w800)),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.brandGold,
                    foregroundColor: AppTheme.brandBlueDeep,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                  ),
                ),
              ),
            ],
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(_error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 15)),
          ],
        ],
      ),
    );
  }

  Future<void> _kirimTtd() async {
    final png = await _padTtd.currentState?.toPng();
    if (png == null) {
      setState(() => _error = 'Tanda tangan masih kosong.');
      return;
    }
    setState(() {
      _mengirim = true;
      _error = '';
    });
    try {
      final res = await _client.uploadSignature(
        visitId: _visitId,
        pngBase64: base64Encode(png),
      );
      final body = res['body'];
      // Amplop sidecar: ok=false berarti tidak sampai ke server sama sekali.
      // Kalau sampai, sukses dibaca dari body-nya -- dan body yang bukan Map
      // diperlakukan sebagai gagal, bukan lolos diam-diam.
      final sukses = res['ok'] == true && body is Map && body['success'] != false;
      if (!mounted) return;
      if (sukses) {
        await _tahapSelesai('signed', 'selesai');
      } else {
        setState(() => _error = (body is Map ? body['message'] : null)?.toString() ??
            res['error']?.toString() ??
            'Gagal menyimpan tanda tangan.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal menyimpan tanda tangan: $e');
    } finally {
      if (mounted) setState(() => _mengirim = false);
    }
  }

  Widget _bingkai({
    required String judul,
    required String keterangan,
    required List<Widget> anak,
    VoidCallback? kembali,
  }) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kembali != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: kembali,
                icon: const Icon(Icons.arrow_back, size: 20),
                label: const Text('Kembali', style: TextStyle(fontSize: 16)),
                style: TextButton.styleFrom(foregroundColor: AppTheme.muted),
              ),
            ),
          const SizedBox(height: 6),
          Text(judul,
              style: const TextStyle(
                  color: AppTheme.fg, fontSize: 32, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(keterangan,
              style: const TextStyle(
                  color: AppTheme.muted, fontSize: 16, height: 1.5)),
          const SizedBox(height: 26),
          ...anak,
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 15)),
          ],
        ],
      ),
    );
  }

  Widget _tombolMenu(
      IconData ikon, String judul, String keterangan, VoidCallback? onTap) {
    final aktif = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: aktif ? AppTheme.panelAlt : AppTheme.panel.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
            child: Row(
              children: [
                Icon(ikon,
                    size: 30, color: aktif ? AppTheme.brandGold : AppTheme.muted),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(judul,
                          style: TextStyle(
                              color: aktif ? AppTheme.fg : AppTheme.muted,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 2),
                      Text(keterangan,
                          style: const TextStyle(
                              color: AppTheme.muted, fontSize: 13)),
                    ],
                  ),
                ),
                if (aktif)
                  const Icon(Icons.chevron_right,
                      color: AppTheme.muted, size: 28),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _mulai(String aksi) async {
    try {
      await _channel.invokeMethod('menu', aksi);
    } catch (e) {
      if (mounted) setState(() => _error = 'Tidak bisa menghubungi petugas: $e');
    }
  }

  /// Kuis safety, dikerjakan tamu sendiri di layar ini.
  Widget _layarKuis() {
    if (_memuatSafety) {
      return _pesanBesar(Icons.hourglass_top, 'Memuat materi safety…', '');
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Safety Induction',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Kode tamu Anda: ${_visitorCode.isEmpty ? "—" : _visitorCode}',
              style: const TextStyle(color: AppTheme.brandGold, fontSize: 15)),
          const SizedBox(height: 16),
          if (_materi.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppTheme.panel.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_materi,
                  style: const TextStyle(
                      color: AppTheme.fg, fontSize: 15, height: 1.6)),
            ),
          const SizedBox(height: 22),
          for (var i = 0; i < _soal.length; i++) _kartuSoal(i, _soal[i]),
          if (_hasilKuis.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(_hasilKuis,
                style: const TextStyle(color: AppTheme.warnAmber, fontSize: 15)),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 66,
            child: FilledButton(
              onPressed: (_jawaban.length == _soal.length &&
                      _soal.isNotEmpty &&
                      !_mengirim)
                  ? _kirimKuis
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandGold,
                foregroundColor: AppTheme.brandBlueDeep,
              ),
              child: Text(_mengirim ? 'Mengirim…' : 'Kirim jawaban',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kartuSoal(int nomor, Map<String, dynamic> soal) {
    final id = (soal['id'] as num?)?.toInt() ?? 0;
    final opsi = soal['options'];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${nomor + 1}. ${soal['question'] ?? soal['text'] ?? ''}',
              style: const TextStyle(
                  color: AppTheme.fg, fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (opsi is List)
            // RadioGroup, bukan groupValue per-tile: yang lama sudah deprecated
            // sejak Flutter 3.32.
            RadioGroup<int>(
              groupValue: _jawaban[id],
              onChanged: (v) => setState(() {
                if (v != null) _jawaban[id] = v;
              }),
              child: Column(
                children: [
                  for (final o in opsi)
                    if (o is Map)
                      RadioListTile<int>(
                        value: (o['id'] as num?)?.toInt() ?? -1,
                        title: Text('${o['text'] ?? o['label'] ?? ''}',
                            style: const TextStyle(
                                color: AppTheme.fg, fontSize: 16)),
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppTheme.brandGold,
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Rencana kunjungan — tanpa ini, check-in di gerbang ditolak server dengan
  /// "Tidak ada rencana kunjungan untuk tamu ini".
  Widget _layarRencana() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              _peran == 'transporter'
                  ? 'Rencana Bongkar Muat'
                  : 'Rencana Kunjungan',
              style: const TextStyle(
                  color: AppTheme.fg, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          const Text(
              'Tanpa ini, wajah Anda tidak bisa dipakai check-in di gerbang.',
              style: TextStyle(color: AppTheme.muted, fontSize: 15)),
          const SizedBox(height: 20),
          // Pertanyaan PERTAMA untuk sopir, sebelum apa pun yang lain:
          // jawabannya menentukan sisa alurnya. Sopir bongkar akan diminta
          // mengisi data barang di layar berikutnya; sopir muat tidak,
          // karena ia datang dengan bak kosong dan barangnya baru ditentukan
          // di gudang -- petugas yang mencatatnya lewat E-Patrol. Ditanyakan
          // di tengah formulir seperti dulu, sopir sudah mengisi separuh
          // isian sebelum kiosk tahu alur mana yang sedang ia jalani.
          if (_peran == 'transporter') _pilihanMuatan(),
          // Sopir tidak menuju PIC melainkan area bongkar muat; yang wajib
          // baginya nomor polisi, karena itu penanda yang dicari petugas
          // patroli saat menelusuri kendaraan di area.
          if (_peran == 'transporter') ...[
            _isian('Nomor polisi kendaraan *', _plat),
            _isian('Jenis kendaraan (mis. tronton, wingbox)', _jenisKendaraan),
          ] else ...[
            _isian('PIC yang dituju *', _pic),
            _isian('Tujuan kunjungan', _keperluan),
          ],
          _isian('Nama perusahaan / instansi', _perusahaan),
          // Kategori tamu tidak berlaku untuk transporter -- sopir tidak
          // punya padanan konsep itu, sama seperti di konsol Semua Profil.
          if (_peran != 'transporter')
            _dropdown(
              _kategoriWajib ? 'Kategori tamu *' : 'Kategori tamu',
              _kategori.isEmpty ? null : _kategori,
              _kategoriPilihan,
              (v) => setState(() => _kategori = v ?? ''),
            ),
          _isian('Nama rombongan (pisahkan dengan koma)', _rombongan),
          if (_area.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: DropdownButtonFormField<int>(
                initialValue: _areaId,
                dropdownColor: AppTheme.panelAlt,
                style: const TextStyle(color: AppTheme.fg, fontSize: 20),
                decoration: const InputDecoration(
                  labelText: 'Area yang dituju',
                  labelStyle: TextStyle(color: AppTheme.muted, fontSize: 16),
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                ),
                items: [
                  for (final a in _area)
                    DropdownMenuItem(
                      value: (a['id'] as num?)?.toInt(),
                      child: Text('${a['name'] ?? ''}'),
                    ),
                ],
                onChanged: (v) => setState(() => _areaId = v),
              ),
            ),
          // Area bongkar/muat bukan lantai produksi, jadi pertanyaan ini dan
          // pernyataan sehat yang menyertainya tidak relevan bagi sopir --
          // sama seperti di app Android.
          if (_peran != 'transporter') ...[
            SwitchListTile(
              value: _masukProduksi,
              onChanged: (v) => setState(() => _masukProduksi = v),
              title: const Text('Masuk area produksi',
                  style: TextStyle(color: AppTheme.fg, fontSize: 18)),
            ),
            if (_masukProduksi)
              SwitchListTile(
                value: _setujuKesehatan,
                onChanged: (v) => setState(() => _setujuKesehatan = v),
                title: const Text('Saya menyatakan sedang sehat',
                    style: TextStyle(color: AppTheme.fg, fontSize: 18)),
                subtitle: const Text('Wajib untuk masuk area produksi.',
                    style: TextStyle(color: AppTheme.muted, fontSize: 13)),
              ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            height: 66,
            child: FilledButton(
              onPressed: (_mengirim || !_rencanaSiap) ? null : _kirimRencana,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandGold,
                foregroundColor: AppTheme.brandBlueDeep,
              ),
              child: Text(
                  _mengirim
                      ? 'Mengirim…'
                      : (_peran == 'transporter'
                          ? 'Lanjut — data muatan'
                          : 'Kirim rencana kunjungan'),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(_error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 15)),
          ],
        ],
      ),
    );
  }

  Widget _pesanBesar(IconData icon, String judul, String isi, {Color? tone}) {
    final warna = tone ?? AppTheme.brandGold;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 96, color: warna),
            const SizedBox(height: 28),
            Text(judul,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.fg,
                    fontSize: 34,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            Text(isi,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppTheme.muted, fontSize: 20, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _selesai() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, size: 96, color: AppTheme.okGreen),
            const SizedBox(height: 24),
            const Text('Terima kasih, Anda sudah terdaftar',
                style: TextStyle(
                    color: AppTheme.fg,
                    fontSize: 32,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 24),
            const Text('Kode tamu Anda',
                style: TextStyle(color: AppTheme.muted, fontSize: 18)),
            const SizedBox(height: 8),
            // Kode ini satu-satunya pegangan tamu yang tidak punya HP, jadi
            // dibuat sebesar mungkin supaya bisa dibaca dan dicatat.
            SelectableText(
              _visitorCode.isEmpty ? '—' : _visitorCode,
              style: const TextStyle(
                color: AppTheme.brandGold,
                fontSize: 56,
                fontWeight: FontWeight.w900,
                letterSpacing: 3,
              ),
            ),
            const SizedBox(height: 20),
            const Text('Sebutkan kode ini kepada petugas bila diperlukan.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.muted, fontSize: 18)),
            const SizedBox(height: 28),
            SizedBox(
              height: 62,
              child: FilledButton.icon(
                onPressed: () {
                  setState(() => _layar = 'awal');
                  _mulai('reset');
                },
                icon: const Icon(Icons.home_outlined),
                label: const Text('Selesai — kembali ke menu',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.panelAlt,
                  foregroundColor: AppTheme.fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Formulir registrasi — disamakan dengan app Android (`register_screen`).
  ///
  /// Android hanya meminta nama, nomor HP, dan alamat lengkap di tahap ini;
  /// sekolah/jurusan hanya untuk magang. Kategori tamu, perusahaan, dan tujuan
  /// kunjungan tidak dikumpulkan di sini — semuanya milik **rencana
  /// kunjungan**, karena satu orang bisa datang berkali-kali dengan keperluan
  /// berbeda. Mengumpulkannya saat registrasi berarti menyimpan jawaban satu
  /// kunjungan sebagai sifat permanen orangnya.
  ///
  /// Nomor HP sengaja tidak diminta: justru itu yang membedakan tamu ini
  /// (`walk_in`), dan server mencoret "Nomor HP" dari daftar wajibnya.
  Widget _formulir() {
    final magang = _peran == 'magang';
    final sopir = _peran == 'transporter';
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 32, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Data diri',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 30, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          const Text('Alamat lengkap wajib diisi sampai desa/kelurahan.',
              style: TextStyle(color: AppTheme.muted, fontSize: 16)),
          const SizedBox(height: 24),
          _isian('Nama lengkap *', _nama),
          if (magang) ...[
            _isian('Sekolah / institusi *', _perusahaan),
            _isian('Jurusan *', _keperluan),
          ],
          if (sopir) ...[
            _isian('Perusahaan ekspedisi *', _perusahaan),
            _isian('Nomor SIM *', _sim),
            _tanggalSim(),
          ],
          const SizedBox(height: 8),
          const Text('Alamat',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          _wilayahDropdown('Provinsi *', 'province'),
          _wilayahDropdown('Kabupaten/Kota *', 'regency'),
          _wilayahDropdown('Kecamatan *', 'district'),
          _wilayahDropdown('Desa/Kelurahan *', 'village'),
          _isian('Detail alamat (jalan, nomor, RT/RW) *', _alamatDetail),
          const SizedBox(height: 28),
          SizedBox(
            height: 72,
            child: FilledButton.icon(
              onPressed: _bisaKirim ? _kirim : null,
              icon: const Icon(Icons.arrow_forward, size: 28),
              label: Text(
                  _mengirim
                      ? 'Mengirim…'
                      : (_langkah == 'data' ? 'Lanjut — foto wajah' : 'Selesai'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandGold,
                foregroundColor: AppTheme.brandBlueDeep,
              ),
            ),
          ),
          if (!_alamatLengkap) ...[
            const SizedBox(height: 12),
            const Text(
                'Alamat belum lengkap — server menyusun baris alamat dari kode '
                'wilayah, jadi keempatnya harus dipilih.',
                style: TextStyle(color: AppTheme.warnAmber, fontSize: 14)),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(_error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 16)),
          ],
        ],
      ),
    );
  }

  String _tanggalIso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Widget _tanggalSim() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton.icon(
        onPressed: () async {
          final kini = DateTime.now();
          final pilih = await showDatePicker(
            context: context,
            initialDate: _simBerlaku ?? kini,
            // Boleh memilih tanggal yang sudah lewat: SIM kedaluwarsa itu
            // keadaan nyata yang harus tercatat apa adanya, bukan sesuatu yang
            // dicegah dengan melarang mengetiknya.
            firstDate: DateTime(kini.year - 10),
            lastDate: DateTime(kini.year + 15),
          );
          if (pilih != null) setState(() => _simBerlaku = pilih);
        },
        icon: const Icon(Icons.badge_outlined),
        label: Text(
          _simBerlaku == null
              ? 'Tanggal kadaluarsa SIM *'
              : 'SIM berlaku s/d ${_tanggalIso(_simBerlaku!)}'
                  '${_simBerlaku!.isBefore(DateTime.now()) ? '  (sudah lewat)' : ''}',
          style: const TextStyle(fontSize: 18),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _simBerlaku != null &&
                  _simBerlaku!.isBefore(DateTime.now())
              ? AppTheme.warnAmber
              : AppTheme.fg,
          padding: const EdgeInsets.symmetric(vertical: 20),
        ),
      ),
    );
  }

  /// Sama dengan `AddressSelection.isComplete` di app Android: keempat tingkat
  /// dipilih dan detailnya terisi.
  bool get _alamatLengkap =>
      _terpilih['province'] != null &&
      _terpilih['regency'] != null &&
      _terpilih['district'] != null &&
      _terpilih['village'] != null &&
      _alamatDetail.text.trim().isNotEmpty;

  /// Bongkar atau muat -- wajib untuk transporter, sama seperti app Android.
  Widget _pilihanMuatan() {
    Widget tombol(String nilai, String label, IconData ikon) {
      final aktif = _loadType == nilai;
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _loadType = nilai),
            icon: Icon(ikon, size: 22),
            label: Text(label, style: const TextStyle(fontSize: 18)),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor:
                  aktif ? AppTheme.brandGold.withValues(alpha: 0.18) : null,
              foregroundColor: aktif ? AppTheme.brandGold : AppTheme.fg,
              side: BorderSide(
                color: aktif ? AppTheme.brandGold : AppTheme.muted,
                width: aktif ? 2 : 1,
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tujuan kedatangan *',
              style: TextStyle(color: AppTheme.muted, fontSize: 16)),
          const SizedBox(height: 8),
          Row(
            children: [
              tombol('bongkar', 'Bongkar', Icons.download_outlined),
              tombol('muat', 'Muat', Icons.upload_outlined),
            ],
          ),
        ],
      ),
    );
  }

  // Ukuran sengaja besar di seluruh formulir: ini layar sentuh yang dipakai
  // sambil berdiri di meja pos, bukan layar yang dipelototi dari kursi.
  Widget _isian(String label, TextEditingController ctl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: ctl,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(color: AppTheme.fg, fontSize: 20),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 16),
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        ),
      ),
    );
  }

  Widget _dropdown(String label, String? nilai, List<String> pilihan,
      ValueChanged<String?> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: pilihan.contains(nilai) ? nilai : null,
        dropdownColor: AppTheme.panelAlt,
        style: const TextStyle(color: AppTheme.fg, fontSize: 20),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 16),
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        ),
        items: [
          for (final p in pilihan)
            DropdownMenuItem(value: p, child: Text(p)),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _wilayahDropdown(String label, String tingkat) {
    final daftar = _wilayah[tingkat] ?? const <Region>[];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DropdownButtonFormField<String>(
        initialValue: _terpilih[tingkat]?.code,
        dropdownColor: AppTheme.panelAlt,
        style: const TextStyle(color: AppTheme.fg, fontSize: 20),
        decoration: InputDecoration(
          labelText: daftar.isEmpty ? '$label (pilih tingkat di atasnya dulu)' : label,
          labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 16),
          border: const OutlineInputBorder(),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        ),
        items: [
          for (final r in daftar)
            DropdownMenuItem(value: r.code, child: Text(r.name)),
        ],
        onChanged: daftar.isEmpty
            ? null
            : (code) => _pilihWilayah(
                  tingkat,
                  daftar.where((r) => r.code == code).firstOrNull,
                ),
      ),
    );
  }

}
