import 'dart:convert';

import 'package:flutter/material.dart';

import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';
import '../widgets/signature_pad.dart';

/// Tahap 4 alur transporter: konfirmasi masuk oleh petugas.
///
/// Arah tanda tangannya **berlawanan** dengan alur tamu, dan itu inti halaman
/// ini. Tamu menandatangani sendiri setelah check-in, dan tanda tangan itulah
/// yang menggerbang check-out-nya. Sopir tidak pernah menandatangani apa pun —
/// yang menyatakan truk boleh masuk adalah petugas, saat itu juga. Karena itu
/// tanda tangan petugas berangkat bersama foto wajah dalam satu permintaan
/// check-in: server menetapkan jam masuk saat permintaan diterima, dan dua
/// permintaan terpisah berarti dua waktu untuk satu kejadian.
/// Tahap 4 (masuk) dan tahap 5 (keluar) — dua kejadian, satu bentuk layar.
enum KonfirmasiMode {
  masuk('checkin', 'Konfirmasi Masuk Transporter', 'Jam masuk',
      'Verifikasi wajah sopir, tanda tangan petugas, lalu konfirmasi. '
          'Jam masuk terisi otomatis saat dikonfirmasi.'),
  keluar('checkout', 'Konfirmasi Keluar Transporter', 'Jam keluar',
      'Bongkar/muat selesai: verifikasi wajah sopir, tanda tangan petugas, '
          'lalu konfirmasi keluar. Jam keluar terisi otomatis.');

  const KonfirmasiMode(this.mode, this.judul, this.labelJam, this.keterangan);

  final String mode;
  final String judul;
  final String labelJam;
  final String keterangan;
}

class TransporterCheckinPage extends StatefulWidget {
  final SidecarClient? client;
  final DetectionState state;
  final String officerName;
  final KonfirmasiMode kind;

  const TransporterCheckinPage({
    super.key,
    required this.client,
    required this.state,
    required this.officerName,
    this.kind = KonfirmasiMode.masuk,
  });

  @override
  State<TransporterCheckinPage> createState() => _TransporterCheckinPageState();
}

class _TransporterCheckinPageState extends State<TransporterCheckinPage> {
  final _padKey = GlobalKey<SignaturePadState>();
  late final TextEditingController _petugas =
      TextEditingController(text: widget.officerName);

  bool _adaGoresan = false;
  bool _proses = false;
  String? _galat;
  RecognitionResult? _hasil;

  @override
  void dispose() {
    _petugas.dispose();
    super.dispose();
  }

