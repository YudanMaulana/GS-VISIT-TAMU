import 'package:flutter/material.dart';

import '../config.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

/// Reset Data — alat masa pengujian: mengosongkan data kunjungan (atau seluruh
/// data tamu) di server lewat `POST /api/admin/reset`.
///
/// Halaman ini sengaja dibuat lambat dipakai, bukan nyaman:
///
///   * **Pratinjau dulu.** Tombol jalankan baru hidup setelah `dry_run`
///     memperlihatkan berapa baris dan berapa foto yang akan hilang. Angka itu
///     datang dari jalur kode yang sama dengan eksekusi sungguhan, jadi bukan
///     tebakan GUI.
///   * **Kalimatnya diketik operator.** GUI tahu kalimat yang benar, tapi tidak
///     mengisinya — kalau tombol mengisi sendiri, penjagaannya tinggal nama.
///   * **Lokasi backup ditampilkan.** Server menyalin DB + foto sebelum baris
///     pertama dihapus; kalau operator salah pencet, jawaban "ke mana data
///     lama pergi" harus ada di layar, bukan di log yang tak pernah dibuka.
class ResetDataPage extends StatefulWidget {
  final SidecarClient? client;
  final AppConfig config;

  const ResetDataPage({super.key, required this.client, required this.config});

  @override
  State<ResetDataPage> createState() => _ResetDataPageState();
}

/// Kalimat konfirmasi per lingkup. Harus sama persis dengan yang divalidasi
/// server (face_parity/server.py RESET_CONFIRMATIONS) -- kalau tidak, operator
/// mengetik dengan benar tapi tetap ditolak.
const _scopes = <_ResetScope>[
  _ResetScope(
    key: 'visits',
    title: 'Riwayat kunjungan',
    confirmation: 'HAPUS RIWAYAT KUNJUNGAN',
    // "bongkar", "muat", atau keduanya sekaligus -- disebut bersama di sini
    // karena ketiganya sama-sama hilang bersama rencananya. Operator tidak
    // perlu tahu nilai enum-nya, cukup tahu bahwa jenis kedatangan ikut hilang.
    lost:
        'Rencana kunjungan (termasuk rencana transporter -- bongkar, muat, '
        'atau keduanya -- beserta baris muatannya), riwayat check-in/out, dan '
        'foto serta tanda tangan milik baris-baris itu.',
    kept:
        'Orangnya sendiri tetap ada: tamu, sopir, wajah terdaftar, nomor '
        'SIM, dan perangkat tepercaya.',
  ),
  _ResetScope(
    key: 'internships',
    title: 'Data magang',
    confirmation: 'HAPUS DATA MAGANG',
    lost:
        'Kontrak magang, jadwal kerja, titik absensi cabang, dan log '
        'check-in/check-out magang untuk masa testing.',
    kept:
        'Profil visitor magang, embedding wajah, akun Google, dan data tamu '
        'lain tetap ada.',
  ),
  _ResetScope(
    key: 'guests',
    title: 'Semua data tamu',
    confirmation: 'HAPUS SEMUA DATA TAMU',
    lost:
        'Semua di atas, ditambah data tamu dan sopir, embedding wajah, '
        'nomor SIM, perangkat tepercaya, OTP, dan seluruh isi folder foto.',
    kept:
        'Katalog (cabang, area, kategori, wilayah, materi safety) tidak '
        'pernah ikut terhapus.',
  ),
];

class _ResetScope {
  final String key;
  final String title;
  final String confirmation;
  final String lost;
  final String kept;

  const _ResetScope({
    required this.key,
    required this.title,
    required this.confirmation,
    required this.lost,
    required this.kept,
  });
}

class _ResetDataPageState extends State<ResetDataPage> {
  _ResetScope _scope = _scopes.first;
  final _confirm = TextEditingController();

  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _preview; // hasil dry_run untuk _scope saat ini
  Map<String, dynamic>? _done; // hasil eksekusi sungguhan

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  /// Ganti lingkup = pratinjau dan kalimat yang sudah diketik tidak berlaku
  /// lagi. Dibuang, bukan dibiarkan: pratinjau milik lingkup lain adalah cara
  /// paling mudah menghapus lebih banyak daripada yang dikira operator.
  void _selectScope(_ResetScope s) {
    if (s.key == _scope.key) return;
    setState(() {
      _scope = s;
      _preview = null;
      _done = null;
      _error = null;
      _confirm.clear();
    });
  }

