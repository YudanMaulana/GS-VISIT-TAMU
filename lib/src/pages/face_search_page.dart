import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

/// Cari wajah: pilih sebuah foto, lalu (1) perlihatkan deteksi wajahnya secara
/// visual (kotak + landmark + metrik dari engine MediaPipe yang sama dengan
/// pipeline check-in), dan (2) cocokkan wajah itu ke SELURUH tamu tersimpan
/// lewat `POST /api/visitors/identify` di server (ArcFace 1:N).
class FaceSearchPage extends StatefulWidget {
  final SidecarClient? client;
  const FaceSearchPage({super.key, required this.client});

  @override
  State<FaceSearchPage> createState() => _FaceSearchPageState();
}

class _FaceSearchPageState extends State<FaceSearchPage> {
  Uint8List? _picked; // the raw file the operator chose
  String _pickedName = '';
  bool _searching = false;
  FaceSearchResult? _result;
  String? _error;

  Future<void> _pick() async {
    final res = await FilePicker.pickFiles(
      type: FileType.image,
      withData: true,
      dialogTitle: 'Pilih foto wajah untuk dicari',
    );
    final file = res?.files.singleOrNull;
    if (file?.bytes == null) return;
    setState(() {
      _picked = file!.bytes;
      _pickedName = file.name;
      _result = null;
      _error = null;
    });
  }

  Future<void> _search() async {
    final client = widget.client;
    final bytes = _picked;
    if (client == null) {
      setState(() => _error = 'Sidecar belum berjalan.');
      return;
    }
    if (bytes == null) return;
    setState(() {
      _searching = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await client.identifyPhoto(bytes);
      if (!mounted) return;
      setState(() {
        _result = r;
        if (!r.ok) _error = r.error ?? 'Gagal memproses foto.';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Error: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConsoleHeader(
            title: 'Cari Wajah',
            subtitle: 'Cocokkan sebuah foto ke seluruh tamu terdaftar (ArcFace 1:N)',
            icon: Icons.person_search_outlined,
            actions: [
              OutlinedButton.icon(
                onPressed: _searching ? null : _pick,
                icon: const Icon(Icons.image_outlined, size: 16),
                label: const Text('Pilih Foto'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.fg,
                  side: BorderSide(color: AppTheme.muted.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              FilledButton.icon(
                onPressed: (_searching || _picked == null) ? null : _search,
                icon: _searching
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.brandBlueDeep,
                        ),
                      )
                    : const Icon(Icons.search, size: 16),
                label: Text(_searching ? 'Mencari…' : 'Cari Wajah'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.brandGold,
                  foregroundColor: AppTheme.brandBlueDeep,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _imagePane()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _resultPane()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _imagePane() {
    final annotated = _result?.detection?.annotated;
    final showBytes = annotated ?? _picked;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.panelAlt),
      ),
      clipBehavior: Clip.antiAlias,
      child: showBytes == null
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_photo_alternate_outlined, color: AppTheme.muted, size: 48),
                  SizedBox(height: 12),
                  Text('Pilih foto untuk memulai',
                      style: TextStyle(color: AppTheme.muted)),
                ],
              ),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(showBytes, fit: BoxFit.contain, gaplessPlayback: true),
                if (annotated != null)
                  Positioned(
                    left: 12,
                    top: 12,
                    child: _chip(
                      _result!.detection!.found
                          ? 'WAJAH TERDETEKSI'
                          : 'TIDAK ADA WAJAH',
                      _result!.detection!.found ? AppTheme.okGreen : AppTheme.badRed,
                    ),
                  ),
                if (_pickedName.isNotEmpty)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: _chip(_pickedName, AppTheme.accent),
                  ),
              ],
            ),
    );
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _resultPane() {
    if (_error != null) {
      return _panel(child: Row(children: [
        const Icon(Icons.error_outline, color: AppTheme.badRed, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(_error!, style: const TextStyle(color: AppTheme.badRed))),
      ]));
    }
    final result = _result;
    if (result == null) {
      return _panel(
        child: const Center(
          child: Text('Hasil pencarian akan muncul di sini.',
              style: TextStyle(color: AppTheme.muted)),
        ),
      );
    }
    return ListView(
      children: [
        _MatchCard(match: result.match),
        const SizedBox(height: 14),
        _DetectionCard(detection: result.detection),
      ],
    );
  }

  Widget _panel({required Widget child}) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.panelAlt),
        ),
        child: child,
      );
}

