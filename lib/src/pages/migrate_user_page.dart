import 'package:flutter/material.dart';

import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

/// Migrasi Tamu — menyiapkan tamu non-mobile agar bisa masuk lewat akun Google
/// tanpa kehilangan datanya.
///
/// Tamu yang didaftarkan di pos tidak punya email. Begitu ia punya HP, petugas
/// mengisikan alamat Google-nya di sini; saat tamu itu login dengan email
/// tersebut, server menautkannya ke data yang sudah ada — wajah, skor safety,
/// dan riwayat kunjungannya tetap satu berkas, bukan pendaftaran kedua atas
/// nama orang yang sama.
///
/// Dua hal yang membentuk halaman ini:
///
///   * **Mengubah email = memindahkan kepemilikan data.** Siapa pun yang
///     menguasai alamat itu akan mendarat di data ini. Karena itu ia tidak ikut
///     di form penyuntingan biasa, dan di sini ada konfirmasi yang menampilkan
///     alamatnya sekali lagi sebelum disimpan.
///   * **Balasan 200 bukan bukti tersimpan.** Server mengabaikan field yang
///     tidak dikenalnya alih-alih menolak, jadi setiap penyimpanan di sini
///     dibaca ulang dari server dan dibandingkan.
class MigrateUserPage extends StatefulWidget {
  final SidecarClient? client;

  const MigrateUserPage({super.key, required this.client});

  @override
  State<MigrateUserPage> createState() => _MigrateUserPageState();
}

class _MigrateUserPageState extends State<MigrateUserPage> {
  final _cari = TextEditingController();
  final _email = TextEditingController();
  final _telepon = TextEditingController();

  List<VisitorRecord> _tamu = const [];
  VisitorRecord? _dipilih;
  bool _memuat = false;
  bool _menyimpan = false;
  String _pesan = '';
  String? _galat;
  bool _berhasil = false;

  @override
  void initState() {
    super.initState();
    _muat();
  }

