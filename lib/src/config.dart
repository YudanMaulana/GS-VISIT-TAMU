import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'camera_slot.dart';

/// Where the Python detection sidecar + its venv live, plus camera/server
/// settings. Persisted with shared_preferences so the app remembers them.
///
/// The detection itself runs in the Python `sidecar.py` (ML Kit is mobile
/// only and MediaPipe has no Dart binding), so the GUI needs to know how to
/// launch it. Defaults assume the sibling `garudafood-linux-detector` repo.
///
/// Multi-camera: each entry in [cameraSlots] gets its OWN sidecar process
/// (own camera, own MediaPipe detector, own auto-identify) -- see
/// `CameraSession` in home_page.dart. Everything else here (server, branch,
/// admin, submit behaviour) is shared across all of them.
class AppConfig {
  String pythonPath;
  String sidecarPath;
  List<CameraSlot> cameraSlots;

  bool mirror;
  String baseUrl; // empty -> sidecar uses its built-in default
  String apiKey;
  String submitMode; // 'none' | 'checkin' | 'checkout' | 'register'
  bool autoIdentify; // label the bbox with the recognised name
  /// Check the guest in the moment their face is recognised AND they have
  /// a 'planned' visit plan for this branch. Off by default: it writes a
  /// visit row without an operator touching anything, so turning it on
  /// should be a decision, not the state a fresh install happens to boot in.
  bool autoCheckin;
  int?
  branchId; // Fase 2: this POS's branch, required by the server for check-in
  String branchName; // display only, so Settings doesn't show a bare id

  // --- Admin gate for the data-management console -------------------------
  // The POS itself is a public front-desk kiosk; the management console
  // Email admin terakhir yang dipakai, semata-mata untuk mengisi awal kolom
  // di layar login. Bukan izin masuk: yang memutuskan siapa admin adalah
  // tabel `admin_users` di server. Kata sandinya TIDAK pernah disimpan di
  // sini dalam bentuk apa pun, termasuk hash -- hash yang tertinggal di dalam
  // biner adalah hash yang bisa diserang offline oleh siapa pun yang
  // memegang binernya.
  String adminEmail;

  // Google desktop OAuth (second admin layer). Loopback + PKCE flow; these
  // come from a Google Cloud "Desktop app" client. Kept in prefs, NOT in
  // source, so the secret never lands in the repo. Empty => Google layer
  // stays disabled and only email+password unlocks.
  String googleClientId;
  String googleClientSecret;

  // Token papan milik pos ini, dikirim sebagai X-Admin-Token dan diteruskan ke
  // sidecar lewat environment GARUDA_ADMIN_TOKEN.
  //
  // Namanya tertinggal dari masa ketika ia hanya dipakai /api/admin/reset.
  // Sejak server menggerbangi /checkin dan /checkout, ia jadi kredensial yang
  // membuat kiosk tetap bisa mencatat kunjungan setelah sesi admin 12 jam
  // habis. Sengaja BUKAN apiKey: yang satu membaca, yang satu menulis.
  //
  // Isi dengan token papan, bukan token admin penuh -- lihat catatan di
  // settings_dialog.dart soal kenapa.
  String adminResetToken;

  static const defaultAdminEmail = 'yudanworkspace@gmail.com';

  bool get googleAuthConfigured =>
      googleClientId.isNotEmpty && googleClientSecret.isNotEmpty;

  bool get adminResetConfigured => adminResetToken.isNotEmpty;

  AppConfig({
    required this.pythonPath,
    required this.sidecarPath,
    List<CameraSlot>? cameraSlots,
    this.mirror = false,
    this.baseUrl = '',
    this.apiKey = '',
    this.submitMode = 'none',
    this.autoIdentify = true,
    this.autoCheckin = false,
    this.branchId,
    this.branchName = '',
    this.adminEmail = defaultAdminEmail,
    this.googleClientId = '',
    this.googleClientSecret = '',
    this.adminResetToken = '',
  }) : cameraSlots = cameraSlots ?? [CameraSlot(label: 'Kamera 1')];

  static const _detectorDirName = 'garudafood-linux-detector';

  /// Locate the Python detector project. Order:
  ///   1. `GARUDA_DETECTOR_DIR` env override,
  ///   2. walk up from the CWD and from the running binary looking for the
  ///      detector sitting beside this app (the repo layout) — so a clone
  ///      works from any path, whether run via `flutter run` or the built
  ///      bundle (which lives ~6 levels deep under the app dir),
  ///   3. give up and return the conventional sibling path, which the UI
  ///      will report as missing and let the user fix in Settings.
  static String _defaultRepoDir() {
    final env = Platform.environment['GARUDA_DETECTOR_DIR'];
    if (env != null && env.isNotEmpty) return env;

    for (final start in <String>[
      Directory.current.path,
      File(Platform.resolvedExecutable).parent.path,
    ]) {
      var dir = Directory(start);
      for (var i = 0; i < 8; i++) {
        final candidate = Directory('${dir.path}/$_detectorDirName');
        if (candidate.existsSync()) return candidate.path;
        final parent = dir.parent;
        if (parent.path == dir.path) break; // hit filesystem root
        dir = parent;
      }
    }
    return '${Directory.current.parent.path}/$_detectorDirName';
  }

