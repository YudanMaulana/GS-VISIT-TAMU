import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Tahapan pendaftaran tamu tanpa HP, dari sisi jendela operator.
enum WalkInPhase {
  /// Belum ada sesi berjalan.
  idle,

  /// Operator sedang mengambil tiga sudut wajah lewat kamera pos.
  capturing,

  /// Layar sentuh sudah diserahkan; tamu mengisi datanya sendiri.
  guestFilling,

  /// Data tamu sudah masuk, sedang dikirim ke server.
  submitting,

  /// Terdaftar. Tamu lanjut mengerjakan kuis safety di layar sentuh.
  ///
  /// Bukan tahap opsional: rencana kunjungan membawa `safety_version_agreed`,
  /// dan tanpa itu data tamu tanpa HP berbeda dari tamu ber-HP yang wajib
  /// lulus kuis sekali per akun.
  safety,

  /// Kuis lewat; tamu ditanya apakah mau berkunjung hari ini juga.
  ///
  /// Ditanya, bukan diasumsikan: sebagian tamu mendaftar untuk kunjungan lain
  /// hari, dan membuatkan rencana hari ini untuk mereka berarti rencana yang
  /// harus dibatalkan orang lain nanti.
  askPlan,

  /// Tamu mengisi rencana kunjungan (PIC, area, produksi).
  ///
  /// Tanpa rencana berstatus 'planned', check-in di gerbang ditolak dengan
  /// "Tidak ada rencana kunjungan untuk tamu ini" -- dan tamu ini justru yang
  /// tidak punya aplikasi untuk membuatnya sendiri.
  plan,

  /// Rencana terbuat; tamu diarahkan menghadap kamera untuk check-in.
  checkin,

  /// Sudah check-in; tamu menandatangani di layar sentuh.
  ///
  /// Bukan tahap kosmetik: server menggerbang check-out dengan tanda tangan
  /// tamu, jadi tanpa ini tamu tanpa HP tidak akan pernah bisa keluar.
  signature,

  /// Selesai untuk kunjungan ini.
  done,

  /// Gagal; [WalkInSession.error] menyimpan pesan dari server apa adanya.
  failed,
}

/// Satu sesi pendaftaran tamu tanpa HP, dipakai bersama oleh jendela operator
/// dan jendela kiosk.
///
/// Kenapa singleton dan bukan state di dalam halaman: jendela kiosk bicara ke
/// jendela utama lewat [WindowMethodChannel], dan penerimanya dipasang sekali
/// di HomePage — bukan di halaman konsol yang bisa ditutup-buka. Kalau
/// state-nya ikut halaman, data yang tamu ketik akan hilang begitu operator
/// pindah menu.
///
/// **Foto tidak pernah menyeberang ke jendela kiosk.** Yang menyeberang hanya
/// isian formulir, satu arah: kiosk -> jendela utama. Kiosk tetap terminal
/// bodoh yang tidak memegang wajah siapa pun.
class WalkInSession extends ChangeNotifier {
  WalkInSession._();

  static final WalkInSession instance = WalkInSession._();

  WalkInPhase phase = WalkInPhase.idle;

  /// Tiga sudut wajah sebagai base64, diisi jendela operator dari hasil
  /// `/capture` yang sudah lolos penjagaan ketajaman.
  String? frontalB64;
  String? leftB64;
  String? rightB64;

  /// Hasil decode-nya, disimpan sekali di sini.
  ///
  /// Ini bukan sekadar penghematan: men-decode base64 di dalam `build` berarti
  /// ~1 MB per sudut dikerjakan ulang tiap rebuild, dan tiap hasilnya objek
  /// baru — sehingga cache gambar Flutter tidak pernah kena dan gambarnya
  /// di-decode ulang lagi saat dilukis. Dengan tiga sudut terambil, UI-nya
  /// tersendat dan pratinjau kamera ikut berkedip. Objek yang sama dipakai
  /// terus, jadi Flutter mengenalinya sebagai gambar yang itu-itu juga.
  final Map<String, Uint8List> _bytes = {};

  /// Foto satu sudut untuk ditampilkan; `null` kalau sudut itu belum diambil.
  Uint8List? bytesFor(String angle) => _bytes[angle];

  /// Isian dari tamu di layar sentuh, siap dikirim sebagai field multipart.
  Map<String, String> form = {};

  String visitorCode = '';
  int visitorId = 0;

  /// Keadaan tamu yang baru dikenali di kiosk — dipakai untuk memutuskan
  /// tombol check-in/check-out mana yang boleh hidup. Diisi dari server, bukan
  /// disimpulkan GUI: aturan check-out digerbang tanda tangan tamu di sana.
  String guestName = '';

  /// Id kunjungan hasil check-in — dibutuhkan untuk mengunggah tanda tangan.
  int visitId = 0;
  bool hasPlan = false;
  String planStatus = '';
  bool signed = false;
  String error = '';

  /// Berapa embedding yang benar-benar tersimpan di server. Diperiksa terpisah
  /// dari sukses: tiga sudut yang gagal terkirim sebagai field berulang tetap
  /// dibalas sukses, hanya dengan satu embedding.
  int embeddingsSaved = 0;

