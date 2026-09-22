import 'package:flutter/material.dart';

import '../models.dart';
import '../sidecar_client.dart';
import '../theme.dart';
import '../widgets/console_ui.dart';

/// Deteksi & Embedding: spesifikasi pipeline (MediaPipe lokal + ArcFace server)
/// berdampingan dengan deteksi wajah live — supaya "spek embedding + info app"
/// dan "embedding benar-benar diperlihatkan visual deteksinya" ada di satu
/// tempat. Frame live memakai snapshot `/state` yang sama dengan layar POS,
/// jadi tidak ada beban kamera tambahan.
class DetectionInfoPage extends StatefulWidget {
  final SidecarClient? client;
  final DetectionState state;

  const DetectionInfoPage({super.key, required this.client, required this.state});

  @override
  State<DetectionInfoPage> createState() => _DetectionInfoPageState();
}

class _DetectionInfoPageState extends State<DetectionInfoPage> {
  EngineInfo? _info;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final client = widget.client;
    if (client == null) {
      setState(() => _error = 'Sidecar belum berjalan.');
      return;
    }
    try {
      final i = await client.engineInfo();
      if (mounted) setState(() => _info = i);
    } catch (e) {
      if (mounted) setState(() => _error = 'Gagal memuat info engine: $e');
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
            title: 'Deteksi & Embedding',
            subtitle: 'Spesifikasi pipeline deteksi wajah lokal dan embedding server',
            icon: Icons.center_focus_strong_outlined,
            actions: [
              ConsoleRefreshButton(
                busy: false,
                onPressed: _loadInfo,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _liveDetection()),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: _specs()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveDetection() {
    final s = widget.state;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.panelAlt),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (s.frameBytes != null)
            Image.memory(s.frameBytes!, fit: BoxFit.contain, gaplessPlayback: true)
          else
            const Center(child: Text('menunggu kamera…', style: TextStyle(color: AppTheme.muted))),
          Positioned(
            left: 12,
            top: 12,
            child: _liveChip(
              s.faceCount > 0 ? '${s.faceCount} WAJAH' : 'TIDAK ADA WAJAH',
              s.faceCount > 0 ? AppTheme.okGreen : AppTheme.muted,
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            right: 12,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (s.bbox != null) _liveChip('bbox ${s.bbox!.join(",")}', AppTheme.accent),
                _liveChip('landmark 478', AppTheme.accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _liveChip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      );

  Widget _specs() {
    if (_error != null) {
      return _card(
        icon: Icons.error_outline,
        color: AppTheme.badRed,
        title: 'Info engine',
        child: Text(_error!, style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
      );
    }
    final info = _info;
    if (info == null) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.brandGold));
    }
    return ListView(
      children: [
        _card(
          icon: Icons.center_focus_strong,
          color: AppTheme.accent,
          title: 'Deteksi (lokal)',
          child: _specRows(info.detection),
        ),
        const SizedBox(height: 14),
        _card(
          icon: Icons.fingerprint,
          color: AppTheme.brandGold,
          title: 'Embedding (server)',
          child: _specRows(info.embedding),
        ),
        const SizedBox(height: 14),
        _card(
          icon: info.serverConfigured ? Icons.cloud_done : Icons.cloud_off,
          color: info.serverConfigured ? AppTheme.okGreen : AppTheme.warnAmber,
          title: 'Server',
          child: _specRows([
            SpecRow('Status', info.serverConfigured ? 'Terhubung (API key ada)' : 'Belum diatur'),
            if (info.serverBaseUrl.isNotEmpty) SpecRow('Base URL', info.serverBaseUrl),
          ]),
        ),
      ],
    );
  }

  Widget _specRows(List<SpecRow> rows) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(r.label,
                        style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(r.value,
                        style: const TextStyle(
                            color: AppTheme.fg, fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _card({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
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
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(title,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