  factory AppConfig.defaults() {
    final dir = _defaultRepoDir();
    final pythonPath = Platform.isWindows
        ? '$dir/.venv/Scripts/python.exe'
        : '$dir/.venv/bin/python';
    return AppConfig(pythonPath: pythonPath, sidecarPath: '$dir/sidecar.py');
  }

  static const _requiredSidecarMarkers = [
    'def admin_google(',
    '"/admin_google"',
    'def admin_console_code_login(',
    '"/admin_console_code_login"',
    'def internship_visitors(',
    '"/internship_visitors"',
    'def _run_without_camera(',
  ];

  /// Use a persisted path only if it still exists; otherwise fall back to the
  /// freshly-detected default. Without this, a saved path silently outlives a
  /// moved/re-cloned checkout and the app just fails to start the sidecar.
  static String _pickPath(String? saved, String fallback) =>
      (saved != null && saved.isNotEmpty && File(saved).existsSync())
      ? saved
      : fallback;

  /// A stale detector can still exist on disk, which is worse than missing:
  /// the GUI starts successfully, then login kode cabang hits `/admin_google`
  /// and receives a bare `not found`. Refuse saved sidecars that don't contain
  /// the current admin/magang routes and fall back to the bundled detector.
  static String _pickSidecarPath(String? saved, String fallback) {
    final candidate = _pickPath(saved, fallback);
    if (_sidecarSupportsCurrentConsole(candidate)) return candidate;
    if (_sidecarSupportsCurrentConsole(fallback)) return fallback;
    return candidate;
  }

  static bool _sidecarSupportsCurrentConsole(String path) {
    try {
      final text = File(path).readAsStringSync();
      return _requiredSidecarMarkers.every(text.contains);
    } catch (_) {
      return false;
    }
  }