  Future<void> _run({required bool dryRun}) async {
    final client = widget.client;
    if (client == null) {
      setState(() => _error = 'Sidecar belum berjalan.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      if (dryRun) _done = null;
    });
    try {
      final res = await client.adminReset(
        scope: _scope.key,
        dryRun: dryRun,
        confirm: dryRun ? null : _confirm.text,
      );
      if (!mounted) return;
      final body = _body(res);
      if (res['ok'] != true || body == null) {
        setState(() => _error = _messageOf(res, body));
        return;
      }
      setState(() {
        if (dryRun) {
          _preview = body;
        } else {
          _done = body;
          _preview = null;
          _confirm.clear();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic>? _body(Map<String, dynamic> res) {
    final b = res['body'];
    return b is Map<String, dynamic> ? b : null;
  }

  String _messageOf(Map<String, dynamic> res, Map<String, dynamic>? body) {
    final fromBody = body?['message'] ?? body?['detail'];
    final err = res['error'] ?? fromBody;
    final status = res['status'];
    if (status == 401 || status == 403) {
      return 'Ditolak server ($status): token reset salah atau belum diatur.';
    }
    return err?.toString() ?? 'Gagal menjalankan reset.';
  }

  @override
  Widget build(BuildContext context) {
    final armed = widget.config.adminResetConfigured;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const ConsoleHeader(
            title: 'Reset Data',
            subtitle:
                'Alat masa pengujian — mengosongkan data di server, '
                'bukan hanya di POS ini.',
            icon: Icons.delete_forever_outlined,
            badgeText: 'PENGUJIAN',
          ),
          const SizedBox(height: 14),
          if (!armed)
            const Expanded(
              child: ConsoleMessage(
                icon: Icons.lock_outline,
                text:
                    'Token reset belum diatur.\nIsi "Token reset data" di '
                    'Pengaturan untuk menghidupkan halaman ini.',
              ),
            )
          else
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _scopePicker(),
                    const SizedBox(height: 14),
                    _previewCard(),
                    const SizedBox(height: 14),
                    if (_preview != null) _confirmCard(),
                    if (_done != null) _doneCard(),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      _errorCard(),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _scopePicker() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stackVertically = constraints.maxWidth < 760;
        final items = [
          for (final s in _scopes)
            InkWell(
              onTap: _busy ? null : () => _selectScope(s),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _scope.key == s.key
                      ? AppTheme.badRed.withValues(alpha: 0.14)
                      : AppTheme.panel.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _scope.key == s.key
                        ? AppTheme.badRed.withValues(alpha: 0.8)
                        : Colors.white.withValues(alpha: 0.08),
                    width: _scope.key == s.key ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _scope.key == s.key
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 16,
                          color: _scope.key == s.key
                              ? AppTheme.badRed
                              : AppTheme.muted,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.title,
                          style: TextStyle(
                            color: _scope.key == s.key
                                ? AppTheme.fg
                                : AppTheme.mutedStrong,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Hilang: ${s.lost}',
                      style: const TextStyle(
                        color: AppTheme.badRed,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bertahan: ${s.kept}',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ];

        if (stackVertically) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                items[i],
              ],
            ],
          );
        }

        return Row(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: items[i]),
            ],
          ],
        );
      },
    );
  }


  Widget _previewCard() {
    final preview = _preview;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '1. Pratinjau',
                  style: TextStyle(
                    color: AppTheme.fg,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _busy ? null : () => _run(dryRun: true),
                icon: const Icon(Icons.visibility_outlined, size: 16),
                label: Text(_busy ? 'Menghitung…' : 'Hitung yang akan hilang'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.panelAlt,
                  foregroundColor: AppTheme.fg,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Dijalankan lewat dry_run — jalur kode yang sama dengan eksekusi '
            'sungguhan, tanpa menghapus apa pun.',
            style: TextStyle(
              color: AppTheme.muted,
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          if (preview != null) ...[
            const SizedBox(height: 12),
            _rowsTable(preview),
          ],
        ],
      ),
    );
  }

  /// Tabel dan jumlah barisnya ditampilkan **apa adanya dari server**, tidak
  /// disaring lewat daftar nama yang ditulis di sini.
  ///
  /// Disengaja: tiap modul baru menambah tabel (transporter_loads yang
  /// terakhir), dan daftar yang ditulis di GUI akan ketinggalan diam-diam --
  /// operator melihat pratinjau yang terlihat lengkap padahal ada tabel yang
  /// tidak disebut, lalu terhapus tanpa pernah muncul di layar.
  Widget _rowsTable(Map<String, dynamic> body) {
    final rows = body['rows'];
    final photos = body['photos'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows is Map)
          for (final e in rows.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 220,
                    child: Text(
                      '${e.key}',
                      style: const TextStyle(
                        color: AppTheme.muted,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  Text(
                    '${e.value} baris',
                    style: const TextStyle(
                      color: AppTheme.fg,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
        if (photos != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Foto/berkas: $photos',
              style: const TextStyle(
                color: AppTheme.fg,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _confirmCard() {
    final typed = _confirm.text.trim() == _scope.confirmation;
    return _card(
      tone: AppTheme.badRed,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '2. Jalankan',
            style: TextStyle(
              color: AppTheme.fg,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Ketik kalimat ini persis untuk melanjutkan:  ${_scope.confirmation}',
            style: const TextStyle(
              color: AppTheme.warnAmber,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            style: const TextStyle(color: AppTheme.fg, fontSize: 13),
            decoration: const InputDecoration(
              isDense: true,
              border: OutlineInputBorder(),
              hintText: 'kalimat konfirmasi',
              hintStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: (!typed || _busy) ? null : () => _run(dryRun: false),
              icon: const Icon(Icons.delete_forever, size: 18),
              label: Text(_busy ? 'Menjalankan…' : 'Hapus sekarang'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.badRed,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.panelAlt,
                disabledForegroundColor: AppTheme.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _doneCard() {
    final done = _done!;
    return _card(
      tone: AppTheme.okGreen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Selesai',
            style: TextStyle(
              color: AppTheme.fg,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          _rowsTable(done),
          const SizedBox(height: 10),
          const Text(
            'Salinan sebelum dihapus:',
            style: TextStyle(color: AppTheme.muted, fontSize: 11.5),
          ),
          for (final key in const ['backup_db', 'backup_photos'])
            if (done[key] != null)
              SelectableText(
                '${done[key]}',
                style: const TextStyle(
                  color: AppTheme.accent,
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    return _card(
      tone: AppTheme.badRed,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.badRed, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(
                color: AppTheme.fg,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child, Color? tone}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: (tone ?? AppTheme.panelAlt).withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}
