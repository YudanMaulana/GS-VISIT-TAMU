import 'package:flutter/material.dart';

import '../config.dart';
import '../models.dart';
import '../pose_window.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../walk_in_session.dart';
import '../widgets/console_ui.dart';

/// Sisi operator dari pendaftaran tamu tanpa HP.
///
/// Operator mengerjakan yang butuh kamera pos — tiga sudut wajah — lalu
/// menyerahkan layar sentuh kedua supaya tamu mengetik datanya sendiri. Yang
/// mengetik tetap orangnya sendiri: salah dengar di meja pos tidak berubah
/// menjadi salah data yang menempel selamanya di kartu tamu.
///
/// Pengambilan wajahnya memakai jalur `/capture` yang sudah ada, berikut
/// penjagaan ketajamannya. Foto yang lolos ke server tanpa penjagaan itu akan
/// ditolak server setelah operator terlanjur menunggu, atau lebih buruk: masuk
/// sebagai embedding buruk yang membuat pencocokan meleset berbulan kemudian.
class WalkInPage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;

  /// Frame kamera terbaru, dipoles oleh konsol. Dipakai untuk pratinjau
  /// langsung supaya operator melihat apa yang akan terambil sebelum menekan
  /// tombol — memotret tanpa melihat layar itu menebak.
  final DetectionState state;

  /// Membuka (atau memunculkan) jendela kiosk di layar sentuh kedua.
  final Future<void> Function() onOpenKiosk;

  const WalkInPage({
    super.key,
    required this.client,
    required this.config,
    required this.state,
    required this.onOpenKiosk,
  });

  @override
  State<WalkInPage> createState() => _WalkInPageState();
}

class _WalkInPageState extends State<WalkInPage> {
  final _session = WalkInSession.instance;
  bool _busy = false;
  String _pesan = '';
  bool _sidecarLama = false;