  static Future<AppConfig> load() async {
    final p = await SharedPreferences.getInstance();
    final d = AppConfig.defaults();
    final sidecarPath = _pickSidecarPath(
      p.getString('sidecarPath'),
      d.sidecarPath,
    );
    final savedSidecarOk = sidecarPath == (p.getString('sidecarPath') ?? '');

    var slots = decodeCameraSlots(p.getString('cameraSlots'));
    if (slots.isEmpty) {
      // Migrate the old single-camera scalar keys (pre-multi-camera builds)
      // if present, so an existing install doesn't lose its configured
      // camera on upgrade. Falls back to the one-slot default otherwise.
      final oldUrl = p.getString('cameraUrl') ?? '';
      final oldCaptureUrl = p.getString('captureUrl') ?? '';
      final oldIndex = p.getInt('camera');
      final oldName = p.getString('cameraName') ?? '';
      if (oldUrl.isNotEmpty || oldIndex != null) {
        slots = [
          CameraSlot(
            label: oldName.isNotEmpty ? oldName : 'Kamera 1',
            isNetwork: oldUrl.isNotEmpty,
            localIndex: oldIndex ?? 0,
            cameraUrl: oldUrl,
            captureUrl: oldCaptureUrl,
          ),
        ];
      } else {
        slots = d.cameraSlots;
      }
    }

    return AppConfig(
      pythonPath: _pickPath(
        savedSidecarOk ? p.getString('pythonPath') : null,
        d.pythonPath,
      ),
      sidecarPath: sidecarPath,
      cameraSlots: slots,
      mirror: p.getBool('mirror') ?? d.mirror,
      baseUrl: p.getString('baseUrl') ?? d.baseUrl,
      apiKey: p.getString('apiKey') ?? d.apiKey,
      submitMode: p.getString('submitMode') ?? d.submitMode,
      autoIdentify: p.getBool('autoIdentify') ?? d.autoIdentify,
      autoCheckin: p.getBool('autoCheckin') ?? d.autoCheckin,
      branchId: p.getInt(
        'branchId',
      ), // absent key -> null -> not configured yet
      branchName: p.getString('branchName') ?? '',
      adminEmail: p.getString('adminEmail') ?? defaultAdminEmail,
      googleClientId: p.getString('googleClientId') ?? '',
      googleClientSecret: p.getString('googleClientSecret') ?? '',
      adminResetToken: p.getString('adminResetToken') ?? '',
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('pythonPath', pythonPath);
    await p.setString('sidecarPath', sidecarPath);
    await p.setString('cameraSlots', encodeCameraSlots(cameraSlots));
    // Old scalar keys are no longer read once cameraSlots exists (see load()),
    // but drop them anyway so a downgrade doesn't resurrect stale values.
    await p.remove('camera');
    await p.remove('cameraUrl');
    await p.remove('captureUrl');
    await p.remove('cameraName');
    await p.setBool('mirror', mirror);
    await p.setString('baseUrl', baseUrl);
    await p.setString('apiKey', apiKey);
    await p.setString('submitMode', submitMode);
    await p.setBool('autoIdentify', autoIdentify);
    await p.setBool('autoCheckin', autoCheckin);
    if (branchId != null) {
      await p.setInt('branchId', branchId!);
    } else {
      await p.remove('branchId');
    }
    await p.setString('branchName', branchName);
    await p.setString('adminEmail', adminEmail);
    // Sisa dari gerbang lokal yang sudah dicabut. Dihapus, bukan dibiarkan:
    // hash kata sandi yang tertinggal di prefs tetap bisa diserang offline.
    await p.remove('adminPasswordSha256');
    await p.setString('googleClientId', googleClientId);
    await p.setString('googleClientSecret', googleClientSecret);
    await p.setString('adminResetToken', adminResetToken);
  }

  /// CLI args to launch one camera slot's sidecar. Port 0 = let the OS pick a
  /// free port; the manager reads the real one back from the sidecar's
  /// stdout. Each slot's sidecar is an entirely separate process, so the same
  /// args shape as the old single-camera build -- just built per slot now.
  ///
  /// The API key is deliberately NOT passed here — argv is world-readable via
  /// `ps` / `/proc/<pid>/cmdline`, so the secret goes through the environment
  /// instead (see [sidecarEnv]).
  List<String> sidecarArgsFor(CameraSlot slot, int port) {
    final args = <String>[
      sidecarPath,
      '--camera', slot.isNetwork ? slot.cameraUrl : '${slot.localIndex}',
      '--host', '127.0.0.1',
      '--port', '$port',
      // Belt-and-braces cleanup: the sidecar kills itself if this GUI dies,
      // even on a hard window-close/SIGTERM that skips Dart's dispose().
      '--parent-death-exit',
    ];
    if (slot.isNetwork && slot.captureUrl.isNotEmpty) {
      args.addAll(['--capture-url', slot.captureUrl]);
    }
    if (mirror) args.add('--mirror');
    if (submitMode != 'none') args.addAll(['--submit', submitMode]);
    // No-op unless an API key is configured (the sidecar checks).
    if (autoIdentify) args.add('--auto-identify');
    // Percuma tanpa auto-identify: sidecar memutuskan auto check-in dari
    // hasil identify, jadi tanpa itu tidak ada yang memicunya.
    if (autoCheckin && autoIdentify) args.add('--auto-checkin');
    if (branchId != null) args.addAll(['--branch-id', '$branchId']);
    return args;
  }

  /// Secrets/config handed to the sidecar via the environment rather than argv.
  /// `sidecar.py` reads these through `ServerConfig.from_env`. Shared by every
  /// camera slot's process -- same server, same key.
  Map<String, String> sidecarEnv() => {
    if (baseUrl.isNotEmpty) 'GARUDA_BASE_URL': baseUrl,
    if (apiKey.isNotEmpty) 'GARUDA_API_KEY': apiKey,
    if (adminResetToken.isNotEmpty) 'GARUDA_ADMIN_TOKEN': adminResetToken,
    // Dipakai sidecar untuk memperbarui sesi admin dari refresh_token
    // Google tanpa membuka browser lagi.
    if (googleClientId.isNotEmpty) 'GARUDA_GOOGLE_CLIENT_ID': googleClientId,
    if (googleClientSecret.isNotEmpty)
      'GARUDA_GOOGLE_CLIENT_SECRET': googleClientSecret,
  };

  AppConfig copy() => AppConfig(
    pythonPath: pythonPath,
    sidecarPath: sidecarPath,
    cameraSlots: cameraSlots.map((s) => s.copy()).toList(),
    mirror: mirror,
    baseUrl: baseUrl,
    apiKey: apiKey,
    submitMode: submitMode,
    autoIdentify: autoIdentify,
    autoCheckin: autoCheckin,
    branchId: branchId,
    branchName: branchName,
    adminEmail: adminEmail,
    googleClientId: googleClientId,
    googleClientSecret: googleClientSecret,
    adminResetToken: adminResetToken,
  );
}