/// The server match result — the "siapa ini" answer.
class _MatchCard extends StatelessWidget {
  final FaceMatch? match;
  const _MatchCard({required this.match});

  @override
  Widget build(BuildContext context) {
    final m = match;
    if (m == null || !m.attempted) {
      return _wrap(
        color: AppTheme.warnAmber,
        icon: Icons.cloud_off,
        title: 'Server tidak dihubungi',
        body: Text(m?.error ?? 'API key belum diatur — cocokkan ke server tidak dijalankan.',
            style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
      );
    }
    if (!m.ok) {
      return _wrap(
        color: AppTheme.badRed,
        icon: Icons.error_outline,
        title: 'Gagal menghubungi server',
        body: Text(m.error ?? m.message, style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
      );
    }
    if (!m.success) {
      return _wrap(
        color: AppTheme.muted,
        icon: Icons.search_off,
        title: 'Tidak ada kecocokan',
        body: Text(
          m.message.isNotEmpty
              ? m.message
              : 'Wajah ini tidak cocok dengan tamu mana pun di database.',
          style: const TextStyle(color: AppTheme.muted, fontSize: 12.5),
        ),
      );
    }
    // Matched.
    final v = m.visitor;
    final simPct = m.similarity != null ? (m.similarity! * 100).toStringAsFixed(1) : '—';
    final thrPct = m.threshold != null ? (m.threshold! * 100).toStringAsFixed(0) : '—';
    return _wrap(
      color: AppTheme.okGreen,
      icon: Icons.verified_user,
      title: 'Cocok ditemukan',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: AppTheme.panelAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.okGreen.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: m.photo != null
                    ? Image.memory(m.photo!, fit: BoxFit.cover)
                    : const Icon(Icons.person, color: AppTheme.muted, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(v?.fullName ?? '-',
                        style: const TextStyle(
                            color: AppTheme.fg, fontSize: 17, fontWeight: FontWeight.w800)),
                    if ((v?.company ?? '').isNotEmpty)
                      Text(v!.company, style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
                    if ((v?.visitorCode ?? '').isNotEmpty)
                      Text(v!.visitorCode, style: const TextStyle(color: AppTheme.accent, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _simBar(m.similarity ?? 0, m.threshold ?? 0),
          const SizedBox(height: 6),
          Text('Kemiripan $simPct% • ambang server $thrPct%',
              style: const TextStyle(color: AppTheme.muted, fontSize: 11.5)),
        ],
      ),
    );
  }

  Widget _simBar(double sim, double thr) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return SizedBox(
        height: 10,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                color: AppTheme.panelAlt,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
            FractionallySizedBox(
              widthFactor: sim.clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: AppTheme.okGreen,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            // threshold marker
            Positioned(
              left: (thr.clamp(0, 1) * w) - 1,
              child: Container(width: 2, height: 10, color: AppTheme.brandGold),
            ),
          ],
        ),
      );
    });
  }

  Widget _wrap({
    required Color color,
    required IconData icon,
    required String title,
    required Widget body,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          body,
        ],
      ),
    );
  }
}

/// The local-detection breakdown — the "benar-benar diperlihatkan" evidence.
class _DetectionCard extends StatelessWidget {
  final DetectionSnapshot? detection;
  const _DetectionCard({required this.detection});

  @override
  Widget build(BuildContext context) {
    final d = detection;
    if (d == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.panelAlt),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.center_focus_strong, color: AppTheme.accent, size: 18),
              SizedBox(width: 8),
              Text('Deteksi (MediaPipe, lokal)',
                  style: TextStyle(color: AppTheme.fg, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 12),
          for (final line in d.reportLines) _reportRow(line),
        ],
      ),
    );
  }

  Widget _reportRow(ReportLine line) {
    final color = line.ok == null
        ? AppTheme.muted
        : (line.ok! ? AppTheme.okGreen : AppTheme.badRed);
    final icon = line.ok == null
        ? Icons.remove
        : (line.ok! ? Icons.check_circle : Icons.cancel);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(line.label, style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          ),
          Text(line.value,
              style: TextStyle(color: color, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
