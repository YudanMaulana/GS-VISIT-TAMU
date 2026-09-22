import 'dart:async';

import 'camera_slot.dart';
import 'config.dart';
import 'models.dart';
import 'sidecar_client.dart';
import 'sidecar_manager.dart';

enum CameraPhase { starting, running, failed }

/// Runtime state for ONE camera slot's own sidecar process: its own camera,
/// its own MediaPipe detector, its own auto-identify track.
///
/// Every slot in the grid gets one of these (see `_HomePageState._sessions`
/// in home_page.dart) and runs fully independently -- a bad camera index or a
/// crashed process in one slot never blocks or freezes the others.
class CameraSession {
  final CameraSlot slot;
  final SidecarManager manager = SidecarManager();
  SidecarClient? client;
  DetectionState state = DetectionState();
  CameraPhase phase = CameraPhase.starting;
  String failMsg = '';

  Timer? _poll;
  bool _busy = false;
  VoidCallback? _onUpdate;

  CameraSession(this.slot);

  /// Start this slot's sidecar and begin polling `/state`. [onUpdate] fires
  /// on every successful poll and on phase changes, so the caller can
  /// `setState` without each session needing to know about Flutter widgets.
  Future<void> start(AppConfig config, {required VoidCallback onUpdate}) async {
    _onUpdate = onUpdate;
    _poll?.cancel();
    client?.close();
    phase = CameraPhase.starting;
    onUpdate();
    try {
      final port = await manager.start(config, slot);
      client = SidecarClient(port);
      phase = CameraPhase.running;
      _poll = Timer.periodic(
        Duration(milliseconds: slot.isNetwork ? 160 : 90),
        (_) => _tick(),
      );
    } catch (e) {
      phase = CameraPhase.failed;
      failMsg = '$e';
    }
    onUpdate();
  }

  Future<void> _tick() async {
    if (_busy || client == null) return;
    _busy = true;
    try {
      state = await client!.fetchState();
      _onUpdate?.call();
    } catch (_) {
      // transient; keep last frame
    } finally {
      _busy = false;
    }
  }

  /// This slot currently has a recognised face -- the "whoever's recognised,
  /// on whichever camera, can check in" rule keys off exactly this.
  bool get hasRecognizedFace => state.identity?.recognized == true;

  Future<void> stop() async {
    _poll?.cancel();
    _onUpdate = null;
    await client?.shutdown();
    client?.close();
    client = null;
    await manager.stop();
  }
}

typedef VoidCallback = void Function();