  Future<void> _konfirmasi() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _galat = 'Sidecar belum berjalan.');
      return;
    }
    final png = await _padKey.currentState?.toPng();
    if (png == null) {
      setState(() => _galat = 'Tanda tangan petugas belum ada.');
      return;
    }
    setState(() {
      _proses = true;
      _galat = null;
      _hasil = null;
    });
    try {
      // 1) titipkan tanda tangan, 2) ambil foto, 3) kirim check-in.
      // Urutannya penting: sidecar menyertakan tanda tangan pada permintaan
      // check-in itu sendiri, bukan menyusul.
      final siap = await client.armOfficerSignature(
        pngB64: base64Encode(png),
        officerName: _petugas.text.trim(),
      );
      if (siap['ok'] != true) {
        setState(() => _galat =
            'Tanda tangan gagal disiapkan: ${siap['error'] ?? 'tidak diketahui'}');
        return;
      }
      final cap = await client.capture();
      if (!cap.ok) {
        setState(() => _galat = 'Gagal mengambil foto dari kamera.');
        return;
      }
      if (!cap.sharp) {
        setState(() => _galat =
            'Foto kurang tajam (var ${cap.variance}). Minta sopir diam sejenak, lalu ulangi.');
        return;
      }
      final res =
          RecognitionResult.fromJson(await client.submit(widget.kind.mode));
      if (!mounted) return;
      setState(() {
        _hasil = res;
        // Pesan server apa adanya: ia menyebut sebabnya (belum ada rencana,
        // salah cabang, sudah check-in) -- petunjuk yang petugas butuhkan.
        if (!res.success) _galat = res.message;
      });
      if (res.success) {
        _padKey.currentState?.clear();
        setState(() => _adaGoresan = false);
      }
    } catch (e) {
      if (mounted) setState(() => _galat = 'Konfirmasi gagal: $e');
    } finally {
      if (mounted) setState(() => _proses = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: widget.kind.judul,
            subtitle: widget.kind.keterangan,
            icon: widget.kind == KonfirmasiMode.masuk
                ? Icons.local_shipping_outlined
                : Icons.badge_outlined,
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
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
                          child: s.frameBytes == null
                              ? const Center(
                                  child: Text('menunggu kamera…',
                                      style: TextStyle(
                                          color: AppTheme.muted, fontSize: 12)))
                              : Image.memory(s.frameBytes!,
                                  gaplessPlayback: true, fit: BoxFit.contain),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(s.good ? Icons.check_circle : Icons.info_outline,
                              size: 15, color: s.color),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              s.message.isEmpty
                                  ? 'Arahkan wajah sopir ke kamera.'
                                  : s.message,
                              style: TextStyle(
                                  color: s.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                SizedBox(width: 380, child: _panelPetugas()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _panelPetugas() {
    final hasil = _hasil;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _petugas,
            style: const TextStyle(color: AppTheme.fg, fontSize: 13),
            decoration: const InputDecoration(
              labelText: 'Nama petugas',
              labelStyle: TextStyle(color: AppTheme.muted, fontSize: 12),
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          const Text('Tanda tangan petugas',
              style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          const SizedBox(height: 6),
          SizedBox(
            height: 150,
            child: SignaturePad(
              key: _padKey,
              onChanged: (ada) => setState(() => _adaGoresan = ada),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                _padKey.currentState?.clear();
                setState(() => _adaGoresan = false);
              },
              icon: const Icon(Icons.backspace_outlined, size: 15),
              label: const Text('Hapus'),
              style: TextButton.styleFrom(foregroundColor: AppTheme.muted),
            ),
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: (_proses || !_adaGoresan) ? null : _konfirmasi,
            icon: Icon(
                widget.kind == KonfirmasiMode.masuk
                    ? Icons.how_to_reg
                    : Icons.logout,
                size: 18),
            label: Text(_proses
                ? 'Mengonfirmasi…'
                : (widget.kind == KonfirmasiMode.masuk
                    ? 'Konfirmasi & check-in'
                    : 'Konfirmasi keluar')),
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.brandGold,
              foregroundColor: AppTheme.brandBlueDeep,
              disabledBackgroundColor: AppTheme.panelAlt,
              disabledForegroundColor: AppTheme.muted,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          if (!_adaGoresan) ...[
            const SizedBox(height: 8),
            const Text(
              'Tombol aktif setelah petugas menandatangani. Server menolak '
              'konfirmasi transporter tanpa tanda tangan petugas.',
              style: TextStyle(color: AppTheme.muted, fontSize: 11.5, height: 1.4),
            ),
          ],
          if (hasil != null && hasil.success) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.panel.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.okGreen.withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified, color: AppTheme.okGreen, size: 18),
                      const SizedBox(width: 8),
                      Text(
                          widget.kind == KonfirmasiMode.masuk
                              ? 'Masuk dikonfirmasi'
                              : 'Keluar dikonfirmasi',
                          style: TextStyle(
                              color: AppTheme.okGreen,
                              fontSize: 14,
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(hasil.message,
                      style: const TextStyle(color: AppTheme.fg, fontSize: 12.5)),
                ],
              ),
            ),
          ],
          if (_galat != null) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.badRed, size: 18),
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
    );
  }
}
