import 'package:flutter/material.dart';

import '../admin_auth.dart';
import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../google_desktop_auth.dart';
import '../theme.dart';

/// Unlock gate for the data-management console.
///
/// Two-layer by design (Google + email/password), mirroring the Windows
/// reference app. Email + password is the reliable desktop layer and is wired
/// here; the Google layer needs a Google Cloud *Desktop* OAuth client (loopback
/// flow) that only the owner can create, so it's shown but disabled until that
/// credential exists — deliberately not faked.
///
/// Returns `true` via [Navigator.pop] when the session unlocks.
class AdminLoginDialog extends StatefulWidget {
  final AppConfig config;
  final AdminSession session;

  /// Dipakai hanya untuk mencatat sesi admin di sidecar setelah login Google
  /// berhasil, supaya alur browser tidak diulang tiap app dibuka. Boleh null
  /// (mis. sidecar belum berjalan): login tetap bisa, hanya tidak tersimpan.
  final SidecarClient? client;
  final Future<SidecarClient?> Function()? resolveClient;

  const AdminLoginDialog({
    super.key,
    required this.config,
    required this.session,
    this.client,
    this.resolveClient,
  });

  @override
  State<AdminLoginDialog> createState() => _AdminLoginDialogState();
}

class _AdminLoginDialogState extends State<AdminLoginDialog> {
  late final TextEditingController _email = TextEditingController(
    text: widget.config.adminEmail,
  );
  final _password = TextEditingController();

  /// Kode konsol cabang diisi setelah Google berhasil. Dipisah dari tombol
  /// Google supaya operator paham urutannya: pilih akun bebas dulu, baru ikat
  /// mesin ini ke cabang dengan kode dari server.
  final _consoleCode = TextEditingController();