  @override
  void dispose() {
    for (final c in [_cari, _email, _telepon]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _muat() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _galat = 'Sidecar belum berjalan.');
      return;
    }
    setState(() {
      _memuat = true;
      _galat = null;
    });
    try {
      final semua = await client.visitors();
      if (!mounted) return;
      setState(() {
        // Hanya yang relevan: tamu non-mobile yang belum tertaut. Menampilkan
        // yang sudah tertaut hanya menawarkan tindakan yang pasti ditolak
        // server dengan 409.
        _tamu = [
          for (final v in semua)
            if (v.walkIn && !v.googleLinked) v,
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _galat = 'Gagal memuat daftar tamu: $e');
    } finally {
      if (mounted) setState(() => _memuat = false);
    }
  }

  void _pilih(VisitorRecord v) {
    setState(() {
      _dipilih = v;
      _email.text = v.email;
      _telepon.text = v.phone;
      _pesan = '';
      _berhasil = false;
      _galat = null;
    });
  }

  bool get _emailMasukAkal {
    final e = _email.text.trim();
    // Sengaja longgar: server yang memutuskan sahnya (ia menolak alamat tanpa
    // @ dengan 400). Yang dijaga di sini cuma tombol yang jelas belum siap.
    return e.contains('@') && e.contains('.') && !e.contains(' ');
  }

  Future<void> _simpan() async {
    final v = _dipilih;
    final client = widget.client;
    if (v == null || client == null || !_emailMasukAkal) return;

    final email = _email.text.trim();
    final lanjut = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.panel,
        title: const Text('Konfirmasi migrasi',
            style: TextStyle(color: AppTheme.fg, fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${v.fullName} (${v.visitorCode})',
                style: const TextStyle(
                    color: AppTheme.fg, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text('Setelah disimpan, siapa pun yang masuk dengan alamat '
                'ini akan mendarat di data tamu tersebut — beserta wajah, skor '
                'safety, dan riwayat kunjungannya.',
                style: TextStyle(color: AppTheme.muted, fontSize: 12.5, height: 1.5)),
            const SizedBox(height: 12),
            SelectableText(email,
                style: const TextStyle(
                    color: AppTheme.brandGold,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (lanjut != true) return;

    setState(() {
      _menyimpan = true;
      _pesan = '';
      _galat = null;
      _berhasil = false;
    });
    try {
      final res = await client.migrateVisitor(
        visitorId: v.id,
        email: email,
        phone: _telepon.text.trim(),
      );
      final body = res['body'];
      final status = res['status'];
      final sukses = body is Map && body['success'] == true;
      if (!sukses) {
        // Pesan server apa adanya: ia membedakan 400 (alamat tanpa @), 409
        // (sudah tertaut) dan 404 — ketiganya menuntut tindakan berbeda.
        setState(() => _galat =
            '${(body is Map ? body['message'] : null) ?? res['error'] ?? 'Gagal menyimpan.'}'
            '${status != null ? ' (HTTP $status)' : ''}');
        return;
      }
      // Baca ulang: satu-satunya bukti nilainya benar-benar tersimpan.
      final segar = await client.visitor(v.id);
      if (!mounted) return;
      final tersimpan = (segar?.email ?? '').toLowerCase();
      if (tersimpan != email.toLowerCase()) {
        setState(() => _galat =
            'Server menjawab berhasil, tetapi email yang tersimpan '
            '"${segar?.email ?? ''}" tidak sama dengan yang dikirim. '
            'Jangan anggap migrasi ini berhasil.');
        return;
      }
      setState(() {
        _berhasil = true;
        _pesan = 'Tersimpan dan diverifikasi: $tersimpan';
        _dipilih = segar;
      });
      await _muat();
    } catch (e) {
      if (mounted) setState(() => _galat = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _menyimpan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _cari.text.trim().toLowerCase();
    final terlihat = [
      for (final v in _tamu)
        if (q.isEmpty || v.matches(q)) v,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Migrasi Tamu',
            subtitle: 'Siapkan tamu non-mobile agar bisa masuk lewat akun '
                'Google tanpa kehilangan riwayat kunjungannya.',
            icon: Icons.sync_alt_outlined,
            actions: [
              ConsoleRefreshButton(busy: _memuat, onPressed: _memuat ? null : _muat),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: _daftar(terlihat)),
                const SizedBox(width: 18),
                Expanded(child: _formulir()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _daftar(List<VisitorRecord> terlihat) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _cari,
          onChanged: (_) => setState(() {}),
          style: const TextStyle(color: AppTheme.fg, fontSize: 13),
          decoration: const InputDecoration(
            isDense: true,
            prefixIcon: Icon(Icons.search, size: 18, color: AppTheme.muted),
            hintText: 'Cari nama / kode tamu',
            hintStyle: TextStyle(color: AppTheme.muted, fontSize: 12.5),
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _memuat
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.brandGold))
              : terlihat.isEmpty
                  ? const ConsoleMessage(
                      icon: Icons.how_to_reg_outlined,
                      text: 'Tidak ada tamu non-mobile yang menunggu migrasi.\n'
                          'Yang sudah tertaut Google tidak ditampilkan.',
                    )
                  : ListView.builder(
                      itemCount: terlihat.length,
                      itemBuilder: (_, i) => _baris(terlihat[i]),
                    ),
        ),
      ],
    );
  }

  Widget _baris(VisitorRecord v) {
    final terpilih = _dipilih?.id == v.id;
    return Material(
      color: terpilih ? AppTheme.panelAlt : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _pilih(v),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(v.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: AppTheme.fg,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  ConsolePill(text: v.visitorCode, tone: AppTheme.accent),
                  const ConsolePill(text: 'Tanpa HP', tone: AppTheme.brandGold),
                  if (v.email.isNotEmpty)
                    const ConsolePill(
                        text: 'Email terisi', tone: AppTheme.okGreen),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formulir() {
    final v = _dipilih;
    if (v == null) {
      return const ConsoleMessage(
        icon: Icons.person_search,
        text: 'Pilih tamu di sebelah kiri untuk mengisikan email akun '
            'Google-nya.',
      );
    }
    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.panel.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.panelAlt),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${v.fullName}  ·  ${v.visitorCode}',
                style: const TextStyle(
                    color: AppTheme.fg,
                    fontSize: 17,
                    fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text('Safety ${v.safetyScore} · terdaftar tanpa HP',
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
            const SizedBox(height: 16),
            TextField(
              controller: _email,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(color: AppTheme.fg, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Email akun Google tamu *',
                labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _telepon,
              style: const TextStyle(color: AppTheme.fg, fontSize: 14),
              decoration: const InputDecoration(
                labelText: 'Nomor HP (opsional)',
                labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Alamat ini menjadi kunci: saat tamu login Google dengan email '
              'tersebut, ia mendarat di data ini. Salah ketik berarti data '
              'tamu ini bisa diambil orang lain.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11.5, height: 1.5),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed:
                    (_menyimpan || !_emailMasukAkal) ? null : _simpan,
                icon: const Icon(Icons.link, size: 18),
                label: Text(_menyimpan ? 'Menyimpan…' : 'Simpan & verifikasi'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: AppTheme.brandBlueDeep,
                  disabledBackgroundColor: AppTheme.panelAlt,
                  disabledForegroundColor: AppTheme.muted,
                ),
              ),
            ),
            if (_berhasil) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(Icons.verified, color: AppTheme.okGreen, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_pesan,
                        style: const TextStyle(
                            color: AppTheme.okGreen, fontSize: 12.5)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tamu sekarang bisa login Google di aplikasi HP-nya dan akan '
                'mendarat di data ini.',
                style: TextStyle(color: AppTheme.muted, fontSize: 11.5),
              ),
            ],
            if (_galat != null) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline,
                      color: AppTheme.badRed, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_galat!,
                        style: const TextStyle(
                            color: AppTheme.badRed, fontSize: 12.5, height: 1.4)),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