  bool get anglesComplete =>
      frontalB64 != null && leftB64 != null && rightB64 != null;

  /// Sudut yang belum diambil, urut sesuai urutan pengambilan yang disarankan.
  List<String> get missingAngles => [
        if (frontalB64 == null) 'frontal',
        if (leftB64 == null) 'kiri',
        if (rightB64 == null) 'kanan',
      ];

  void start() {
    phase = WalkInPhase.capturing;
    _bytes.clear();
    frontalB64 = null;
    leftB64 = null;
    rightB64 = null;
    form = {};
    visitorCode = '';
    visitorId = 0;
    guestName = '';
    hasPlan = false;
    planStatus = '';
    signed = false;
    error = '';
    embeddingsSaved = 0;
    notifyListeners();
  }

  void setAngle(String angle, String b64) {
    switch (angle) {
      case 'frontal':
        frontalB64 = b64;
      case 'left':
        leftB64 = b64;
      case 'right':
        rightB64 = b64;
      default:
        return;
    }
    try {
      _bytes[angle] = base64Decode(b64);
    } on FormatException {
      // Foto yang tidak bisa di-decode tidak boleh menggagalkan sesi: yang
      // dikirim ke server tetap base64 aslinya, ini hanya untuk pratinjau.
      _bytes.remove(angle);
    }
    notifyListeners();
  }

  /// Operator menyerahkan layar sentuh ke tamu. Hanya boleh setelah ketiga
  /// sudut ada: menyerahkan lebih awal berarti tamu mengisi formulir untuk
  /// wajah yang belum tentu jadi terambil.
  bool handOverToGuest() {
    if (!anglesComplete) return false;
    phase = WalkInPhase.guestFilling;
    notifyListeners();
    return true;
  }

  /// Dipanggil dari jendela kiosk lewat channel.
  void submitFromGuest(Map<String, String> filled) {
    form = filled;
    phase = WalkInPhase.submitting;
    notifyListeners();
  }

  /// Pendaftaran berhasil. Tamu belum selesai -- ia lanjut ke kuis safety.
  void registered({
    required String code,
    required int id,
    required int embeddings,
  }) {
    visitorCode = code;
    visitorId = id;
    embeddingsSaved = embeddings;
    phase = WalkInPhase.safety;
    notifyListeners();
  }

  /// Tamu yang wajahnya sudah dikenali: lewati pendaftaran, langsung ke
  /// rencana kunjungan. Mendaftar ulang wajah yang sama hanya menambah
  /// identitas kedua untuk orang yang sama.
  /// Hasil pengenalan wajah di kiosk beserta keadaan kunjungannya hari ini.
  void guestIdentified({
    required String code,
    required int id,
    required String name,
    required bool hasPlan,
    required String status,
    required bool signed,
  }) {
    visitorCode = code;
    visitorId = id;
    guestName = name;
    this.hasPlan = hasPlan;
    planStatus = status;
    this.signed = signed;
    notifyListeners();
  }

  void existingGuest({required String code, required int id}) {
    visitorCode = code;
    visitorId = id;
    phase = WalkInPhase.plan;
    notifyListeners();
  }

  void safetyPassed() {
    phase = WalkInPhase.askPlan;
    notifyListeners();
  }

  void wantsPlanToday() {
    phase = WalkInPhase.plan;
    notifyListeners();
  }

  void planCreated() {
    phase = WalkInPhase.checkin;
    notifyListeners();
  }

  void checkedIn(int id) {
    visitId = id;
    phase = WalkInPhase.signature;
    notifyListeners();
  }

  void signatureUploaded() {
    phase = WalkInPhase.done;
    notifyListeners();
  }

  void finished() {
    phase = WalkInPhase.done;
    notifyListeners();
  }

  void failed(String message) {
    error = message;
    phase = WalkInPhase.failed;
    notifyListeners();
  }

  void reset() {
    phase = WalkInPhase.idle;
    _bytes.clear();
    frontalB64 = null;
    leftB64 = null;
    rightB64 = null;
    form = {};
    visitorCode = '';
    visitorId = 0;
    error = '';
    embeddingsSaved = 0;
    notifyListeners();
  }

  /// Ringkasan untuk jendela kiosk. Sengaja tidak memuat foto maupun apa pun
  /// yang tidak dibutuhkan layar tamu.
  Map<String, dynamic> kioskSnapshot() => {
        'phase': phase.name,
        'visitor_code': visitorCode,
        // Dibutuhkan kiosk untuk mengirim jawaban kuis dan membuat rencana
        // atas nama tamu ini. Bukan rahasia: id ini sudah tercetak di kartu
        // tamu, dan setiap panggilannya tetap lewat sidecar yang memegang
        // kredensialnya.
        'visitor_id': visitorId,
        'visit_id': visitId,
        'guest_name': guestName,
        'has_plan': hasPlan,
        'plan_status': planStatus,
        'signed': signed,
        'error': error,
      };
}
