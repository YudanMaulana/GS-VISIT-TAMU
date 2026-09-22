/// Gerbang konsol Kelola Data.
///
/// POS ini kios yang berdiri di meja depan, jadi konsolnya (cari wajah, ubah
/// data tamu, reset data) tidak boleh terjangkau oleh siapa pun yang lewat.
///
/// **Keputusan "boleh masuk atau tidak" ada di server**, di tabel
/// `admin_users` — bukan di sini dan bukan di `AppConfig`. Gerbang yang
/// seluruhnya di klien hanya menahan orang yang membuka aplikasinya: ia tidak
/// menahan apa pun yang bicara langsung ke server, dan kata sandinya ikut
/// terbagi ke setiap salinan aplikasi yang terpasang.
///
/// Yang tinggal di sini cuma satu pertanyaan yang tidak bisa dijawab server:
/// **apakah orangnya masih berdiri di depan kios.** Token menjawab "siapa";
/// kunci diam di bawah menjawab "masih di sini atau tidak". Kios yang
/// ditinggal operator dan tetap terbuka 12 jam adalah kios yang terbuka untuk
/// siapa pun yang lewat.
class AdminSession {
  /// Berapa lama sesi bertahan tanpa aktivitas sebelum mengunci sendiri.
  static const Duration lifetime = Duration(minutes: 15);

  DateTime? _unlockedAt;
  String _email = '';

  bool get isUnlocked {
    final at = _unlockedAt;
    if (at == null) return false;
    if (DateTime.now().difference(at) > lifetime) {
      _unlockedAt = null; // kedaluwarsa
      _email = '';
      return false;
    }
    return true;
  }

  /// Email admin yang sedang masuk, untuk ditampilkan di konsol. Kosong
  /// berarti terkunci.
  String get email => isUnlocked ? _email : '';

  /// Buka sesi setelah **server** menyatakan kredensialnya sah (login
  /// email+kata sandi, atau login Google admin).
  void unlockFromServer({required String email}) {
    _email = email.trim();
    _unlockedAt = DateTime.now();
  }

  /// Buka sesi dari sesi admin yang tersimpan di sidecar dan sudah
  /// diverifikasi ke server lewat `/admin_me`.
  ///
  /// Sesi tersimpan membebaskan operator dari mengulang login tiap app dibuka;
  /// ia bukan izin masuk dengan sendirinya — yang menyatakan token itu masih
  /// sah tetap server.
  bool unlockFromStoredSession(String? verifiedEmail) {
    final email = verifiedEmail?.trim() ?? '';
    if (email.isEmpty) return false;
    unlockFromServer(email: email);
    return true;
  }

  /// Geser tenggat diam ke depan — dipanggil pada aktivitas konsol yang
  /// berarti, supaya sesi yang sedang dipakai tidak mengunci di tengah kerja.
  void touch() {
    if (_unlockedAt != null) _unlockedAt = DateTime.now();
  }

  void lock() {
    _unlockedAt = null;
    _email = '';
  }
}