  /// Ambil sendiri begitu pose tepat, seperti di app Android. Operator tidak
  /// perlu memilih saat yang pas sambil juga memandu tamu -- dua pekerjaan
  /// yang saling mengganggu kalau dikerjakan satu orang.
  bool _autoAmbil = true;
  int _stabil = 0;
  String? _sudutTerkunci; // sudut yang sedang dikejar auto-ambil
  DateTime _jedaSampai = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSession);
    _periksaSidecar();
  }

  @override
  void dispose() {
    _session.removeListener(_onSession);
    super.dispose();
  }

  Future<void> _periksaSidecar() async {
    final client = widget.client;
    if (client == null) return;
    final ok = await client.supportsWalkIn();
    if (mounted) setState(() => _sidecarLama = !ok);
  }

  @override
  void didUpdateWidget(WalkInPage old) {
    super.didUpdateWidget(old);
    // State kamera datang dari konsol sebagai widget baru tiap polling; di
    // situlah pose diperiksa, bukan di timer sendiri -- satu sumber frame,
    // satu irama.
    _periksaAutoAmbil();
  }

  /// Sudut berikutnya yang belum terambil, urut frontal -> kiri -> kanan.
  String? get _sudutBerikutnya {
    for (final (key, _, _) in PoseWindow.steps) {
      final sudah = switch (key) {
        'frontal' => _session.frontalB64 != null,
        'left' => _session.leftB64 != null,
        _ => _session.rightB64 != null,
      };
      if (!sudah) return key;
    }
    return null;
  }

  void _periksaAutoAmbil() {
    if (!_autoAmbil || _busy || _sidecarLama) return;
    if (_session.phase != WalkInPhase.capturing) return;
    if (DateTime.now().isBefore(_jedaSampai)) return;

    final sudut = _sudutBerikutnya;
    final yaw = widget.state.yaw;
    final pitch = widget.state.pitch;
    if (sudut == null || yaw == null || pitch == null || widget.state.faceCount < 1) {
      if (_stabil != 0) setState(() => _stabil = 0);
      return;
    }
    if (sudut != _sudutTerkunci) {
      _sudutTerkunci = sudut;
      _stabil = 0;
    }
    if (!PoseWindow.inTarget(sudut, yaw, pitch)) {
      if (_stabil != 0) setState(() => _stabil = 0);
      return;
    }
    setState(() => _stabil++);
    if (_stabil >= PoseWindow.stableReadings) {
      _stabil = 0;
      // Jeda sesudahnya supaya tamu sempat berpindah pose dan sudut
      // berikutnya tidak ikut terambil dari pose yang sama.
      _jedaSampai = DateTime.now().add(const Duration(milliseconds: 1200));
      _ambil(sudut);
    }
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _ambil(String angle) async {
    final client = widget.client;
    if (client == null) {
      setState(() => _pesan = 'Sidecar belum berjalan.');
      return;
    }
    setState(() {
      _busy = true;
      _pesan = '';
    });
    try {
      final cap = await client.capture();
      if (!cap.ok) {
        setState(() => _pesan = 'Gagal mengambil foto.');
        return;
      }
      // Penjagaan yang sama dengan check-in: foto buram ditolak di sini,
      // bukan setelah perjalanan bolak-balik ke server.
      if (!cap.sharp) {
        setState(() => _pesan =
            'Foto kurang tajam (var ${cap.variance}). Minta tamu diam sejenak, lalu ulangi.');
        return;
      }
      final still = await client.lastStill();
      if (still['stale_sidecar'] == true) {
        setState(() {
          _sidecarLama = true;
          _pesan = '';
        });
        return;
      }
      final b64 = still['jpeg_b64'];
      if (still['ok'] != true || b64 is! String || b64.isEmpty) {
        setState(() => _pesan = 'Foto tidak terbaca dari sidecar.');
        return;
      }
      _session.setAngle(angle, b64);
      setState(() => _pesan = '');
    } catch (e) {
      setState(() => _pesan = 'Gagal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _serahkan() async {
    if (!_session.handOverToGuest()) {
      setState(() => _pesan = 'Ketiga sudut wajah harus lengkap dulu.');
      return;
    }
    await widget.onOpenKiosk();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _session.phase;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Second Monitor',
            subtitle: 'Layar sentuh yang diserahkan ke tamu. Tamu mengerjakan '
                'sendiri; halaman ini untuk membukanya dan membantu bila perlu.',
            icon: Icons.personal_video_outlined,
            actions: [
              FilledButton.icon(
                onPressed: () => widget.onOpenKiosk(),
                icon: const Icon(Icons.tablet_android, size: 16),
                label: const Text('Buka layar tamu'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: AppTheme.brandBlueDeep,
                ),
              ),
              const SizedBox(width: 8),
              if (phase != WalkInPhase.idle)
                TextButton.icon(
                  onPressed: _busy ? null : _session.reset,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Mulai ulang'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_sidecarLama) ...[
                    _peringatanSidecarLama(),
                    const SizedBox(height: 14),
                  ],
                  if (phase == WalkInPhase.idle) _mulai() else _langkahWajah(),
                  const SizedBox(height: 14),
                  if (phase != WalkInPhase.idle) _langkahTamu(),
                  if (_pesan.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(_pesan,
                        style: const TextStyle(
                            color: AppTheme.warnAmber, fontSize: 12.5)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Versi Python yang berjalan lebih tua daripada GUI ini. Disebut apa
  /// adanya beserta cara memperbaikinya: gejalanya (foto tidak terbaca, lalu
  /// pendaftaran gagal) tidak menunjuk ke sebabnya sama sekali.
  Widget _peringatanSidecarLama() {
    return _kartu(
      tone: AppTheme.badRed,
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined, color: AppTheme.badRed, size: 18),
              SizedBox(width: 8),
              Text('Sidecar yang berjalan versi lama',
                  style: TextStyle(
                      color: AppTheme.fg,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800)),
            ],
          ),
          SizedBox(height: 8),
          Text(
            'Proses Python yang dipakai app ini belum punya rute pendaftaran '
            'tamu tanpa HP, jadi foto tidak akan bisa diambil maupun dikirim. '
            'Biasanya karena Pengaturan menunjuk salinan detector lain — '
            'misalnya folder hasil ekstrak paket rilis, bukan yang di repo.\n\n'
            'Perbaiki di Pengaturan: arahkan "Python interpreter" dan '
            '"sidecar.py path" ke salinan yang sedang dikembangkan, lalu '
            'Save & restart.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _mulai() {
    return _kartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tamu mengerjakan sendiri di layar sentuh: pilih peran, isi data, '
            'ambil tiga sudut wajah, safety induction, lalu rencana kunjungan. '
            'Halaman ini tidak perlu disentuh untuk alur itu.\n\n'
            'Tombol di bawah hanya untuk tamu yang tidak bisa memakai layar '
            'sentuh — petugas mengambilkan wajahnya dari kamera pos, lalu '
            'menyerahkan layar untuk pengisian datanya.',
            style: TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.5),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _session.start,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Bantu ambil wajah (tamu tak bisa pakai layar sentuh)'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.brandGold,
                foregroundColor: AppTheme.brandBlueDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _langkahWajah() {
    return _kartu(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('1. Tiga sudut wajah',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Ambil satu per satu. Sudut yang kurang bagus bisa diulang sendiri '
            'tanpa mengulang ketiganya.',
            style: TextStyle(color: AppTheme.muted, fontSize: 11.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          _pratinjau(),
          const SizedBox(height: 14),
          for (final (key, judul, petunjuk) in PoseWindow.steps) _barisSudut(key, judul, petunjuk),
        ],
      ),
    );
  }

  /// Pratinjau langsung + panduan dari sidecar (pesan, garis mutu, dan hitungan
  /// frame bagus berturut-turut) — bahan yang sama dengan yang dipakai layar
  /// POS, bukan jalur kamera baru.
  ///
  /// Panduannya sengaja **tidak** mengunci tombol Ambil. Penilaian "bagus"
  /// dari sidecar mengandaikan wajah menghadap lurus; untuk sudut kiri dan
  /// kanan kepala memang harus diputar, jadi mengunci tombol pada frame
  /// "bagus" akan membuat dua sudut itu mustahil diambil. Ketajaman tetap
  /// diperiksa setelah pengambilan, dan itu berlaku untuk ketiga sudut.
  Widget _pratinjau() {
    final s = widget.state;
    final bytes = s.frameBytes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.panelAlt),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes == null
                ? Center(
                    child: Text(
                      s.error?.isNotEmpty == true
                          ? s.error!
                          : (widget.client == null
                              ? 'Sidecar belum berjalan.'
                              : 'menunggu kamera…'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                    ),
                  )
                : Image.memory(bytes, gaplessPlayback: true, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 8),
        _panduanSudut(),
        const SizedBox(height: 6),
        Row(
          children: [
            Icon(s.good ? Icons.check_circle : Icons.info_outline,
                size: 15, color: s.color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.message.isEmpty ? 'Arahkan wajah tamu ke kamera.' : s.message,
                style: TextStyle(color: s.color, fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            if (s.faceCount > 1)
              const Text('Lebih dari satu wajah terlihat',
                  style: TextStyle(color: AppTheme.warnAmber, fontSize: 11.5)),
          ],
        ),
      ],
    );
  }

  /// Baris panduan untuk sudut yang sedang dikejar: instruksi, sudut yaw
  /// sekarang, dan seberapa lama pose sudah bertahan. Angka yaw ditampilkan
  /// karena kalau kiri/kanan terasa terbalik di suatu perangkat, itulah yang
  /// memberi tahu -- bukan tebakan.
  Widget _panduanSudut() {
    final sudut = _sudutBerikutnya;
    if (sudut == null) {
      return const Row(
        children: [
          Icon(Icons.check_circle, size: 15, color: AppTheme.okGreen),
          SizedBox(width: 8),
          Text('Ketiga sudut sudah terambil.',
              style: TextStyle(color: AppTheme.okGreen, fontSize: 12)),
        ],
      );
    }
    final (_, judul, petunjuk) =
        PoseWindow.steps.firstWhere((e) => e.$1 == sudut);
    final yaw = widget.state.yaw;
    final masuk = yaw != null &&
        widget.state.pitch != null &&
        PoseWindow.inTarget(sudut, yaw, widget.state.pitch!);
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Icon(masuk ? Icons.gps_fixed : Icons.gps_not_fixed,
                  size: 15, color: masuk ? AppTheme.okGreen : AppTheme.brandGold),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '$judul — $petunjuk'
                  '${yaw == null ? '' : '  (yaw ${yaw.toStringAsFixed(0)}°)'}',
                  style: TextStyle(
                      color: masuk ? AppTheme.okGreen : AppTheme.fg,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        if (_autoAmbil)
          SizedBox(
            width: 90,
            child: LinearProgressIndicator(
              value: _stabil / PoseWindow.stableReadings,
              minHeight: 6,
              backgroundColor: AppTheme.panelAlt,
              color: masuk ? AppTheme.okGreen : AppTheme.muted,
            ),
          ),
        const SizedBox(width: 10),
        Switch(
          value: _autoAmbil,
          onChanged: (v) => setState(() {
            _autoAmbil = v;
            _stabil = 0;
          }),
        ),
        const Text('Auto', style: TextStyle(color: AppTheme.muted, fontSize: 11.5)),
      ],
    );
  }

  Widget _barisSudut(String key, String judul, String petunjuk) {
    // Byte-nya diambil dari sesi, bukan di-decode di sini: decode di dalam
    // build berarti ~1 MB dikerjakan ulang tiap rebuild.
    final bytes = _session.bytesFor(key);
    final ada = switch (key) {
      'frontal' => _session.frontalB64 != null,
      'left' => _session.leftB64 != null,
      _ => _session.rightB64 != null,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.panelAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: ada ? AppTheme.okGreen : AppTheme.panelAlt,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: bytes != null
                ? Image.memory(bytes,
                    fit: BoxFit.cover, cacheWidth: 128, gaplessPlayback: true)
                : const Icon(Icons.face_outlined, color: AppTheme.muted),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(judul,
                    style: TextStyle(
                        color: ada ? AppTheme.okGreen : AppTheme.fg,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700)),
                Text(petunjuk,
                    style: const TextStyle(
                        color: AppTheme.muted, fontSize: 11.5)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: (_busy || _sidecarLama) ? null : () => _ambil(key),
            child: Text(ada ? 'Ulangi' : 'Ambil'),
          ),
        ],
      ),
    );
  }

  Widget _langkahTamu() {
    final phase = _session.phase;
    return _kartu(
      tone: phase == WalkInPhase.done ? AppTheme.okGreen : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('2. Tamu mengisi datanya',
              style: TextStyle(
                  color: AppTheme.fg, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          switch (phase) {
            WalkInPhase.capturing => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _session.anglesComplete
                        ? 'Ketiga sudut sudah terambil. Serahkan layar sentuh ke tamu.'
                        : 'Belum lengkap: ${_session.missingAngles.join(", ")}.',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FilledButton.icon(
                      onPressed: _session.anglesComplete ? _serahkan : null,
                      icon: const Icon(Icons.touch_app_outlined, size: 18),
                      label: const Text('Serahkan ke tamu'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.brandGold,
                        foregroundColor: AppTheme.brandBlueDeep,
                        disabledBackgroundColor: AppTheme.panelAlt,
                        disabledForegroundColor: AppTheme.muted,
                      ),
                    ),
                  ),
                ],
              ),
            WalkInPhase.guestFilling => const Text(
                'Layar sentuh sedang diisi tamu…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.submitting => const Text('Mengirim ke server…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.safety => const Text(
                'Tamu sedang mengerjakan kuis safety di layar sentuh…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.askPlan => const Text(
                'Tamu ditanya apakah berkunjung hari ini…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.plan => const Text(
                'Tamu sedang mengisi rencana kunjungan…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.checkin => const Text(
                'Menunggu tamu menghadap kamera untuk check-in…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.signature => const Text(
                'Tamu sedang menandatangani di layar sentuh…',
                style: TextStyle(color: AppTheme.accent, fontSize: 12.5)),
            WalkInPhase.done => _hasil(),
            WalkInPhase.failed => Text(
                // Pesan server ditampilkan apa adanya.
                _session.error,
                style: const TextStyle(color: AppTheme.badRed, fontSize: 12.5)),
            WalkInPhase.idle => const SizedBox.shrink(),
          },
        ],
      ),
    );
  }

  Widget _hasil() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Kode tamu: ',
                style: TextStyle(color: AppTheme.muted, fontSize: 13)),
            SelectableText(
              _session.visitorCode,
              style: const TextStyle(
                  color: AppTheme.brandGold,
                  fontSize: 20,
                  fontWeight: FontWeight.w900),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // embeddings_saved diperiksa terpisah dari "sukses": tiga sudut yang
        // gagal terkirim sebagai field berulang tetap dibalas sukses dengan
        // satu embedding, dan itu baru terasa berbulan kemudian.
        if (_session.embeddingsSaved >= 3)
          Text('Tiga sudut wajah tersimpan (${_session.embeddingsSaved} embedding).',
              style: const TextStyle(color: AppTheme.okGreen, fontSize: 12))
        else
          Text(
            'Peringatan: hanya ${_session.embeddingsSaved} embedding tersimpan, '
            'seharusnya 3. Wajah tamu ini akan lebih sulit dikenali — daftarkan ulang.',
            style: const TextStyle(color: AppTheme.badRed, fontSize: 12, height: 1.4),
          ),
      ],
    );
  }

  Widget _kartu({required Widget child, Color? tone}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (tone ?? AppTheme.panelAlt).withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}
