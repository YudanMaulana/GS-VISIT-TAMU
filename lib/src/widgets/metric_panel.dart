import 'package:flutter/material.dart';

import '../models.dart';
import '../theme.dart';

/// The right-hand data panel: good-streak meter + every §3.1 metric line
/// (from the shared Python report builder) + the last-capture summary.
class MetricPanel extends StatelessWidget {
  final DetectionState state;
  const MetricPanel({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.panel,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('FACE QUALITY',
                  style: TextStyle(
                      color: AppTheme.fg,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1)),
              const Spacer(),
              _verdictChip(state),
            ],
          ),
          if (state.autoIdentify) ...[
            const SizedBox(height: 12),
            _IdentityChip(state: state),
          ],
          const SizedBox(height: 14),
          _StreakMeter(state: state),
          const SizedBox(height: 14),
          const Divider(color: AppTheme.panelAlt, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              children: [
                if (state.recognition != null) ...[
                  RecognitionCard(rec: state.recognition!),
                  const SizedBox(height: 14),
                ],
                for (final line in state.lines) _MetricRow(line: line),
                if (state.lastCapture != null) ...[
                  const SizedBox(height: 12),
                  _CaptureCard(cap: state.lastCapture!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _verdictChip(DetectionState s) {
    final good = s.good;
    final color = good ? AppTheme.okGreen : AppTheme.badRed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color, width: 1),
      ),
      child: Text(good ? 'GOOD' : 'BAD',
          style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }
}

/// Live identity of the tracked face — the same name drawn on the bounding
/// box. Resolved once per face track (side-effect-free identify endpoint),
/// so standing in front of the camera costs one request, not one per frame.
class _IdentityChip extends StatelessWidget {
  final DetectionState state;
  const _IdentityChip({required this.state});

  @override
  Widget build(BuildContext context) {
    final id = state.identity;
    final Color color;
    final IconData icon;
    final String title;
    String? sub;

    if (id == null) {
      if (state.identifying) {
        color = AppTheme.muted;
        icon = Icons.hourglass_top;
        title = 'Mengenali…';
      } else {
        color = AppTheme.muted;
        icon = Icons.person_search;
        title = 'Menunggu wajah';
      }
    } else if (id.status == 'error') {
      color = AppTheme.badRed;
      icon = Icons.cloud_off;
      title = 'Server error';
      sub = id.message;
    } else if (id.recognized) {
      color = AppTheme.okGreen;
      icon = Icons.verified_user;
      title = id.name ?? 'Dikenali';
      if (id.similarity != null) {
        sub = 'Kecocokan ${(id.similarity! * 100).toStringAsFixed(1)}%'
            '${id.threshold != null ? ' (min ${(id.threshold! * 100).toStringAsFixed(0)}%)' : ''}';
      }
    } else {
      color = AppTheme.badRed;
      icon = Icons.person_off;
      title = 'Tidak dikenal';
      sub = id.message;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w800, fontSize: 14.5)),
                if (sub != null)
                  Text(sub,
                      maxLines: 2,
                      style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StreakMeter extends StatelessWidget {
  final DetectionState state;
  const _StreakMeter({required this.state});

  @override
  Widget build(BuildContext context) {
    final n = state.goodStreak;
    final total = state.stableThreshold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Good streak',
                style: TextStyle(color: AppTheme.muted, fontSize: 12)),
            Text('$n / $total',
                style: TextStyle(
                    color: n > 0 ? AppTheme.okGreen : AppTheme.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 12)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: total == 0 ? 0 : (n / total).clamp(0, 1),
            minHeight: 8,
            backgroundColor: AppTheme.panelAlt,
            valueColor: const AlwaysStoppedAnimation(AppTheme.okGreen),
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  final ReportLine line;
  const _MetricRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData? icon;
    switch (line.ok) {
      case true:
        color = AppTheme.okGreen;
        icon = Icons.check_circle;
        break;
      case false:
        color = AppTheme.badRed;
        icon = Icons.cancel;
        break;
      default:
        color = AppTheme.muted;
        icon = null;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.label,
              style: const TextStyle(color: AppTheme.muted, fontSize: 12.5)),
          const SizedBox(height: 3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(line.value,
                    style: TextStyle(
                        color: line.ok == null ? AppTheme.fg : color,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaptureCard extends StatelessWidget {
  final CaptureResult cap;
  const _CaptureCard({required this.cap});

  @override
  Widget build(BuildContext context) {
    final sharpColor = cap.sharp ? AppTheme.okGreen : AppTheme.badRed;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.panelAlt,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(cap.forced ? Icons.camera : Icons.auto_awesome,
                  size: 15, color: AppTheme.accent),
              const SizedBox(width: 6),
              Text(cap.forced ? 'Forced capture' : 'Auto capture',
                  style: const TextStyle(
                      color: AppTheme.fg, fontWeight: FontWeight.w700, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 6),
          Text(cap.filename ?? '',
              style: const TextStyle(color: AppTheme.muted, fontSize: 11)),
          const SizedBox(height: 6),
          Text('Sharpness ${cap.sharp ? "PASS" : "FAIL"}  (var ${cap.variance})',
              style: TextStyle(color: sharpColor, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}

/// The "did the server recognise / register this face" card — the sidebar's
/// answer to "terdaftar atau tidak", plus the matched visitor's data + photo.
class RecognitionCard extends StatelessWidget {
  final RecognitionResult rec;
  const RecognitionCard({super.key, required this.rec});

  bool get _positive => rec.ok && rec.success;

  String get _title {
    if (!rec.ok && rec.error != null) return 'SERVER ERROR';
    if (_positive) {
      switch (rec.mode) {
        case 'register':
          return 'PENDAFTARAN BERHASIL';
        case 'checkout':
          return 'TERDAFTAR · CHECK-OUT';
        default:
          return 'TERDAFTAR · CHECK-IN';
      }
    }
    return rec.mode == 'register' ? 'PENDAFTARAN GAGAL' : 'WAJAH TIDAK TERDAFTAR';
  }

  @override
  Widget build(BuildContext context) {
    final color = _positive ? AppTheme.okGreen : AppTheme.badRed;
    final v = rec.visitor;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _photo(color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(_positive ? Icons.verified : Icons.gpp_bad,
                            color: color, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_title,
                              style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13.5)),
                        ),
                      ],
                    ),
                    if (rec.similarity != null) ...[
                      const SizedBox(height: 4),
                      Text('Kecocokan: ${(rec.similarity! * 100).toStringAsFixed(1)}%',
                          style: const TextStyle(color: AppTheme.fg, fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (rec.message.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(rec.message,
                style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ],
          if (v != null) ...[
            const SizedBox(height: 10),
            _kv('Nama', v.fullName),
            _kv('Instansi', v.company),
            _kv('Telepon', v.phone),
            _kv('Keperluan', v.purpose),
            if (v.visitorCode.isNotEmpty) _kv('Kode', v.visitorCode),
          ],
        ],
      ),
    );
  }

  Widget _photo(Color color) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: AppTheme.panelAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: rec.photo != null
          ? Image.memory(rec.photo!, fit: BoxFit.cover, gaplessPlayback: true)
          : Icon(_positive ? Icons.person : Icons.person_off,
              color: AppTheme.muted, size: 30),
    );
  }

  Widget _kv(String k, String value) {
    final v = value.trim().isEmpty ? '-' : value.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(k, style: const TextStyle(color: AppTheme.muted, fontSize: 12)),
          ),
          const Text(': ', style: TextStyle(color: AppTheme.muted, fontSize: 12)),
          Expanded(
            child: Text(v,
                style: const TextStyle(
                    color: AppTheme.fg, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
