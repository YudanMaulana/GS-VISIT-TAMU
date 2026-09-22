import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'camera_slot.dart';
import 'config.dart';

/// Launches and supervises the Python detection sidecar as a child process.
///
/// One instance per camera slot in the multi-camera grid -- each owns its own
/// process (own camera, own MediaPipe detector), so a crash or a bad camera
/// index in one slot never affects the others.
///
/// The sidecar is started with `--port 0`; it prints the real bound port on
/// its first stdout line ("listening on http://127.0.0.1:PORT"), which we
/// parse. stdout/stderr are buffered so the UI can show them if it fails.
class SidecarManager {
  Process? _process;
  final _logBuffer = StringBuffer();
  int? _port;
  // Re-created on every start(): a Completer is single-use, so reusing one
  // field across restarts made the second start() return the old (dead) port
  // immediately -> the app polled a dead sidecar and the video froze.
  Completer<int>? _portCompleter;

  int? get port => _port;
  String get log => _logBuffer.toString();
  bool get running => _process != null;

  /// Start this camera slot's sidecar and resolve once it reports its port
  /// (or throw). `slot` picks which camera source `config`'s shared settings
  /// (server, branch, ...) get combined with.
  Future<int> start(AppConfig config, CameraSlot slot) async {
    await stop();
    _validate(config);

    final completer = Completer<int>();
    _portCompleter = completer;
    _logBuffer.clear();

    // Secrets go via the environment, never argv (argv is world-readable).
    final proc = await Process.start(
      config.pythonPath,
      config.sidecarArgsFor(slot, 0),
      environment: config.sidecarEnv(),
    );
    _process = proc;

    proc.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    proc.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(_onLine);
    proc.exitCode.then((code) {
      _appendLog('[sidecar exited with code $code]');
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('Sidecar exited before starting (code $code).\n$log'),
        );
      }
      if (identical(_process, proc)) _process = null;
    });

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () => throw TimeoutException(
        'Sidecar did not report a port within 20s.\n$log',
      ),
    );
  }

  void _validate(AppConfig config) {
    if (!File(config.pythonPath).existsSync()) {
      throw StateError(
        'Python interpreter not found:\n  ${config.pythonPath}\n'
        'Set the correct path in Settings (the detector repo\'s .venv).',
      );
    }
    if (!File(config.sidecarPath).existsSync()) {
      throw StateError(
        'sidecar.py not found:\n  ${config.sidecarPath}\n'
        'Set the correct path in Settings.',
      );
    }
  }

  void _onLine(String line) {
    _appendLog(line);
    if (_port == null) {
      final m = RegExp(r'listening on http://[^:]+:(\d+)').firstMatch(line);
      if (m != null) {
        _port = int.parse(m.group(1)!);
        final c = _portCompleter;
        if (c != null && !c.isCompleted) c.complete(_port);
      }
    }
  }

  void _appendLog(String line) {
    _logBuffer.writeln(line);
    // keep the buffer from growing unbounded
    if (_logBuffer.length > 20000) {
      final s = _logBuffer.toString();
      _logBuffer
        ..clear()
        ..write(s.substring(s.length - 12000));
    }
  }

  Future<void> stop() async {
    final proc = _process;
    _process = null;
    _port = null;
    if (proc != null) {
      proc.kill(ProcessSignal.sigterm);
      try {
        await proc.exitCode.timeout(const Duration(seconds: 3));
      } on TimeoutException {
        proc.kill(ProcessSignal.sigkill);
      }
    }
  }
}
