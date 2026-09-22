import 'package:flutter/material.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';

import 'src/guest_kiosk_window.dart';
import 'src/home_page.dart';
import 'src/preview_window.dart';
import 'src/theme.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final window = await WindowController.fromCurrentEngine();
  if (window.arguments == 'camera-preview') {
    runApp(const CameraPreviewWindowApp());
    return;
  }
  // Jendela kiosk membawa port sidecar di argumennya supaya bisa mengambil
  // katalog (kategori tamu, wilayah) sendiri -- daftar panjang tidak perlu
  // dipompa lewat channel antar-jendela.
  final kiosk = window.arguments;
  if (kiosk.startsWith('guest-kiosk:')) {
    runApp(GuestKioskWindowApp(
      sidecarPort: int.tryParse(kiosk.split(':').last) ?? 0,
    ));
    return;
  }
  runApp(const GarudaParityApp());
}

class GarudaParityApp extends StatelessWidget {
  const GarudaParityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Garudashield Visit',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const HomePage(),
    );
  }
}
