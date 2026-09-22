import 'package:flutter/material.dart';

import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';
import '../widgets/guest_avatar.dart';

/// Semua Profil — daftar SELURUH orang terdaftar di server ini, apa pun
/// jenisnya: tamu, transporter, magang, vendor.
///
/// Namanya dulu "Manajemen Tamu", dan itu menyesatkan: halaman ini tidak
/// pernah menyaring per jenis, jadi transporter selalu ikut terdaftar di sana
/// sejak awal. Yang berubah cuma namanya jadi jujur, plus penyaring supaya
/// operator tidak perlu memindainya dengan mata.
///
/// Sengaja hanya membaca dan meng-PATCH teks profil. Ganti foto referensi,
/// lepas tautan Google, dan hapus tamu **tidak** disediakan di sini dan juga
/// tidak diteruskan oleh sidecar, jadi konsol ini secara fisik tidak bisa
/// merusak data wajah maupun riwayat kunjungan.
class GuestManagementPage extends StatefulWidget {
  final SidecarClient? client;
  const GuestManagementPage({super.key, required this.client});

  @override
  State<GuestManagementPage> createState() => _GuestManagementPageState();
}

/// Keys are the server's own field names — they go straight into the PATCH
/// body, so a typo here would be a silent no-op rather than a compile error.
const _fields = <String, String>{
  'full_name': 'Nama Lengkap',
  'company': 'Perusahaan',
  'phone': 'Telepon',
  'guest_category': 'Kategori Tamu',
  'address': 'Alamat',
  'sim_number': 'Nomor SIM',
  'sim_expires_at': 'SIM Berlaku s/d (YYYY-MM-DD)',
};

const _visitorTypes = <String>['tamu', 'transporter', 'magang', 'vendor'];

class _GuestManagementPageState extends State<GuestManagementPage> {
  final _search = TextEditingController();

  /// Penyaring jenis. `null` = semua, sesuai maksud halaman ini: menampung
  /// SELURUH profil, bukan hanya tamu. Halaman ini memang tidak pernah
  /// menyaring diam-diam -- transporter, magang, dan vendor selalu ikut
  /// terdaftar -- tapi tanpa penyaring, operator harus memindainya dengan mata.
  String? _saringJenis;

  /// Rentang tanggal pendaftaran. Dipakai untuk pertanyaan yang sering muncul
  /// saat audit: "siapa saja yang terdaftar bulan lalu".
  DateTimeRange? _saringTanggal;
  final _ctl = {for (final k in _fields.keys) k: TextEditingController()};

