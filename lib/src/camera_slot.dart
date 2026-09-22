import 'dart:convert';

/// One camera feed in the multi-camera grid (webcam laptop, webcam USB,
/// ESP32-CAM, ...). Each slot gets its own sidecar process -- see
/// `CameraSession` -- so this only holds what that process needs to know
/// which device to open, plus a display label for the grid panel.
///
/// Local XOR network, same distinction the single-camera config used to make
/// (see git history of `AppConfig` before this), just repeated per slot now.
class CameraSlot {
  String label; // "Webcam Laptop", "USB2.0 HD UVC WebCam", "ESP32-CAM" ...
  bool enabled; // keep a slot configured but temporarily switched off
  bool isNetwork;
  int localIndex; // used when !isNetwork
  String cameraUrl; // used when isNetwork (ESP32-CAM MJPEG stream URL)
  String captureUrl; // optional high-res still URL, only used when isNetwork

  CameraSlot({
    required this.label,
    this.enabled = true,
    this.isNetwork = false,
    this.localIndex = 0,
    this.cameraUrl = '',
    this.captureUrl = '',
  });

  Map<String, dynamic> toJson() => {
        'label': label,
        'enabled': enabled,
        'isNetwork': isNetwork,
        'localIndex': localIndex,
        'cameraUrl': cameraUrl,
        'captureUrl': captureUrl,
      };

  factory CameraSlot.fromJson(Map<String, dynamic> j) => CameraSlot(
        label: j['label'] as String? ?? '',
        enabled: j['enabled'] as bool? ?? true,
        isNetwork: j['isNetwork'] as bool? ?? false,
        localIndex: (j['localIndex'] as num?)?.toInt() ?? 0,
        cameraUrl: j['cameraUrl'] as String? ?? '',
        captureUrl: j['captureUrl'] as String? ?? '',
      );

  CameraSlot copy() => CameraSlot(
        label: label,
        enabled: enabled,
        isNetwork: isNetwork,
        localIndex: localIndex,
        cameraUrl: cameraUrl,
        captureUrl: captureUrl,
      );
}

List<CameraSlot> decodeCameraSlots(String? json) {
  if (json == null || json.isEmpty) return const [];
  try {
    final list = jsonDecode(json) as List;
    return list.map((e) => CameraSlot.fromJson(e as Map<String, dynamic>)).toList();
  } catch (_) {
    return const [];
  }
}

String encodeCameraSlots(List<CameraSlot> slots) =>
    jsonEncode(slots.map((s) => s.toJson()).toList());
