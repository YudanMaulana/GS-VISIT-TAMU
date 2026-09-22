import 'dart:async';
import 'dart:typed_data';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

class CameraPreviewWindowApp extends StatelessWidget {
  const CameraPreviewWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Preview Kamera POS',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const CameraPreviewWindow(),
    );
  }
}

class CameraPreviewWindow extends StatefulWidget {
  const CameraPreviewWindow({super.key});

  @override
  State<CameraPreviewWindow> createState() => _CameraPreviewWindowState();
}

class _CameraPreviewWindowState extends State<CameraPreviewWindow> {
  static const _channel = WindowMethodChannel(
    'garudafood_visit/preview',
    mode: ChannelMode.unidirectional,
  );

  Timer? _poll;
  Map<String, dynamic>? _snapshot;
  String _error = '';
  bool _actionBusy = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 180), (_) => _load());
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'snapshot',
      );
      if (!mounted) return;
      setState(() {
        _snapshot = raw == null ? null : Map<String, dynamic>.from(raw);
        _error = '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Menunggu window utama: $e');
    }
  }

  Future<void> _action(String method) async {
    if (_actionBusy) return;
    setState(() => _actionBusy = true);
    try {
      await _channel.invokeMethod(method);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = 'Aksi gagal: $e');
    } finally {
      if (mounted) setState(() => _actionBusy = false);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Container(
        decoration: const BoxDecoration(gradient: AppTheme.backgroundGradient),
        child: SafeArea(child: snap == null ? _emptyState() : _preview(snap)),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Text(
        _error.isEmpty ? 'Menunggu preview kamera...' : _error,
        style: const TextStyle(color: AppTheme.muted, fontSize: 14),
      ),
    );
  }

  Widget _preview(Map<String, dynamic> snap) {
    final sessions = (snap['sessions'] as List<dynamic>? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final activeState = Map<String, dynamic>.from(
      (snap['activeState'] as Map?) ?? const <String, dynamic>{},
    );
    return Column(
      children: [
        _topBar(snap),
        if (_error.isNotEmpty)
          Container(
            width: double.infinity,
            color: AppTheme.badRed.withValues(alpha: 0.18),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Text(_error, style: const TextStyle(color: AppTheme.fg)),
          ),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _cameraGrid(sessions)),
              SizedBox(width: 380, child: _visitPanel(snap, activeState)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topBar(Map<String, dynamic> snap) {
    final scanColor = _color(snap['scanColor'] as int?);
    final online = snap['online'] == true;
    final branchName = (snap['branchName'] as String? ?? '').trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Image.asset('assets/branding/visit_logo_tight.png'),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Preview Kamera POS',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: AppTheme.fg,
                fontSize: 22,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          _pill(
            online ? 'ONLINE' : 'OFFLINE',
            online ? AppTheme.okGreen : AppTheme.muted,
          ),
          const SizedBox(width: 8),
          _pill(
            branchName.isEmpty
                ? 'CABANG BELUM DIATUR'
                : branchName.toUpperCase(),
            branchName.isEmpty ? AppTheme.badRed : AppTheme.accent,
          ),
          const SizedBox(width: 8),
          _pill(
            (snap['scanLabel'] as String? ?? 'SIAP').toUpperCase(),
            scanColor,
          ),
        ],
      ),
    );
  }

  Widget _cameraGrid(List<Map<String, dynamic>> sessions) {
    if (sessions.isEmpty) {
      return const Center(
        child: Text(
          'Belum ada kamera aktif. Atur kamera dari window utama.',
          style: TextStyle(color: AppTheme.muted),
        ),
      );
    }
    final columns = sessions.length <= 1 ? 1 : (sessions.length <= 4 ? 2 : 3);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 12, 18),
      child: GridView.count(
        crossAxisCount: columns,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 4 / 3,
        children: [for (final s in sessions) _cameraPanel(s)],
      ),
    );
  }

  Widget _cameraPanel(Map<String, dynamic> session) {
    final state = Map<String, dynamic>.from(
      (session['state'] as Map?) ?? const <String, dynamic>{},
    );
    final active = session['active'] == true;
    final phase = session['phase'] as String? ?? '';
    final message = state['message'] as String? ?? '';
    final msgColor = _color(state['color'] as int?);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black,
          border: Border.all(
            color: active ? AppTheme.brandGold : Colors.transparent,
            width: 3,
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _cameraContent(phase, session, state),
            Positioned(
              left: 8,
              top: 8,
              child: _chip(
                session['label'] as String? ?? 'Kamera',
                session['isNetwork'] == true ? Icons.wifi : Icons.usb,
                AppTheme.fg,
              ),
            ),
            if (active)
              Positioned(
                right: 8,
                top: 8,
                child: _chip(
                  (state['identityName'] as String?)?.isNotEmpty == true
                      ? state['identityName'] as String
                      : 'DIKENALI',
                  Icons.verified,
                  AppTheme.brandGold,
                ),
              ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  message.isEmpty ? '-' : message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: msgColor,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cameraContent(
    String phase,
    Map<String, dynamic> session,
    Map<String, dynamic> state,
  ) {
    if (phase == 'starting') {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.brandGold,
          ),
        ),
      );
    }
    if (phase == 'failed') {
      return _centerMessage(
        Icons.error_outline,
        session['failMsg'] as String? ?? 'Kamera gagal.',
      );
    }
    final err = state['error'] as String?;
    if (err != null && err.isNotEmpty) {
      return _centerMessage(Icons.error_outline, err);
    }
    final frame = state['frame'];
    if (frame is Uint8List) {
      return Image.memory(frame, gaplessPlayback: true, fit: BoxFit.contain);
    }
    return const Center(
      child: Text(
        'menunggu kamera...',
        style: TextStyle(color: AppTheme.muted),
      ),
    );
  }

  Widget _visitPanel(Map<String, dynamic> snap, Map<String, dynamic> state) {
    final recognized = state['identityRecognized'] == true;
    final name = state['identityName'] as String? ?? '';
    final similarity = state['identitySimilarity'];
    final lastVisit = snap['lastVisit'] is Map
        ? Map<String, dynamic>.from(snap['lastVisit'] as Map)
        : null;
    final checkedIn =
        lastVisit?['success'] == true && lastVisit?['mode'] == 'checkin';
    final signed = snap['signed'] == true;
    final busy = snap['busy'] == true || _actionBusy;
    final branchConfigured = snap['branchConfigured'] == true;
    return Container(
      color: AppTheme.panel,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'KUNJUNGAN',
            style: TextStyle(
              color: AppTheme.fg,
              fontSize: 15,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          _identityCard(recognized, name, similarity, lastVisit),
          const SizedBox(height: 16),
          _step(
            1,
            'Check-in wajah (POS)',
            checkedIn,
            checkedIn
                ? (lastVisit?['message'] as String? ?? '')
                : 'Arahkan wajah lalu tekan Check-in',
          ),
          _step(
            2,
            'Tanda tangan Tamu + PIC',
            signed,
            signed
                ? 'Sudah ditandatangani di aplikasi Tamu'
                : (checkedIn
                      ? 'Menunggu tanda tangan di aplikasi Android...'
                      : 'Dilakukan setelah check-in'),
            waiting: checkedIn && !signed,
          ),
          _step(
            3,
            'Check-out (POS)',
            false,
            signed ? 'Siap check-out' : 'Terkunci sampai tanda tangan selesai',
          ),
          const Spacer(),
          if (!branchConfigured)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _pill(
                'CABANG BELUM DIATUR',
                AppTheme.badRed,
                expand: true,
              ),
            ),
          if ((state['autoCheckinMessage'] as String? ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _pill(
                (state['autoCheckinMessage'] as String).toUpperCase(),
                state['autoCheckinState'] == 'checked_in'
                    ? AppTheme.okGreen
                    : AppTheme.muted,
                expand: true,
              ),
            ),
          _actionButton(
            icon: Icons.login,
            label: 'Check-in (F1)',
            enabled: !busy && recognized && branchConfigured,
            color: AppTheme.brandGold,
            fg: AppTheme.brandBlueDeep,
            onPressed: () => _action('checkin'),
          ),
          const SizedBox(height: 8),
          _actionButton(
            icon: Icons.refresh,
            label: signed ? 'Status: sudah TTD' : 'Cek status TTD (F2)',
            enabled: !busy && checkedIn,
            color: Colors.transparent,
            fg: signed ? AppTheme.okGreen : AppTheme.fg,
            outlined: true,
            onPressed: () => _action('refresh'),
          ),
          const SizedBox(height: 8),
          _actionButton(
            icon: Icons.logout,
            label: 'Check-out (F3)',
            enabled: !busy && recognized && signed,
            color: AppTheme.brandBlueBright,
            fg: AppTheme.fg,
            onPressed: () => _action('checkout'),
          ),
        ],
      ),
    );
  }

  Widget _identityCard(
    bool recognized,
    String name,
    Object? similarity,
    Map<String, dynamic>? lastVisit,
  ) {
    final color = recognized ? AppTheme.okGreen : AppTheme.muted;
    final photo = lastVisit?['photo'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.panelAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: photo is Uint8List
                ? Image.memory(photo, fit: BoxFit.cover, gaplessPlayback: true)
                : Icon(
                    recognized ? Icons.person : Icons.person_search,
                    color: AppTheme.muted,
                    size: 26,
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recognized
                      ? (name.isEmpty ? '-' : name)
                      : 'Menunggu wajah...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                if (similarity is num)
                  Text(
                    'Kecocokan ${(similarity * 100).toStringAsFixed(1)}%',
                    style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(
    int n,
    String title,
    bool done,
    String sub, {
    bool waiting = false,
  }) {
    final color = done
        ? AppTheme.okGreen
        : (waiting ? AppTheme.brandGold : AppTheme.muted);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: done
                  ? AppTheme.okGreen.withValues(alpha: 0.2)
                  : Colors.transparent,
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.6)),
            ),
            child: done
                ? const Icon(Icons.check, size: 13, color: AppTheme.okGreen)
                : Text(
                    '$n',
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: done ? AppTheme.fg : AppTheme.muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  sub,
                  maxLines: 2,
                  style: const TextStyle(color: AppTheme.muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required bool enabled,
    required Color color,
    required Color fg,
    required VoidCallback onPressed,
    bool outlined = false,
  }) {
    final child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
    if (outlined) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: enabled ? onPressed : null,
          style: OutlinedButton.styleFrom(
            foregroundColor: fg,
            side: BorderSide(color: fg.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: child,
        ),
      );
    }
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? onPressed : null,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: child,
      ),
    );
  }

  Widget _centerMessage(IconData icon, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppTheme.badRed, size: 22),
            const SizedBox(height: 8),
            Text(
              message,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
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

  Widget _pill(String label, Color color, {bool expand = false}) {
    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.7,
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: pill) : pill;
  }

  Color _color(int? argb) {
    if (argb == null) return AppTheme.muted;
    return Color.fromARGB(
      (argb >> 24) & 0xff,
      (argb >> 16) & 0xff,
      (argb >> 8) & 0xff,
      argb & 0xff,
    );
  }
}
