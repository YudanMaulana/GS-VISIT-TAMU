import 'package:flutter/material.dart';

import '../camera_slot.dart';
import '../config.dart';
import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';

/// Edits the sidecar paths, the camera grid (one or more slots -- laptop/USB
/// webcams and/or ESP32-CAMs, each gets its own sidecar process), and server
/// config. Returns the new AppConfig (already persisted) or null if cancelled.
class SettingsDialog extends StatefulWidget {
  final AppConfig config;
  /// One of the running sidecars' client, used to fetch the branch list and
  /// enumerate local webcams. Null when no sidecar is up (e.g. opened from
  /// the failure screen) — those fields then fall back to read-only/manual.
  final SidecarClient? client;

  const SettingsDialog({super.key, required this.config, this.client});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final AppConfig _c = widget.config.copy();
  late final _python = TextEditingController(text: _c.pythonPath);
  late final _sidecar = TextEditingController(text: _c.sidecarPath);
  late final _baseUrl = TextEditingController(text: _c.baseUrl);
  late final _apiKey = TextEditingController(text: _c.apiKey);
  late final _googleClientId = TextEditingController(text: _c.googleClientId);
  late final _googleClientSecret =
      TextEditingController(text: _c.googleClientSecret);
  late final _adminResetToken =
      TextEditingController(text: _c.adminResetToken);

  bool _loadingBranches = true;
  String _branchError = '';
  List<Branch> _branches = const [];
  Branch? _selectedBranch;

  /// Cabang menurut kredensial mesin ini, kalau server bisa menjawabnya.
  ///
  /// Begitu ini terisi, cabang berhenti jadi sesuatu yang diketik: ia berasal
  /// dari kode konsol / token papan yang dipegang mesin, jadi kredensial dan
  /// cabang tidak mungkin berbeda. Dropdown lama tetap ada sebagai jalan
  /// mundur untuk mesin yang belum diberi kode -- mencabutnya lebih dulu akan
  /// mengunci mesin itu di tengah shift.
  Branch? _cabangKredensial;
  String _labelKredensial = '';

  // Shared across every camera slot editor below -- fetched once, not once
  // per slot.
  bool _loadingCameras = true;
  String _cameraError = '';
  List<CameraDevice> _cameras = const [];

  @override
  void initState() {
    super.initState();
    _loadBranches();
    _muatCabangKredensial();
    _loadCameras();
  }