  List<VisitorRecord> _all = [];
  int? _selectedId;
  String _visitorType = 'tamu';
  bool _loading = false;
  bool _saving = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    for (final c in _ctl.values) {
      c.dispose();
    }
    super.dispose();
  }

  VisitorRecord? get _selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final v in _all) {
      if (v.id == id) return v;
    }
    return null;
  }

  List<VisitorRecord> get _filtered => [
        for (final v in _all)
          if (v.matches(_search.text) && _lolosJenis(v) && _lolosTanggal(v)) v,
      ];

  bool _lolosJenis(VisitorRecord v) {
    if (_saringJenis == null) return true;
    // Data lama bisa punya visitor_type kosong. Itu tamu menurut server
    // (kolomnya default 'tamu'), jadi diperlakukan sama di sini -- kalau
    // tidak, profil lama menghilang dari penyaring "Tamu" tanpa penjelasan.
    final jenis = v.visitorType.trim().isEmpty ? 'tamu' : v.visitorType.trim();
    return jenis == _saringJenis;
  }

  bool _lolosTanggal(VisitorRecord v) {
    final r = _saringTanggal;
    if (r == null) return true;
    final t = v.createdAt;
    // Tanpa tanggal pendaftaran, tidak ada dasar untuk memasukkan maupun
    // membuangnya. Dibuang, supaya hitungan "terdaftar periode ini" tidak
    // ikut menghitung yang tanggalnya tidak diketahui.
    if (t == null) return false;
    final hari = DateTime(t.year, t.month, t.day);
    final awal = DateTime(r.start.year, r.start.month, r.start.day);
    final akhir = DateTime(r.end.year, r.end.month, r.end.day);
    return !hari.isBefore(awal) && !hari.isAfter(akhir);
  }

  /// What the form currently holds, in the server's field names.
  Map<String, String> get _edited => {
        for (final e in _ctl.entries) e.key: e.value.text.trim(),
        'visitor_type': _visitorType,
      };

  bool get _dirty {
    final sel = _selected;
    return sel != null && sel.diff(_edited).isNotEmpty;
  }

  Future<void> _load() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _error = 'Sidecar belum berjalan.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _notice = null;
    });
    try {
      final list = await client.visitors();
      if (!mounted) return;
      setState(() {
        _all = list;
        // Keep the current selection across a refresh when that guest still
        // exists; drop it silently when they no longer do.
        if (_selectedId != null && !list.any((v) => v.id == _selectedId)) {
          _selectedId = null;
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _select(VisitorRecord v) {
    setState(() {
      _selectedId = v.id;
      _visitorType = _visitorTypes.contains(v.visitorType) ? v.visitorType : 'tamu';
      _notice = null;
      _error = null;
      final source = v.editable;
      for (final e in _ctl.entries) {
        e.value.text = source[e.key] ?? '';
      }
    });
  }

  Future<void> _save() async {
    final client = widget.client;
    final sel = _selected;
    if (client == null || sel == null) return;
    final changed = sel.diff(_edited);
    if (changed.isEmpty) {
      setState(() => _notice = 'Tidak ada perubahan untuk disimpan.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _notice = null;
    });
    try {
      final updated = await client.updateVisitor(sel.id, changed);
      if (!mounted) return;
      setState(() {
        if (updated != null) {
          // Replace with the server's copy, then re-fill the form from it —
          // if the server normalised something (an unknown visitor_type
          // becomes 'tamu'), the operator sees what was actually stored
          // rather than what they typed.
          _all = [for (final v in _all) v.id == updated.id ? updated : v];
          _select(updated);
        }
        _notice = 'Tersimpan: ${changed.length} kolom diperbarui.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _clean(Object e) =>
      e.toString().replaceFirst('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Semua Profil',
            subtitle: _all.isEmpty
                ? 'Data profil tamu terdaftar — hanya teks profil yang bisa diubah'
                : '${_all.length} tamu terdaftar — hanya teks profil yang bisa diubah',
            icon: Icons.people_alt_outlined,
            actions: [
              ConsoleRefreshButton(busy: _loading, onPressed: _load),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 330, child: _listPane()),
                const SizedBox(width: 16),
                Expanded(child: _detailPane()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _listPane() {
    final rows = _filtered;
    return Container(
      decoration: consolePanel(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppTheme.fg, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Cari nama, perusahaan, telepon, kode, email…',
                hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.muted),
                isDense: true,
                filled: true,
                fillColor: AppTheme.panelAlt.withValues(alpha: 0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          _barisPenyaring(rows.length),
          Expanded(
            child: _buildListBody(rows),
          ),
        ],
      ),
    );
  }

  Widget _barisPenyaring(int jumlah) {
    const jenis = <String?, String>{
      null: 'Semua',
      'tamu': 'Tamu',
      'transporter': 'Transporter',
      'magang': 'Magang',
      'vendor': 'Vendor',
    };
    final r = _saringTanggal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in jenis.entries)
                ChoiceChip(
                  label: Text(e.value, style: const TextStyle(fontSize: 11.5)),
                  selected: _saringJenis == e.key,
                  onSelected: (_) => setState(() => _saringJenis = e.key),
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    color: _saringJenis == e.key
                        ? AppTheme.brandBlueDeep
                        : AppTheme.muted,
                  ),
                  selectedColor: AppTheme.brandGold,
                  backgroundColor: AppTheme.panelAlt.withValues(alpha: 0.6),
                  side: BorderSide.none,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pilihRentang,
                  icon: const Icon(Icons.date_range, size: 15),
                  label: Text(
                    r == null
                        ? 'Semua tanggal daftar'
                        : '${_tgl(r.start)} – ${_tgl(r.end)}',
                    style: const TextStyle(fontSize: 11.5),
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.muted,
                    side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              if (r != null)
                IconButton(
                  tooltip: 'Hapus penyaring tanggal',
                  icon: const Icon(Icons.close, size: 16, color: AppTheme.muted),
                  onPressed: () => setState(() => _saringTanggal = null),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '$jumlah profil ditampilkan dari ${_all.length}',
            style: const TextStyle(color: AppTheme.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  static String _tgl(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  Future<void> _pilihRentang() async {
    final kini = DateTime.now();
    final hasil = await showDateRangePicker(
      context: context,
      // 2024 sebagai batas bawah: server ini belum ada sebelum itu, dan
      // membuka kalender sampai tahun 1900 hanya menyulitkan penggulungan.
      firstDate: DateTime(2024),
      lastDate: DateTime(kini.year + 1),
      initialDateRange: _saringTanggal,
    );
    if (hasil != null) setState(() => _saringTanggal = hasil);
  }

  Widget _buildListBody(List<VisitorRecord> rows) {
    if (_loading && _all.isEmpty) {
      return const ConsoleMessage(
        icon: Icons.hourglass_top,
        text: 'Memuat data profil…',
      );
    }
    if (_all.isEmpty) {
      return ConsoleMessage(
        icon: Icons.people_outline,
        text: _error ?? 'Belum ada profil terdaftar di server ini.',
        tone: _error != null ? AppTheme.badRed : null,
      );
    }
    if (rows.isEmpty) {
      return const ConsoleMessage(
        icon: Icons.search_off,
        text: 'Tidak ada profil yang cocok dengan pencarian atau penyaring.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: rows.length,
      itemBuilder: (_, i) => _listRow(rows[i]),
    );
  }

  Widget _listRow(VisitorRecord v) {
    final selected = v.id == _selectedId;
    return Material(
      color: selected ? AppTheme.brandGold.withValues(alpha: 0.14) : Colors.transparent,
      child: InkWell(
        onTap: () => _select(v),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: selected ? AppTheme.brandGold : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            children: [
              GuestAvatar(
                client: widget.client,
                photoUrl: v.photoUrl,
                name: v.fullName,
                size: 40,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      v.fullName.isEmpty ? '(tanpa nama)' : v.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selected ? AppTheme.fg : AppTheme.fg.withValues(alpha: 0.9),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      v.company.isEmpty ? v.visitorCode : '${v.visitorCode} · ${v.company}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                    ),
                    if (v.email.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            // Tertaut Google vs baru dijanjikan adalah dua hal
                            // berbeda, dan operator perlu bisa membedakannya
                            // sekilas: yang satu sudah diverifikasi Google,
                            // yang satu baru alamat yang diisi petugas.
                            v.googleLinked
                                ? Icons.verified_user_outlined
                                : Icons.mail_outline,
                            size: 11,
                            color: v.googleLinked
                                ? AppTheme.okGreen
                                : AppTheme.muted,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              v.email,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppTheme.muted, fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (v.createdAt != null)
                Text(
                  _tgl(v.createdAt!),
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailPane() {
    final v = _selected;
    if (v == null) {
      return Container(
        decoration: consolePanel(subtle: true),
        child: const ConsoleMessage(
          icon: Icons.badge_outlined,
          text: 'Pilih satu profil di daftar kiri untuk melihat dan '
              'menyuntingnya. Daftar itu memuat semua jenis — tamu, '
              'transporter, magang, dan vendor.',
        ),
      );
    }
    return Container(
      decoration: consolePanel(subtle: true),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _detailHeader(v),
          const Divider(color: AppTheme.panelAlt, height: 26),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _typeSelector(),
                  const SizedBox(height: 14),
                  // Kategori Tamu tidak relevan untuk transporter -- sopir
                  // tidak punya padanan konsep itu. Sebaliknya, SIM cuma
                  // milik transporter -- tamu/magang/vendor tidak pernah
                  // diminta nomor SIM.
                  for (final e in _fields.entries)
                    if (_fieldRelevan(e.key)) ...[
                      _field(e.key, e.value),
                      const SizedBox(height: 12),
                    ],
                  _readOnlyFacts(v),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          _saveRow(),
        ],
      ),
    );
  }

  Widget _detailHeader(VisitorRecord v) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GuestAvatar(
          client: widget.client,
          photoUrl: v.photoUrl,
          name: v.fullName,
          size: 62,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.fullName.isEmpty ? '(tanpa nama)' : v.fullName,
                style: const TextStyle(
                  color: AppTheme.fg,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ConsolePill(text: v.visitorCode, tone: AppTheme.accent),
                  ConsolePill(
                    text: v.googleLinked ? 'Google tertaut' : 'Tanpa Google',
                    tone: v.googleLinked ? AppTheme.okGreen : AppTheme.muted,
                  ),
                  // Tanpa penanda ini, operator melihat nomor telepon kosong
                  // lalu mengira datanya belum selesai diisi -- dan mencoba
                  // melengkapi nomor yang memang tidak pernah ada.
                  if (v.walkIn)
                    const ConsolePill(text: 'Tanpa HP', tone: AppTheme.brandGold),
                  if (v.safetyScore > 0)
                    ConsolePill(
                      text: 'Safety ${v.safetyScore}',
                      tone: AppTheme.brandGold,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _typeSelector() {
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            'Jenis Pengunjung',
            style: TextStyle(
              color: AppTheme.muted.withValues(alpha: 0.9),
              fontSize: 12,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.panelAlt.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(10),
          ),
          child: DropdownButton<String>(
            value: _visitorType,
            underline: const SizedBox.shrink(),
            dropdownColor: AppTheme.panel,
            style: const TextStyle(color: AppTheme.fg, fontSize: 13),
            items: [
              for (final t in _visitorTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: _saving ? null : (t) => setState(() => _visitorType = t ?? 'tamu'),
          ),
        ),
      ],
    );
  }

  /// `guest_category` hanya untuk non-transporter; `sim_*` hanya untuk
  /// transporter. Semua field lain selalu relevan.
  bool _fieldRelevan(String key) {
    if (key == 'guest_category') return _visitorType != 'transporter';
    if (key.startsWith('sim_')) return _visitorType == 'transporter';
    return true;
  }

  Widget _field(String key, String label) {
    final multiline = key == 'address';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: SizedBox(
            width: 130,
            child: Text(
              label,
              style: TextStyle(
                color: AppTheme.muted.withValues(alpha: 0.9),
                fontSize: 12,
              ),
            ),
          ),
        ),
        Expanded(
          child: TextField(
            controller: _ctl[key],
            enabled: !_saving,
            maxLines: multiline ? 3 : 1,
            onChanged: (_) => setState(() {}), // keeps the Save button honest
            style: const TextStyle(color: AppTheme.fg, fontSize: 13),
            decoration: InputDecoration(
              hintStyle: const TextStyle(color: AppTheme.muted, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: AppTheme.panelAlt.withValues(alpha: 0.5),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyFacts(VisitorRecord v) {
    final facts = <String, String>{
      'Terdaftar': dateTimeLabel(v.createdAt),
      if (v.purpose.isNotEmpty) 'Keperluan (lama)': v.purpose,
    };
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelAlt.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final f in facts.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 118,
                    child: Text(
                      f.key,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11.5),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      f.value,
                      style: const TextStyle(color: AppTheme.fg, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          const Text(
            'Kode tamu, tautan Google, dan data wajah tidak bisa diubah dari '
            'konsol ini.',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 10.5,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }

  Widget _saveRow() {
    final message = _error ?? _notice;
    return Row(
      children: [
        Expanded(
          child: message == null
              ? const SizedBox.shrink()
              : Text(
                  message,
                  style: TextStyle(
                    color: _error != null ? AppTheme.badRed : AppTheme.okGreen,
                    fontSize: 12,
                  ),
                ),
        ),
        FilledButton.icon(
          onPressed: (_saving || !_dirty) ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.brandBlueDeep,
                  ),
                )
              : const Icon(Icons.save_outlined, size: 18),
          label: Text(_saving ? 'Menyimpan…' : 'Simpan Perubahan'),
          style: FilledButton.styleFrom(
            backgroundColor: AppTheme.brandGold,
            foregroundColor: AppTheme.brandBlueDeep,
            disabledBackgroundColor: AppTheme.panelAlt,
            disabledForegroundColor: AppTheme.muted,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
      ],
    );
  }
}
