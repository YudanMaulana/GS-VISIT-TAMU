import 'package:flutter/material.dart';

import '../camera_session.dart';
import '../theme.dart';

/// CCTV-style wall of every configured camera's live feed. Detection runs
/// independently on each (its own sidecar) -- whichever panel currently has
/// a recognised face is highlighted with a gold border, since that's the
/// camera the check-in/out action will actually use (see
/// `_HomePageState._activeSession` in home_page.dart).
class CameraGrid extends StatelessWidget {
  final List<CameraSession> sessions;

  const CameraGrid({super.key, required this.sessions});

  @override
  Widget build(BuildContext context) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada kamera diatur - buka Pengaturan.',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    if (sessions.length == 1) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 12, 18),
        child: _CameraPanel(session: sessions.first),
      );
    }
    final columns = sessions.length <= 4 ? 2 : 3;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 18),
      child: GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 4 / 3,
        children: [for (final s in sessions) _CameraPanel(session: s)],
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  final CameraSession session;
  const _CameraPanel({required this.session});

  @override
  Widget build(BuildContext context) {
    final active = session.hasRecognizedFace;
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: active
              ? AppTheme.brandGold.withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.10),
          width: active ? 2.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: (active ? AppTheme.brandGold : Colors.black).withValues(
              alpha: active ? 0.15 : 0.24,
            ),
            blurRadius: active ? 28 : 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _content(),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0x66000000), Colors.transparent],
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                ),
              ),
            ),
          ),
          Positioned(
            left: 10,
            top: 10,
            child: _chip(
              session.slot.label.isEmpty ? 'Kamera' : session.slot.label,
              session.slot.isNetwork ? Icons.wifi : Icons.usb,
              AppTheme.fg,
            ),
          ),
          if (active)
            Positioned(
              right: 10,
              top: 10,
              child: _chip(
                session.state.identity?.name ?? 'DIKENALI',
                Icons.verified,
                AppTheme.brandGold,
              ),
            ),
          Positioned(left: 10, right: 10, bottom: 10, child: _statusLine()),
        ],
      ),
    );
  }

  Widget _content() {
    switch (session.phase) {
      case CameraPhase.starting:
        return const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppTheme.brandGold,
            ),
          ),
        );
      case CameraPhase.failed:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: AppTheme.badRed,
                  size: 20,
                ),
                const SizedBox(height: 6),
                Text(
                  session.failMsg,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 10.5),
                ),
              ],
            ),
          ),
        );
      case CameraPhase.running:
        final err = session.state.error;
        if (err != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: AppTheme.badRed,
                    size: 20,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    err,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AppTheme.muted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
          );
        }
        final bytes = session.state.frameBytes;
        if (bytes == null) {
          return const Center(
            child: Text(
              'menunggu kamera...',
              style: TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          );
        }
        return Image.memory(bytes, gaplessPlayback: true, fit: BoxFit.contain);
    }
  }

  Widget _statusLine() {
    if (session.phase != CameraPhase.running) return const SizedBox.shrink();
    final s = session.state;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xE6071634),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Text(
        s.message.isEmpty ? '-' : s.message,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: s.color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.1,
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xD9071634),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
