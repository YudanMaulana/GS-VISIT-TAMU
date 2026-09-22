import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'admin_auth.dart';
import 'camera_slot.dart';
import 'camera_session.dart';
import 'config.dart';
import 'models.dart';
import 'pages/management_console.dart';
import 'sidecar_client.dart';
import 'sidecar_manager.dart';
import 'theme.dart';
import 'walk_in_session.dart';
import 'widgets/admin_login_dialog.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/top_bar.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  /// Jendela kiosk memanggil ke sini: menanyakan keadaan sesi, lalu mengirim
  /// isian formulir tamu. Satu arah, dan foto tidak pernah ikut menyeberang.
  static const _kioskChannel = WindowMethodChannel(
    'garudafood_visit/kiosk',
    mode: ChannelMode.unidirectional,
  );

  static const _previewChannel = WindowMethodChannel(
    'garudafood_visit/preview',
    mode: ChannelMode.unidirectional,
  );

  final AdminSession _admin = AdminSession();
  final FocusNode _focus = FocusNode();
  final SidecarManager _adminSidecar = SidecarManager();
  AppConfig? _config;
  SidecarClient? _adminClient;
  WindowController? _previewWindow;

  // One independent sidecar (own camera, own MediaPipe detector, own
  // auto-identify) per configured camera slot -- the CCTV-style grid.
  List<CameraSession> _sessions = [];
  Timer? _visitWatch;
  bool _busy = false;

  // POS visit flow
  RecognitionResult? _lastVisit;
  // Which session's sidecar actually submitted the last checkin -- kept
  // separate from `_activeSession` because the guest may walk out of every
  // camera's frame right after checking in, while the operator still needs
  // to poll that same visit for the Android-side signature.
  SidecarClient? _lastVisitClient;
  bool _signed = false;
  bool _showDiagnostics = false;
  Future<void>? _adminSidecarBoot;

  @override
  void initState() {
    super.initState();
    _previewChannel.setMethodCallHandler(_handlePreviewCall);
    _kioskChannel.setMethodCallHandler(_handleKioskCall);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _config = await AppConfig.load();
    await Future.wait([_startAdminSidecar(), _startAllSessions()]);
    await _pulihkanSesiAdmin();
  }

  /// Buka kembali sesi admin dari yang tersimpan di sidecar, supaya alur
  /// browser Google tidak diulang tiap app dibuka.
  ///
  /// Emailnya tetap dicocokkan dengan email admin yang dikonfigurasi: sesi
  /// tersimpan bukan izin masuk dengan sendirinya, ia hanya membebaskan
  /// operator dari mengulang login yang sudah pernah berhasil di mesin ini.
  Future<void> _pulihkanSesiAdmin() async {
    final client = _adminBridgeClient;
    if (client == null) return;
    try {
      // Token yang tersimpan tidak dipercaya begitu saja: keabsahannya
      // ditanyakan ke server lewat /admin_me. Token yang sudah dicabut atau
      // kedaluwarsa dibuang sidecar di situ juga, jadi app tidak mencobanya
      // lagi tiap kali dibuka.
      final me = await client.adminMe();
      final body = me['body'];
      if (me['ok'] == true && body is Map && body['success'] == true) {
        final admin = body['admin'];
        final email = admin is Map ? admin['email']?.toString() : null;
        if (_admin.unlockFromStoredSession(email) && mounted) {
          setState(() {});
          return;
        }
      }
    } catch (_) {
      // Sidecar belum siap atau tidak menjawab: operator tinggal login seperti
      // biasa. Gagal memulihkan sesi bukan alasan menahan app di layar kosong.
    }
  }

  Future<void> _startAllSessions() async {
    final config = _config!;
    _sessions = [
      for (final slot in config.cameraSlots.where((s) => s.enabled))
        CameraSession(slot),
    ];
    if (!mounted) return;
    setState(() {});
    await Future.wait(
      _sessions.map(
        (s) => s.start(
          config,
          onUpdate: () {
            if (mounted) {
              setState(() {});
            }
          },
        ),
      ),
    );
    if (mounted) _focus.requestFocus();
  }

  Future<void> _startAdminSidecar() async {
    final config = _config!;
    if (_adminSidecarBoot != null) {
      await _adminSidecarBoot;
      return;
    }
    final boot = _doStartAdminSidecar(config);
    _adminSidecarBoot = boot;
    try {
      await boot;
    } finally {
      _adminSidecarBoot = null;
    }
  }

  Future<void> _doStartAdminSidecar(AppConfig config) async {
    try {
      final port = await _adminSidecar.start(
        config,
        CameraSlot(label: 'Admin API', isNetwork: true, cameraUrl: 'none'),
      );
      _adminClient?.close();
      _adminClient = SidecarClient(port);
    } catch (_) {
      _adminClient?.close();
      _adminClient = null;
    }
    if (mounted) setState(() {});
  }

  Future<SidecarClient?> _ensureAdminBridgeClient() async {
    if (_adminBridgeClient != null) return _adminBridgeClient;
    await _startAdminSidecar();
    return _adminBridgeClient;
  }

  Future<void> _stopAllSessions() async {
    await Future.wait(_sessions.map((s) => s.stop()));
    _sessions = [];
  }

  SidecarClient? get _adminBridgeClient =>
      _adminClient ?? (_sessions.isNotEmpty ? _sessions.first.client : null);

  CameraSession? get _cameraSessionForActions =>
      _activeSession ?? (_sessions.isNotEmpty ? _sessions.first : null);

  SidecarClient? get _cameraBridgeClient => _cameraSessionForActions?.client;

  DetectionState get _cameraBridgeState =>
      _cameraSessionForActions?.state ?? DetectionState();

  /// Whichever camera currently sees a recognised face -- the "whoever's
  /// recognised, on whichever camera, can check in" rule. First match wins if
  /// (rarely) more than one camera recognises someone in the same tick.
  CameraSession? get _activeSession {
    for (final s in _sessions) {
      if (s.hasRecognizedFace) return s;
    }
    return null;
  }

  bool get _allFailed =>
      _sessions.isNotEmpty &&
      _sessions.every((s) => s.phase == CameraPhase.failed);

  Future<dynamic> _handlePreviewCall(MethodCall call) async {
    switch (call.method) {
      case 'snapshot':
        return _previewSnapshot();
      case 'checkin':
        await _checkin();
        return true;
      case 'refresh':
        await _refreshVisit();
        return true;
      case 'checkout':
        await _checkout();
        return true;
      default:
        throw MissingPluginException('No preview method ${call.method}');
    }
  }

  Map<String, dynamic> _previewSnapshot() {
    final active = _activeSession;
    final activeState =
        active?.state ??
        (_sessions.isNotEmpty ? _sessions.first.state : DetectionState());
    final scan = _scanState;
    return {
      'configReady': _config != null,
      'branchName': _config?.branchName ?? '',
      'branchConfigured': _config?.branchId != null,
      'online': _sessions.any((s) => s.state.serverConfigured),
      'busy': _busy,
      'signed': _signed,
      'scanLabel': scan.label,
      'scanColor': scan.color.toARGB32(),
      'activeIndex': active == null ? -1 : _sessions.indexOf(active),
      'sessions': [
        for (var i = 0; i < _sessions.length; i++)
          {
            'index': i,
            'label': _sessions[i].slot.label.isEmpty
                ? 'Kamera ${i + 1}'
                : _sessions[i].slot.label,
            'isNetwork': _sessions[i].slot.isNetwork,
            'phase': _sessions[i].phase.name,
            'failMsg': _sessions[i].failMsg,
            'active': identical(_sessions[i], active),
            'state': _stateMap(_sessions[i].state),
          },
      ],
      'activeState': _stateMap(activeState),
      'lastVisit': _lastVisit == null
          ? null
          : {
              'success': _lastVisit!.success,
              'mode': _lastVisit!.mode,
              'message': _lastVisit!.message,
              'photo': _lastVisit!.photo,
              'visitorName': _lastVisit!.visitor?.fullName ?? '',
            },
    };
  }

  Map<String, dynamic> _stateMap(DetectionState s) => {
    'error': s.error,
    'ready': s.ready,
    'frame': s.frameBytes,
    'faceCount': s.faceCount,
    'message': s.message,
    'color': s.color.toARGB32(),
    'serverConfigured': s.serverConfigured,
    'identifying': s.identifying,
    'autoIdentify': s.autoIdentify,
    'autoCheckin': s.autoCheckin,
    'presenceEnabled': s.presenceEnabled,
    'presencePresent': s.presencePresent,
    'presenceTofOk': s.presenceTofOk,
    'distanceMm': s.distanceMm,
    'identityRecognized': s.identity?.recognized == true,
    'identityVisitorId': s.identity?.visitorId ?? 0,
    'identityVisitorCode': s.identity?.visitorCode ?? '',
    'identityVisitorType': s.identity?.visitorType ?? '',
    'identityName': s.identity?.name ?? '',
    'identityMessage': s.identity?.message ?? '',
    'identitySimilarity': s.identity?.similarity,
    'autoCheckinState': s.autoCheckinResult?.state ?? '',
    'autoCheckinMessage': s.autoCheckinResult?.message ?? '',
  };

  // ---- POS actions ------------------------------------------------------

  Future<void> _checkin() => _submitVisit('checkin');
  Future<void> _checkout() => _submitVisit('checkout');

  Future<void> _submitVisit(String mode) async {
    final session = _activeSession;
    final c = session?.client;
    if (c == null) return;
    if (!session!.state.serverConfigured) {
      _toast('Belum ada API key — isi di Pengaturan.');
      return;
    }
    // Fase 2: server rejects checkin without branch_id (matched against the
    // guest's own visit plan for that branch). Caught here too, not just in
    // the sidecar, so the operator sees a clear message instead of a raw
    // 422 round-trip.
    if (mode == 'checkin' && _config?.branchId == null) {
      _toast('Cabang POS belum diatur — buka Pengaturan untuk memilihnya.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Capture the current frame first, then submit it.
      final cap = await c.capture();
      if (!cap.ok) {
        _toast('Gagal mengambil foto.');
        return;
      }
      if (!cap.sharp) {
        _toast(
          'Foto kurang tajam (var ${cap.variance}). Coba lagi, tahan diam.',
        );
        return;
      }
      final r = await c.submit(mode);
      final res = RecognitionResult.fromJson(r);
      if (!mounted) return;
      setState(() {
        _lastVisit = res;
        _lastVisitClient = c;
        if (mode == 'checkin') _signed = res.signed;
        if (mode == 'checkout' && res.success) _signed = false;
      });
      if (mode == 'checkin' && res.success && !res.signed) {
        _startVisitWatch();
      } else {
        _visitWatch?.cancel();
      }
      _toast(
        res.success
            ? '${mode == 'checkin' ? 'Check-in' : 'Check-out'}: ${res.message}'
            : 'Gagal: ${res.message}',
      );
    } catch (e) {
      _toast('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Re-read the visit from the server to see whether the guest has finished
  /// signing **in their Android app**. Signing never happens on the POS.
  Future<void> _refreshVisit({bool silent = false}) async {
    final c = _lastVisitClient;
    final visit = _lastVisit;
    if (c == null || visit?.visitId == null) return;
    try {
      final r = await c.getVisit(visit!.visitId!);
      if (!mounted) return;
      var nowSigned = false;
      if (r['ok'] == true) {
        final body = r['body'];
        final url = body is Map ? body['signature_visitor_url'] : null;
        nowSigned = url != null && '$url'.isNotEmpty;
      } else if (!silent) {
        _toast('Gagal baca status kunjungan: ${r['error'] ?? r['status']}');
      }

      final visitorId = visit.visitor?.id ?? 0;
      if (!nowSigned && visitorId > 0) {
        final st = await c.guestStatus(visitorId);
        final status = (st['status'] ?? '').toString().trim();
        nowSigned = st['signed'] == true || status == 'signed';
      }

      if (!mounted) return;
      final justSigned = nowSigned && !_signed;
      setState(() => _signed = nowSigned);
      if (justSigned) {
        _toast('Tamu & PIC sudah tanda tangan. Check-out bisa dilakukan.');
      } else if (!silent && !nowSigned) {
        _toast('Belum ada tanda tangan atau data tamu belum lengkap.');
      }
    } catch (e) {
      if (!silent) _toast('Error baca status: $e');
    }
  }

  /// Watch for the Android-side signature so the operator sees check-out unlock
  /// without having to poke anything.
  void _startVisitWatch() {
    _visitWatch?.cancel();
    _visitWatch = Timer.periodic(const Duration(seconds: 3), (t) {
      if (_signed || _lastVisit?.visitId == null) {
        t.cancel();
        return;
      }
      _refreshVisit(silent: true);
    });
  }

  // Note: ManagementConsole is now embedded in _managementHome() once unlocked.

  /// Panggilan dari jendela kiosk. `state` dipanggil berkala; `submit`
  /// sekali, membawa isian tamu. Pendaftarannya dijalankan di sini -- jendela
  /// utama yang memegang foto dan klien sidecar, kiosk tidak memegang
  /// keduanya.
  Future<dynamic> _handleKioskCall(MethodCall call) async {
    final session = WalkInSession.instance;
    switch (call.method) {
      case 'state':
        return session.kioskSnapshot();
      case 'menu':
        // Tamu memilih dari layar sentuh. Aksinya dijalankan di sini karena
        // kamera, foto, dan klien sidecar semuanya milik jendela ini.
        unawaited(_aksiKiosk('${call.arguments}'));
        return session.kioskSnapshot();
      case 'safety_passed':
        session.safetyPassed();
        return session.kioskSnapshot();
      case 'plan_wanted':
        session.wantsPlanToday();
        return session.kioskSnapshot();
      case 'plan_created':
        session.planCreated();
        return session.kioskSnapshot();
      case 'walkin_checkin':
        // Check-in untuk tamu yang baru membuat rencana di kiosk. Hasilnya
        // membawa visit_id, dan itu yang dibutuhkan unggahan tanda tangan.
        unawaited(_checkinKiosk());
        return session.kioskSnapshot();
      case 'signed':
        session.signatureUploaded();
        return session.kioskSnapshot();
      case 'finish':
        session.finished();
        return session.kioskSnapshot();
      case 'reset':
        // Kembali ke menu untuk tamu berikutnya. Sesi lama dibuang seluruhnya
        // -- termasuk foto dan kode tamu -- supaya tidak ada sisa milik orang
        // sebelumnya yang terbawa ke pendaftaran berikutnya.
        session.reset();
        return session.kioskSnapshot();
      case 'submit':
        final raw = call.arguments;
        final fields = <String, String>{
          if (raw is Map)
            for (final e in raw.entries) '${e.key}': '${e.value}',
        };
        session.submitFromGuest(fields);
        unawaited(_kirimPendaftaranWalkIn());
        return session.kioskSnapshot();
      default:
        throw MissingPluginException('kiosk: ${call.method}');
    }
  }

  /// Menjalankan pilihan menu kiosk.
  ///
  /// Registrasi selalu diawali pengenalan wajah, bukan langsung mengambil tiga
  /// sudut: kalau tamunya ternyata sudah terdaftar, mendaftarkannya lagi hanya
  /// menambah identitas kedua untuk orang yang sama — dan yang dia butuhkan
  /// sebenarnya cuma rencana kunjungan baru.
  Future<void> _aksiKiosk(String aksi) async {
    final session = WalkInSession.instance;
    switch (aksi) {
      case 'status_tamu':
        // Cabang "Pengguna Mobile": tamu sudah punya app, jadi yang perlu
        // dijawab bukan "daftar atau belum" melainkan "sudah sampai mana dia
        // hari ini" -- itu yang menentukan tombol mana yang boleh hidup.
        await _statusTamuDariWajah();
      case 'register_tamu':
        session.start();
        final dikenal = await _kenaliWajahSekarang();
        if (dikenal != null) {
          session.existingGuest(code: dikenal.$1, id: dikenal.$2);
        }
      case 'checkin_tamu':
        await _checkin();
      case 'checkout_tamu':
        await _checkout();
    }
  }

  Future<void> _checkinKiosk() async {
    final session = WalkInSession.instance;
    await _checkin();
    final res = _lastVisit;
    // visitId bertipe Object? di model (server pernah mengirimnya sebagai
    // angka maupun string), jadi dinormalkan di sini alih-alih di-cast buta.
    final id = int.tryParse('${res?.visitId ?? ''}') ?? 0;
    if (res != null && res.success && id > 0) {
      session.checkedIn(id);
    } else {
      // Pesan server diteruskan apa adanya -- ia menyebut sebabnya (rencana
      // salah cabang, salah hari, sudah check-in), dan menggantinya dengan
      // "gagal" membuang satu-satunya petunjuk yang tamu punya.
      session.failed(res?.message ?? 'Check-in gagal.');
    }
  }

  /// Kenali wajah lalu ambil keadaan kunjungannya hari ini.
  Future<void> _statusTamuDariWajah() async {
    final session = WalkInSession.instance;
    final client =
        _activeSession?.client ??
        (_sessions.isNotEmpty ? _sessions.first.client : null);
    final dikenal = await _kenaliWajahSekarang();
    if (dikenal == null || client == null) {
      session.failed('Wajah tidak dikenali. Coba lagi menghadap kamera.');
      return;
    }
    try {
      final st = await client.guestStatus(dikenal.$2);
      session.guestIdentified(
        code: dikenal.$1,
        id: dikenal.$2,
        name: dikenal.$3,
        hasPlan: st['has_plan'] == true,
        status: st['status']?.toString() ?? '',
        signed: st['signed'] == true,
      );
    } catch (e) {
      session.failed('Gagal membaca status kunjungan: $e');
    }
  }

  /// Kenali wajah dari kamera pos. Mengembalikan (kode tamu, id) kalau cocok,
  /// `null` kalau tidak ada yang cocok atau prosesnya gagal — dan gagal di
  /// sini sengaja berarti "lanjutkan pendaftaran", bukan menghentikan tamu.
  Future<(String, int, String)?> _kenaliWajahSekarang() async {
    final client =
        _activeSession?.client ??
        (_sessions.isNotEmpty ? _sessions.first.client : null);
    if (client == null) return null;
    try {
      final cap = await client.capture();
      if (!cap.ok || !cap.sharp) return null;
      final still = await client.lastStill();
      final b64 = still['jpeg_b64'];
      if (b64 is! String || b64.isEmpty) return null;
      final hasil = await client.identifyPhoto(base64Decode(b64));
      final cocok = hasil.match;
      final v = cocok?.visitor;
      if (cocok?.success == true && v != null && v.id > 0) {
        return (v.visitorCode, v.id, v.fullName);
      }
    } catch (_) {
      // Pengenalan gagal bukan alasan menolak tamu: alur pendaftaran biasa
      // tetap berjalan, dan server akan menolak wajah ganda kalau memang ada.
    }
    return null;
  }

  Future<void> _kirimPendaftaranWalkIn() async {
    final session = WalkInSession.instance;
    final client =
        _activeSession?.client ??
        (_sessions.isNotEmpty ? _sessions.first.client : null);
    if (client == null) {
      session.failed('Sidecar belum berjalan.');
      return;
    }
    if (!session.anglesComplete) {
      session.failed('Foto wajah tidak lengkap.');
      return;
    }
    try {
      final res = await client.registerWalkIn(
        frontalB64: session.frontalB64!,
        leftB64: session.leftB64!,
        rightB64: session.rightB64!,
        fields: session.form,
      );
      final hasil = WalkInResult.fromEnvelope(res);
      if (!hasil.success) {
        session.failed(hasil.message);
        return;
      }
      session.registered(
        code: hasil.visitorCode,
        id: hasil.visitorId,
        embeddings: hasil.embeddingsSaved,
      );
    } catch (e) {
      session.failed('Gagal mendaftar: $e');
    }
  }

  /// Jendela kiosk di layar sentuh kedua. Port sidecar ikut di argumennya
  /// supaya kiosk bisa mengambil katalog sendiri.
  Future<void> _openGuestKiosk() async {
    final client =
        _activeSession?.client ??
        (_sessions.isNotEmpty ? _sessions.first.client : null);
    final args = 'guest-kiosk:${client?.port ?? 0}';
    for (final controller in await WindowController.getAll()) {
      if (controller.arguments == args) {
        await controller.show();
        return;
      }
    }
    final window = await WindowController.create(
      WindowConfiguration(arguments: args, hiddenAtLaunch: true),
    );
    await window.show();
  }

  Future<void> _openCameraPreview() async {
    for (final controller in await WindowController.getAll()) {
      if (controller.arguments == 'camera-preview') {
        _previewWindow = controller;
        await controller.show();
        return;
      }
    }
    _previewWindow = await WindowController.create(
      const WindowConfiguration(
        arguments: 'camera-preview',
        hiddenAtLaunch: true,
      ),
    );
    await _previewWindow!.show();
  }

  Future<void> _openSettings() async {
    final updated = await showDialog<AppConfig>(
      context: context,
      builder: (_) =>
          SettingsDialog(config: _config!, client: _adminBridgeClient),
    );
    if (updated != null) {
      _config = updated;
      _adminClient?.close();
      await _adminSidecar.stop();
      await _stopAllSessions();
      await Future.wait([_startAdminSidecar(), _startAllSessions()]);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: const Duration(seconds: 4),
        backgroundColor: AppTheme.panelAlt,
      ),
    );
  }

  void _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.f1) _checkin();
    if (k == LogicalKeyboardKey.f2 && _lastVisit != null) _refreshVisit();
    if (k == LogicalKeyboardKey.f3 && _signed) _checkout();
    if (k == LogicalKeyboardKey.f9) {
      setState(() => _showDiagnostics = !_showDiagnostics);
    }
  }

  @override
  void dispose() {
    _visitWatch?.cancel();
    _previewChannel.setMethodCallHandler(null);
    _adminClient?.close();
    _adminSidecar.stop();
    for (final s in _sessions) {
      s.stop();
    }
    _focus.dispose();
    super.dispose();
  }

  // ---- build ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Scaffold(
        backgroundColor: AppTheme.bg,
        body: _shellBackground(
          SafeArea(child: _config == null ? _splash() : _posView()),
        ),
      ),
    );
  }

  Widget _shellBackground(Widget child) {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -90,
            child: _ambientOrb(AppTheme.accent, 280, 0.10),
          ),
          Positioned(
            left: -110,
            bottom: -130,
            child: _ambientOrb(AppTheme.brandGold, 320, 0.07),
          ),
          Positioned(
            top: 130,
            left: 80,
            child: _ambientOrb(AppTheme.brandBlueBright, 220, 0.08),
          ),
          child,
        ],
      ),
    );
  }

  Widget _ambientOrb(Color color, double size, double alpha) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: alpha),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  ({String label, Color color}) get _scanState {
    if (_busy) return (label: 'PROSES', color: AppTheme.brandGold);
    if (_activeSession != null) {
      return (label: 'DIKENALI', color: AppTheme.okGreen);
    }
    if (_sessions.any((s) => s.state.identifying)) {
      return (label: 'MENGENALI', color: AppTheme.brandGold);
    }
    if (_sessions.any((s) => s.state.faceCount > 0)) {
      return (label: 'SCAN', color: AppTheme.accent);
    }
    return (label: 'SIAP', color: AppTheme.muted);
  }

  Widget _posView() {
    final config = _config;
    // Sebelum login layarnya hanya login: tidak ada top bar, jadi Pengaturan
    // (yang memuat API key dan token reset) dan preview kamera tidak lagi
    // terjangkau oleh siapa pun yang sekadar membuka app di meja depan.
    if (config == null) return _splash();
    if (!_admin.isUnlocked) return _loginScreen(config);

    final s = _scanState;
    final anyServerConfigured = _sessions.any(
      (sess) => sess.state.serverConfigured,
    );
    return Column(
      children: [
        PosTopBar(
          stateLabel: s.label,
          stateColor: s.color,
          online: anyServerConfigured,
          branchName: _config?.branchName ?? '',
          adminEmail: _admin.email,
          onPreview: _openCameraPreview,
          onSettings: _openSettings,
          onLock: () => setState(_admin.lock),
        ),
        Expanded(child: _managementHome()),
      ],
    );
  }

  Widget _managementHome() {
    final config = _config;
    if (config == null) return _splash();
    return Column(
      children: [
        if (_allFailed) _cameraWarning(),
        Expanded(
          child: ManagementConsole(
            client: _adminBridgeClient,
            cameraClient: _cameraBridgeClient,
            cameraState: _cameraBridgeState,
            config: config,
            session: _admin,
            onOpenKiosk: _openGuestKiosk,
            onOpenPreview: _openCameraPreview,
            embedded: true,
          ),
        ),
      ],
    );
  }

  Widget _cameraWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.badRed.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.badRed.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: AppTheme.badRed,
            size: 18,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Semua kamera gagal dijalankan. Konsol manajemen tetap bisa digunakan; buka Pengaturan untuk memperbaiki kamera.',
              style: TextStyle(color: AppTheme.fg, fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings, size: 16),
            label: const Text('Pengaturan'),
          ),
        ],
      ),
    );
  }

  /// Satu-satunya layar sebelum masuk: merek, dan satu tombol.
  ///
  /// Tidak ada preview kamera dan tidak ada Pengaturan di sini. Keduanya
  /// pindah ke dalam konsol, di balik login — kios di meja depan yang
  /// membiarkan siapa pun membuka Pengaturan sama saja dengan membiarkan API
  /// key-nya terbaca.
  Widget _loginScreen(AppConfig config) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          padding: const EdgeInsets.fromLTRB(36, 36, 36, 32),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [
                Color(0xF00D2A5E),
                Color(0xE60A2352),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 36,
                offset: Offset(0, 18),
              ),
              BoxShadow(
                color: Color(0x1AF4C300),
                blurRadius: 24,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.brandGold.withValues(alpha: 0.18),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Image.asset(
                    'assets/branding/visit_logo_tight.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'GARUDASHIELD',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.fg,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  height: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'VISIT CONSOLE',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.brandGold,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 4.5,
                  height: 1,
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Sistem pengawasan gerbang, pendaftaran tamu walk-in, dan integrasi absensi enterprise.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppTheme.mutedStrong,
                  fontSize: 13,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _featureBadge(Icons.face, 'Deteksi Wajah'),
                  _featureBadge(Icons.local_shipping, 'Transporter'),
                  _featureBadge(Icons.badge, 'Magang'),
                  _featureBadge(Icons.cloud_done, 'Cloud Sync'),
                ],
              ),
              const SizedBox(height: 26),
              FilledButton.icon(
                onPressed: () async {
                  final client = await _ensureAdminBridgeClient();
                  if (!mounted) return;
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AdminLoginDialog(
                      config: config,
                      session: _admin,
                      client: client,
                      resolveClient: _ensureAdminBridgeClient,
                    ),
                  );
                  if (ok == true && mounted) setState(() {});
                },
                icon: const Icon(Icons.login, size: 19),
                label: const Text('Masuk ke Konsol'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: AppTheme.brandBlueDeep,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (_allFailed) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.warnAmber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: AppTheme.warnAmber.withValues(alpha: 0.35),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.info_outline,
                          size: 15, color: AppTheme.warnAmber),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Kamera belum terhubung — periksa di Pengaturan setelah masuk.',
                          style: TextStyle(
                            color: AppTheme.warnAmber,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _featureBadge(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.brandGold),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.mutedStrong,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _splash() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(
            'assets/branding/visit_logo_tight.png',
            width: 132,
            height: 132,
          ),
          const SizedBox(height: 24),
          const CircularProgressIndicator(color: AppTheme.brandGold),
          const SizedBox(height: 18),
          const Text(
            'Menyiapkan Visit…',
            style: TextStyle(
              color: AppTheme.fg,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Menjalankan mesin deteksi wajah.',
            style: TextStyle(color: AppTheme.muted, fontSize: 14),
          ),
        ],
      ),
    );
  }
}