  /// Form email+kata sandi disembunyikan, bukan dihapus.
  ///
  /// Jalur masuk konsol sekarang Google + kode konsol. Tapi mencabut jalur
  /// lama sepenuhnya berarti mesin yang OAuth Google-nya belum dikonfigurasi,
  /// atau yang cabangnya belum punya kode konsol, tidak bisa dimasuki sama
  /// sekali -- dan itu terjadi di tengah shift, bukan saat orang siap
  /// memperbaikinya. Dibuka lewat tekan-lama ikon di kiri atas: tidak
  /// ditemukan tanpa sengaja, tapi ada saat dibutuhkan.
  bool _jalurLama = false;
  bool _obscure = true;
  bool _googleBusy = false;
  bool _codeBusy = false;
  bool _busy = false;
  String? _pendingIdToken;
  String? _pendingRefreshToken;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _consoleCode.dispose();
    super.dispose();
  }

  /// Login sehari-hari: email + kata sandi, diputuskan server.
  ///
  /// Pesan galat dari server ditampilkan **apa adanya**. Pesan rem percobaan
  /// menyebut sisa detiknya, dan menggantinya dengan "Login gagal" membuang
  /// satu-satunya petunjuk kenapa kata sandi yang benar pun ditolak.
  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final client = await _clientSiap();
      if (client == null) return;
      final res = await client.adminLogin(_email.text.trim(), _password.text);
      final hasil = AdminLoginResult.fromEnvelope(res);
      if (!hasil.success) {
        setState(
          () => _error = hasil.message.isEmpty
              ? 'Login gagal — server tidak memberi keterangan.'
              : hasil.message,
        );
        return;
      }
      if (hasil.mustSetPassword) {
        // Akun yang belum pernah punya kata sandi (mis. baru masuk lewat
        // Google). Dibuat dulu, baru sesinya dibuka.
        final dibuat = await _buatKataSandi(client);
        if (!dibuat) return;
      }
      widget.session.unlockFromServer(
        email: hasil.admin?.email ?? _email.text.trim(),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Tidak bisa menghubungi server: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Layar "buat kata sandi" untuk akun yang balasannya `must_set_password`.
  /// Dikirim dengan `current_password` kosong, sesuai kontrak server.
  Future<bool> _buatKataSandi(SidecarClient client) async {
    final baru = TextEditingController();
    final ulang = TextEditingController();
    String? galat;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: AppTheme.panel,
          title: const Text(
            'Buat kata sandi admin',
            style: TextStyle(color: AppTheme.fg, fontSize: 17),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Akun ini belum punya kata sandi. Buat sekarang supaya login '
                'berikutnya tidak perlu lewat browser.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12.5),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: baru,
                obscureText: true,
                style: const TextStyle(color: AppTheme.fg),
                decoration: _dec('Kata sandi baru', Icons.lock_outline),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ulang,
                obscureText: true,
                style: const TextStyle(color: AppTheme.fg),
                decoration: _dec('Ulangi kata sandi', Icons.lock_reset),
              ),
              if (galat != null) ...[
                const SizedBox(height: 10),
                Text(
                  galat!,
                  style: const TextStyle(color: AppTheme.badRed, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () async {
                if (baru.text.length < 8) {
                  setLocal(() => galat = 'Minimal 8 karakter.');
                  return;
                }
                if (baru.text != ulang.text) {
                  setLocal(() => galat = 'Dua isian tidak sama.');
                  return;
                }
                final res = await client.adminSetPassword(
                  currentPassword: '',
                  newPassword: baru.text,
                );
                final body = res['body'];
                final sukses = body is Map && body['success'] == true;
                if (sukses) {
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } else {
                  setLocal(
                    () => galat =
                        (body is Map ? body['message'] : null)?.toString() ??
                        res['error']?.toString() ??
                        'Gagal menyimpan kata sandi.',
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    baru.dispose();
    ulang.dispose();
    return ok == true;
  }

  /// Jalan masuk pertama kali app dipasang, dan cadangan kalau kata sandi
  /// terlupa. Sengaja tidak pernah disembunyikan setelah kata sandi dibuat:
  /// ini satu-satunya jalan masuk kalau kata sandinya hilang.
  Future<void> _google() async {
    if (!widget.config.googleAuthConfigured) return;
    setState(() {
      _googleBusy = true;
      _error = null;
    });
    try {
      final auth = GoogleDesktopAuth(
        clientId: widget.config.googleClientId,
        clientSecret: widget.config.googleClientSecret,
      );
      final idToken = await auth.signInIdToken();
      if (!mounted) return;
      setState(() {
        _pendingIdToken = idToken;
        _pendingRefreshToken = auth.lastRefreshToken;
      });
    } on GoogleAuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Login Google gagal: $e');
    } finally {
      if (mounted) setState(() => _googleBusy = false);
    }
  }

  Future<void> _submitConsoleCode() async {
    final idToken = _pendingIdToken;
    final code = _consoleCode.text.trim();
    if (idToken == null || idToken.isEmpty) {
      setState(() => _error = 'Masuk Google dulu, lalu isi kode cabang.');
      return;
    }
    if (code.isEmpty) {
      setState(() => _error = 'Kode cabang wajib diisi.');
      return;
    }
    setState(() {
      _codeBusy = true;
      _error = null;
    });
    try {
      final client = await _clientSiap();
      if (client == null) return;
      final res = await client.adminConsoleCodeLogin(
        idToken,
        consoleCode: code,
        refreshToken: _pendingRefreshToken,
      );
      final hasil = AdminLoginResult.fromEnvelope(res);
      if (!hasil.success) {
        setState(
          () => _error = hasil.message.isEmpty
              ? 'Kode cabang ditolak server.'
              : hasil.message,
        );
        return;
      }
      await _syncBranchFromCredential(client);
      widget.session.unlockFromServer(email: hasil.admin?.email ?? '');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Aktivasi kode cabang gagal: $e');
    } finally {
      if (mounted) setState(() => _codeBusy = false);
    }
  }

  Future<SidecarClient?> _clientSiap() async {
    final client = widget.client ?? await widget.resolveClient?.call();
    if (client == null && mounted) {
      setState(
        () =>
            _error = 'Sidecar belum berjalan — tidak bisa menghubungi server.',
      );
    }
    return client;
  }

  Future<void> _syncBranchFromCredential(SidecarClient client) async {
    try {
      final env = await client.branchOfCredential();
      final body = env['body'];
      if (env['ok'] != true || body is! Map) return;
      final id = (body['branch_id'] as num?)?.toInt();
      final name = body['branch_name']?.toString().trim() ?? '';
      if (id == null || name.isEmpty) return;
      widget.config.branchId = id;
      widget.config.branchName = name;
      await widget.config.save();
    } catch (_) {
      // Login tetap sah; sinkronisasi prefs hanya agar header POS langsung
      // menampilkan cabang hasil kode.
    }
  }

  void _gantiAkunGoogle() {
    setState(() {
      _pendingIdToken = null;
      _pendingRefreshToken = null;
      _consoleCode.clear();
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final menungguKode = _pendingIdToken != null;
    return Dialog(
      backgroundColor: AppTheme.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  GestureDetector(
                    onLongPress: () => setState(() => _jalurLama = !_jalurLama),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: AppTheme.brandGold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.admin_panel_settings,
                        color: AppTheme.brandGold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          menungguKode ? 'Kode Cabang' : 'Masuk Admin',
                          style: TextStyle(
                            color: AppTheme.fg,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          menungguKode
                              ? 'Google berhasil — ikat mesin ke cabang'
                              : 'Kelola Data — akses terbatas',
                          style: TextStyle(color: AppTheme.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (!menungguKode && _jalurLama) ...[
                Text(
                  'Jalur lama, hanya untuk keadaan darurat. Konsol seharusnya '
                  'dimasuki dengan Google lalu kode konsol cabang.',
                  style: TextStyle(
                    color: AppTheme.muted.withValues(alpha: 0.9),
                    fontSize: 11.5,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  style: const TextStyle(color: AppTheme.fg),
                  keyboardType: TextInputType.emailAddress,
                  decoration: _dec('Email admin', Icons.email_outlined),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: _obscure,
                  style: const TextStyle(color: AppTheme.fg),
                  onSubmitted: (_) => _busy ? null : _submit(),
                  decoration: _dec('Kata sandi', Icons.lock_outline).copyWith(
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        color: AppTheme.muted,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppTheme.badRed,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppTheme.badRed,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              if (!menungguKode && _jalurLama)
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: (_busy || _googleBusy) ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.brandBlueDeep,
                            ),
                          )
                        : const Icon(Icons.login, size: 18),
                    label: Text(_busy ? 'Menghubungi server…' : 'Masuk'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandGold,
                      foregroundColor: AppTheme.brandBlueDeep,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              // Pemisah hanya berarti kalau ada sesuatu di atasnya.
              if (!menungguKode && _jalurLama) ...[
                const SizedBox(height: 16),
                const Divider(height: 1),
              ],
              const SizedBox(height: 14),
              if (menungguKode) ...[
                const Text(
                  'Akun Google sudah dipilih. Masukkan kode cabang dari server '
                  'untuk mengaktifkan konsol di mesin ini.',
                  style: TextStyle(
                    color: AppTheme.muted,
                    fontSize: 12.5,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _consoleCode,
                  obscureText: true,
                  autofocus: true,
                  onSubmitted: (_) => _codeBusy ? null : _submitConsoleCode(),
                  decoration: const InputDecoration(
                    labelText: 'Kode cabang',
                    helperText: 'Kode 24 jam dari admin/server.',
                    helperMaxLines: 2,
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _codeBusy ? null : _submitConsoleCode,
                    icon: _codeBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.brandBlueDeep,
                            ),
                          )
                        : const Icon(Icons.verified_user_outlined, size: 18),
                    label: Text(
                      _codeBusy ? 'Memeriksa kode…' : 'Aktifkan Cabang',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.brandGold,
                      foregroundColor: AppTheme.brandBlueDeep,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _codeBusy ? null : _gantiAkunGoogle,
                  icon: const Icon(Icons.swap_horiz, size: 17),
                  label: const Text('Ganti akun Google'),
                ),
              ] else ...[
                // First layer: Google only. Belum menyentuh server Garudafood;
                // akun apa pun boleh sampai tahap kode cabang.
                _googleButton(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _googleButton() {
    final configured = widget.config.googleAuthConfigured;
    final button = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: (!configured || _googleBusy) ? null : _google,
        icon: _googleBusy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.muted,
                ),
              )
            : const Icon(Icons.g_mobiledata, size: 22),
        label: Text(
          _googleBusy
              ? 'Menunggu browser…'
              : (configured
                    ? 'Masuk dengan Google'
                    : 'Masuk dengan Google (belum diatur)'),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: configured ? AppTheme.fg : AppTheme.muted,
          side: BorderSide(
            color: (configured ? AppTheme.brandGold : AppTheme.muted)
                .withValues(alpha: 0.4),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
    if (configured) return button;
    return Tooltip(
      message:
          'Perlu Google Cloud "Desktop app" OAuth client (loopback) di Pengaturan.',
      child: button,
    );
  }

  InputDecoration _dec(String label, IconData icon) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: AppTheme.muted),
    prefixIcon: Icon(icon, color: AppTheme.muted, size: 20),
    filled: true,
    fillColor: AppTheme.panelAlt,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: AppTheme.muted.withValues(alpha: 0.25)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: AppTheme.brandGold),
    ),
  );
}
