/// Jendela pose untuk pengambilan tiga sudut wajah.
///
/// Nilainya disamakan dengan app Android (`multi_angle_capture_screen.dart`,
/// `_kSteps`). Itu bukan kerapian belaka: embedding yang tersimpan dari POS
/// dan dari HP harus sebanding, dan kalau jendelanya berbeda, sudut "kiri"
/// dari POS bisa jauh lebih frontal daripada "kiri" dari HP — pencocokan lalu
/// meleset tanpa satu pun pesan galat yang menunjuk ke sini.
///
/// Longgar dengan sengaja: cukup menyimpang dari frontal supaya embedding-nya
/// benar-benar memberi tampak baru, tapi masih bisa dicapai tanpa memutar
/// leher berlebihan. Sumbu tegak lurusnya dibatasi longgar juga, supaya
/// menengok ke kiri tidak gagal hanya karena tamu ikut menunduk sedikit.
class PoseWindow {
  PoseWindow._();

  /// Arah yaw bergantung pada pencerminan kamera. Kalau di suatu perangkat
  /// kiri dan kanan tertukar, balik konstanta ini — tidak ada tempat lain yang
  /// perlu diubah. (Android memakai trik yang sama lewat `_kSignYaw`.)
  static const double signYaw = 1.0;

  /// Berapa pembacaan berturut-turut pose harus bertahan sebelum foto diambil
  /// sendiri. Satu pembacaan ~90 ms di POS, jadi 6 kali ≈ setengah detik:
  /// cukup untuk menyaring pose yang cuma terlewat, tidak sampai melelahkan
  /// untuk ditahan. Android memakai 6 frame kamera untuk alasan yang sama.
  static const int stableReadings = 6;

  /// Urutan pengambilan; `key` juga label sudut yang dikirim ke server.
  static const steps = <(String, String, String)>[
    ('frontal', 'Frontal', 'Tamu menghadap lurus ke kamera.'),
    ('left', 'Hadap kiri', 'Tamu menengok perlahan ke KIRI.'),
    ('right', 'Hadap kanan', 'Tamu menengok perlahan ke KANAN.'),
  ];

  /// Apakah pose sekarang masuk jendela sudut [angle].
  static bool inTarget(String angle, double yaw, double pitch) =>
      switch (angle) {
        'frontal' => yaw.abs() < 12 && pitch.abs() < 12,
        'left' => (signYaw * yaw) >= 15 && pitch.abs() < 28,
        'right' => (signYaw * yaw) <= -15 && pitch.abs() < 28,
        _ => false,
      };
}