  Future<void> _loadCameras() async {
    final client = widget.client;
    if (client == null) {
      setState(() {
        _loadingCameras = false;
        _cameraError = 'Sidecar belum berjalan — tidak bisa mendeteksi kamera.';
      });
      return;
    }
    try {
      final body = await client.cameras();
      if (!mounted) return;
      if (body['ok'] != true) {
        setState(() {
          _loadingCameras = false;
          _cameraError = (body['error'] as String?) ?? 'Gagal mendeteksi kamera.';
        });
        return;
      }
      final list = (body['cameras'] as List<dynamic>? ?? [])
          .map((e) => CameraDevice.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _loadingCameras = false;
        _cameras = list;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingCameras = false;
        _cameraError = 'Gagal mendeteksi kamera: $e';
      });
    }
  }

  Future<void> _muatCabangKredensial() async {
    final client = widget.client;
    if (client == null) return;
    try {
      final env = await client.branchOfCredential();
      final body = env['body'];
      if (env['ok'] != true || body is! Map) return;
      final id = (body['branch_id'] as num?)?.toInt();
      final nama = (body['branch_name'] as String?)?.trim() ?? '';
      if (id == null || nama.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _cabangKredensial = Branch(
          id: id,
          code: (body['branch_code'] as String?)?.trim() ?? '',
          name: nama,
        );
        _labelKredensial = (body['label'] as String?)?.trim() ?? '';
        // Config ikut diselaraskan langsung. Kalau hanya ditampilkan tanpa
        // disimpan, mesin tetap mengirim cabang lama yang salah sampai
        // seseorang membuka Pengaturan dan menekan Simpan.
        _c.branchId = id;
        _c.branchName = nama;
      });
      await _c.save();
    } catch (_) {
      // Diam saja: mesin yang belum punya kredensial cabang tetap memakai
      // dropdown di bawah, dan itu jalur yang sah selama masa peralihan.
    }
  }

  Future<void> _loadBranches() async {
    final client = widget.client;
    if (client == null) {
      setState(() {
        _loadingBranches = false;
        _branchError = 'Sidecar belum berjalan — tidak bisa memuat daftar cabang.';
      });
      return;
    }
    try {
      final body = await client.branches();
      if (!mounted) return;
      if (body['ok'] != true) {
        setState(() {
          _loadingBranches = false;
          _branchError = (body['error'] as String?) ?? 'Gagal memuat daftar cabang.';
        });
        return;
      }
      final respBody = body['body'] as Map<String, dynamic>?;
      final list = (respBody?['branches'] as List<dynamic>? ?? [])
          .map((e) => Branch.fromJson(e as Map<String, dynamic>))
          .toList();
      final matches = list.where((b) => b.id == _c.branchId);
      setState(() {
        _loadingBranches = false;
        _branches = list;
        // Keep the previously-saved branch selected if it's still in the list.
        _selectedBranch = matches.isEmpty ? null : matches.first;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingBranches = false;
        _branchError = 'Gagal memuat daftar cabang: $e';
      });
    }
  }

  void _addSlot() {
    setState(() {
      _c.cameraSlots.add(CameraSlot(label: 'Kamera ${_c.cameraSlots.length + 1}'));
    });
  }

  void _removeSlot(CameraSlot slot) {
    setState(() => _c.cameraSlots.remove(slot));
  }

  @override
  void dispose() {
    for (final ctl in [
      _python,
      _sidecar,
      _baseUrl,
      _apiKey,
      _googleClientId,
      _googleClientSecret,
      _adminResetToken,
    ]) {
      ctl.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.panel,
      title: const Text('Settings', style: TextStyle(color: AppTheme.fg)),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _field('Python interpreter (.venv/bin/python)', _python),
              _field('sidecar.py path', _sidecar),
              const Divider(height: 24),
              Row(
                children: [
                  const Expanded(
                    child: Text('Kamera (grid CCTV)',
                        style: TextStyle(
                            color: AppTheme.fg, fontSize: 14, fontWeight: FontWeight.w700)),
                  ),
                  TextButton.icon(
                    onPressed: _addSlot,
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Tambah Kamera'),
                  ),
                ],
              ),
              const Text(
                'Tiap kamera aktif dijalankan bersamaan (deteksi wajah sendiri-sendiri) '
                'dan ditampilkan sebagai satu panel di grid. Siapa pun yang dikenali di '
                'kamera manapun bisa check-in/check-out.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              for (final slot in _c.cameraSlots)
                _CameraSlotEditor(
                  key: ObjectKey(slot),
                  slot: slot,
                  cameras: _cameras,
                  camerasLoading: _loadingCameras,
                  camerasError: _cameraError,
                  onReloadCameras: () {
                    setState(() {
                      _loadingCameras = true;
                      _cameraError = '';
                    });
                    _loadCameras();
                  },
                  onRemove: () => _removeSlot(slot),
                ),
              if (_c.cameraSlots.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    'Belum ada kamera — grid akan kosong. Tambah minimal satu.',
                    style: TextStyle(color: AppTheme.warnAmber, fontSize: 11.5),
                  ),
                ),
              const Divider(height: 24),
              _field('Server base URL (blank = default)', _baseUrl),
              _field('Server API key (X-API-Key)', _apiKey, obscure: true),
              // Kredensial terpisah dari API key di atas, dan memang harus
              // begitu: yang satu membaca data, yang satu menulis kunjungan.
              //
              // Isi dengan TOKEN PAPAN milik pos ini, bukan token admin penuh.
              // Token papan hanya bisa checkin/checkout dan membaca papan tamu;
              // token admin penuh bisa mengosongkan basis data, dan menaruhnya
              // di tiap mesin pos berarti tiap mesin memegang kunci itu.
              //
              // Dipakai sebagai cadangan saat sesi admin habis. Sesi admin
              // berumur 12 jam, sementara kiosk jalan terus -- tanpa token di
              // sini, check-in akan mulai ditolak 401 di tengah shift.
              // Halaman Reset Data sendiri tetap menuntut login admin, karena
              // token papan memang ditolak 403 di sana.
              _field('Token papan pos (X-Admin-Token)', _adminResetToken,
                  obscure: true),
              const SizedBox(height: 12),
              _branchField(),
              const Divider(height: 24),
              _googleAuthSection(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text('Auto-submit captures:',
                      style: TextStyle(color: AppTheme.muted)),
                  const SizedBox(width: 12),
                  DropdownButton<String>(
                    value: _c.submitMode,
                    dropdownColor: AppTheme.panelAlt,
                    items: const [
                      DropdownMenuItem(value: 'none', child: Text('none')),
                      DropdownMenuItem(value: 'checkin', child: Text('checkin')),
                      DropdownMenuItem(value: 'checkout', child: Text('checkout')),
                      DropdownMenuItem(value: 'register', child: Text('register')),
                    ],
                    onChanged: (v) => setState(() => _c.submitMode = v ?? 'none'),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto-identify (nama di bounding box)',
                    style: TextStyle(color: AppTheme.fg, fontSize: 14)),
                subtitle: const Text(
                  'Kenali wajah otomatis lewat /api/visitors/identify — tanpa '
                  'membuat catatan kunjungan. Satu permintaan per wajah baru, '
                  'bukan per frame.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                value: _c.autoIdentify,
                onChanged: (v) => setState(() {
                  _c.autoIdentify = v;
                  // Auto check-in diputuskan dari hasil identify; tanpa
                  // identify tidak ada yang memicunya, jadi jangan tinggalkan
                  // saklar yang menyala tapi tidak berefek apa-apa.
                  if (!v) _c.autoCheckin = false;
                }),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Auto check-in',
                    style: TextStyle(color: AppTheme.fg, fontSize: 14)),
                subtitle: Text(
                  _c.branchId == null
                      ? 'Perlu cabang POS diatur dulu di atas.'
                      : 'Check-in otomatis begitu wajah dikenali DAN tamu punya '
                          'rencana kunjungan berstatus "planned" di cabang ini. '
                          'Tamu tanpa rencana diabaikan, yang sudah lewat gerbang '
                          'tidak di-check-in ulang. Satu percobaan per wajah.',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
                value: _c.autoCheckin,
                // Mati kalau prasyaratnya belum ada -- lebih baik tidak bisa
                // dinyalakan daripada menyala diam-diam tanpa efek.
                onChanged: (_c.autoIdentify && _c.branchId != null)
                    ? (v) => setState(() => _c.autoCheckin = v)
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mirror video (selfie view)',
                    style: TextStyle(color: AppTheme.fg, fontSize: 14)),
                value: _c.mirror,
                onChanged: (v) => setState(() => _c.mirror = v),
              ),
              const SizedBox(height: 4),
              const Text(
                'Saving restarts every camera\'s sidecar so changes take effect.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () async {
            _c
              ..pythonPath = _python.text.trim()
              ..sidecarPath = _sidecar.text.trim()
              ..baseUrl = _baseUrl.text.trim()
              ..apiKey = _apiKey.text.trim()
              ..googleClientId = _googleClientId.text.trim()
              ..googleClientSecret = _googleClientSecret.text.trim()
              ..adminResetToken = _adminResetToken.text.trim();
            if (_selectedBranch != null) {
              _c.branchId = _selectedBranch!.id;
              _c.branchName = _selectedBranch!.name;
            }
            await _c.save();
            if (context.mounted) Navigator.pop(context, _c);
          },
          child: const Text('Save & restart'),
        ),
      ],
    );
  }

  /// Fase 2: check-in is rejected server-side without a branch_id, matched
  /// against the guest's own visit plan for that branch. A dropdown (not a
  /// raw id field) so the operator can't typo their way into a silent
  /// mismatch.
  Widget _branchField() {
    final dariKredensial = _cabangKredensial;
    if (dariKredensial != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppTheme.muted.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_outlined, size: 16, color: AppTheme.okGreen),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cabang POS ini: ${dariKredensial.name}',
                      style: const TextStyle(color: AppTheme.fg, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    _labelKredensial.isEmpty
                        ? 'Mengikuti kredensial mesin ini — tidak bisa diketik manual.'
                        : 'Terdaftar sebagai "$_labelKredensial" — mengikuti '
                            'kredensial, tidak bisa diketik manual.',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (_loadingBranches) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Memuat daftar cabang…', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
      );
    }
    if (_branchError.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.error_outline, size: 14, color: AppTheme.badRed),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_branchError,
                    style: const TextStyle(color: AppTheme.badRed, fontSize: 11)),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _loadingBranches = true;
                    _branchError = '';
                  });
                  _loadBranches();
                },
                child: const Text('Muat ulang', style: TextStyle(fontSize: 11)),
              ),
            ]),
            if (_c.branchName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Cabang tersimpan: ${_c.branchName}',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
              ),
          ],
        ),
      );
    }
    return DropdownButtonFormField<Branch>(
      initialValue: _selectedBranch,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Cabang POS ini *',
        labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
        isDense: true,
        border: OutlineInputBorder(),
        helperText: 'Wajib — check-in ditolak server tanpa ini (Fase 2).',
        helperStyle: TextStyle(color: AppTheme.muted, fontSize: 10.5),
      ),
      dropdownColor: AppTheme.panelAlt,
      style: const TextStyle(color: AppTheme.fg, fontSize: 13),
      items: _branches
          .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
          .toList(),
      onChanged: (b) => setState(() => _selectedBranch = b),
    );
  }

  /// Kredensial untuk lapis kedua login admin (tombol "Masuk dengan Google" di
  /// dialog login). Diisi di sini, bukan di source, supaya secret-nya tidak
  /// ikut ter-commit -- dan karena tiap device punya prefs sendiri, device baru
  /// hasil deploy memang mulai kosong. Selama kosong, tombol Google-nya tetap
  /// mati dan hanya email+password yang membuka kunci.
  Widget _googleAuthSection() {
    final terisi = _googleClientId.text.trim().isNotEmpty &&
        _googleClientSecret.text.trim().isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text('Login admin dengan Google (opsional)',
                  style: TextStyle(
                      color: AppTheme.fg,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
            ),
            Text(
              terisi ? 'aktif' : 'belum diatur',
              style: TextStyle(
                color: terisi ? AppTheme.brandGold : AppTheme.muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const Text(
          'Dari Google Cloud Console: OAuth client bertipe "Desktop app" '
          '(alurnya loopback + PKCE lewat browser). Kosongkan keduanya untuk '
          'mematikan lapis ini -- login admin lalu hanya lewat email+password.',
          style: TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
        // Status di atas ikut berubah begitu diketik, jadi tidak perlu simpan
        // dulu untuk tahu apakah tombolnya akan hidup.
        _field('Google OAuth Client ID (Desktop app)', _googleClientId,
            onChanged: (_) => setState(() {})),
        _field('Google OAuth Client Secret', _googleClientSecret,
            obscure: true, onChanged: (_) => setState(() {})),
      ],
    );
  }

  Widget _field(String label, TextEditingController ctl,
      {bool obscure = false,
      TextInputType? keyboardType,
      ValueChanged<String>? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: ctl,
        obscureText: obscure,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(color: AppTheme.fg, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

/// One camera slot's editor: enable + label + Local/ESP32-CAM toggle + the
/// matching picker. Mutates [slot] directly (it's the same object living in
/// the parent's `AppConfig.cameraSlots`), so there's nothing to sync back at
/// Save time -- the parent just persists `_c` as-is.
class _CameraSlotEditor extends StatefulWidget {
  final CameraSlot slot;
  final List<CameraDevice> cameras;
  final bool camerasLoading;
  final String camerasError;
  final VoidCallback onReloadCameras;
  final VoidCallback onRemove;

  const _CameraSlotEditor({
    super.key,
    required this.slot,
    required this.cameras,
    required this.camerasLoading,
    required this.camerasError,
    required this.onReloadCameras,
    required this.onRemove,
  });

  @override
  State<_CameraSlotEditor> createState() => _CameraSlotEditorState();
}

class _CameraSlotEditorState extends State<_CameraSlotEditor> {
  late final _label = TextEditingController(text: widget.slot.label);
  late final _localIndex = TextEditingController(text: '${widget.slot.localIndex}');
  late final _cameraUrl = TextEditingController(text: widget.slot.cameraUrl);
  late final _captureUrl = TextEditingController(text: widget.slot.captureUrl);

  @override
  void dispose() {
    for (final c in [_label, _localIndex, _cameraUrl, _captureUrl]) {
      c.dispose();
    }
    super.dispose();
  }

  CameraDevice? get _matchedDevice {
    final matches = widget.cameras.where((c) => c.index == widget.slot.localIndex);
    return matches.isEmpty ? null : matches.first;
  }

  @override
  Widget build(BuildContext context) {
    final slot = widget.slot;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelAlt.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.panelAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: slot.enabled,
                activeColor: AppTheme.brandGold,
                onChanged: (v) => setState(() => slot.enabled = v ?? true),
              ),
              Expanded(
                child: TextField(
                  controller: _label,
                  style: const TextStyle(color: AppTheme.fg, fontSize: 13),
                  decoration: const InputDecoration(
                    labelText: 'Label kamera',
                    labelStyle: TextStyle(color: AppTheme.muted, fontSize: 11),
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => slot.label = v,
                ),
              ),
              IconButton(
                tooltip: 'Hapus kamera ini',
                icon: const Icon(Icons.delete_outline, color: AppTheme.badRed, size: 20),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Kamera Lokal'), icon: Icon(Icons.usb, size: 14)),
              ButtonSegment(value: true, label: Text('ESP32-CAM'), icon: Icon(Icons.wifi, size: 14)),
            ],
            selected: {slot.isNetwork},
            onSelectionChanged: (s) => setState(() => slot.isNetwork = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              backgroundColor: WidgetStateProperty.resolveWith(
                (states) =>
                    states.contains(WidgetState.selected) ? AppTheme.brandGold : AppTheme.panel,
              ),
              foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppTheme.brandBlueDeep
                    : AppTheme.fg,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (slot.isNetwork) _networkFields(slot) else _localField(slot),
        ],
      ),
    );
  }

  Widget _localField(CameraSlot slot) {
    if (widget.camerasLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Mendeteksi kamera…', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
        ]),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.camerasError.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              const Icon(Icons.error_outline, size: 14, color: AppTheme.warnAmber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.camerasError,
                    style: const TextStyle(color: AppTheme.warnAmber, fontSize: 11)),
              ),
              TextButton(
                onPressed: widget.onReloadCameras,
                child: const Text('Muat ulang', style: TextStyle(fontSize: 11)),
              ),
            ]),
          )
        else if (widget.cameras.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: DropdownButtonFormField<CameraDevice>(
              initialValue: _matchedDevice,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Kamera terdeteksi',
                labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              dropdownColor: AppTheme.panelAlt,
              style: const TextStyle(color: AppTheme.fg, fontSize: 13),
              items: widget.cameras
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text('${c.name} (${c.device})', overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (c) => setState(() {
                if (c != null) {
                  slot.localIndex = c.index;
                  _localIndex.text = '${c.index}';
                }
              }),
            ),
          ),
        TextField(
          controller: _localIndex,
          keyboardType: TextInputType.number,
          style: const TextStyle(color: AppTheme.fg, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'Camera index (manual/lanjutan)',
            labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => slot.localIndex = int.tryParse(v.trim()) ?? 0,
        ),
      ],
    );
  }

  Widget _networkFields(CameraSlot slot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ESP32-CAM di jaringan lokal. Lihat esp32cam_garudafood/README.md.',
          style: TextStyle(color: AppTheme.muted, fontSize: 11),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _cameraUrl,
          style: const TextStyle(color: AppTheme.fg, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'URL stream (mis. http://192.168.1.50:81/stream)',
            labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => slot.cameraUrl = v.trim(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _captureUrl,
          style: const TextStyle(color: AppTheme.fg, fontSize: 13),
          decoration: const InputDecoration(
            labelText: 'URL capture resolusi tinggi (opsional)',
            labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => slot.captureUrl = v.trim(),
        ),
      ],
    );
  }
}
