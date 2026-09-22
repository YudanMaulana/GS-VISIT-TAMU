import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Papan tanda tangan untuk layar sentuh.
///
/// Ada karena check-out digerbang tanda tangan tamu di server
/// (`signature_visitor_path`): tamu ber-HP menandatangani di app Android, dan
/// tanpa papan ini tamu tanpa HP tidak akan pernah bisa check-out.
///
/// Digambar di atas **putih**, bukan transparan: berkasnya berakhir di berkas
/// kunjungan yang dicetak dan dilihat orang, dan goresan gelap di atas latar
/// transparan berubah jadi tak terlihat begitu ditempel di kertas atau di
/// tema terang.
class SignaturePad extends StatefulWidget {
  /// Ukuran keluaran PNG. Cukup besar untuk dibaca saat dicetak, cukup kecil
  /// untuk dikirim lewat tunnel tanpa terasa.
  final Size exportSize;

  final void Function(bool adaGoresan)? onChanged;

  const SignaturePad({
    super.key,
    this.exportSize = const Size(900, 300),
    this.onChanged,
  });

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  /// Tiap goresan = satu rangkaian titik. Dipisah per goresan supaya huruf
  /// yang terputus tidak tersambung oleh garis yang tidak pernah digambar.
  final List<List<Offset>> _goresan = [];
  Size _kanvas = Size.zero;

  bool get isEmpty => _goresan.every((g) => g.length < 2);

  void clear() {
    setState(_goresan.clear);
    widget.onChanged?.call(false);
  }

  /// Render ke PNG pada [SignaturePad.exportSize], bukan pada ukuran layar:
  /// hasilnya sama di monitor mana pun, dan berkas yang tersimpan tidak
  /// bergantung pada kebetulan resolusi kiosk.
  Future<Uint8List?> toPng() async {
    if (isEmpty || _kanvas == Size.zero) return null;
    final recorder = ui.PictureRecorder();
    final size = widget.exportSize;
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final skala = size.width / _kanvas.width;
    _lukis(canvas, skala, const Color(0xFF0A2558), 3.0 * skala);
    final gambar = await recorder
        .endRecording()
        .toImage(size.width.round(), size.height.round());
    final data = await gambar.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  void _lukis(Canvas canvas, double skala, Color warna, double tebal) {
    final kuas = Paint()
      ..color = warna
      ..strokeWidth = tebal
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final goresan in _goresan) {
      if (goresan.length < 2) continue;
      final path = Path()
        ..moveTo(goresan.first.dx * skala, goresan.first.dy * skala);
      for (final titik in goresan.skip(1)) {
        path.lineTo(titik.dx * skala, titik.dy * skala);
      }
      canvas.drawPath(path, kuas);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _kanvas = Size(constraints.maxWidth, constraints.maxHeight);
        return GestureDetector(
          onPanStart: (d) => setState(() => _goresan.add([d.localPosition])),
          onPanUpdate: (d) => setState(() {
            if (_goresan.isEmpty) _goresan.add([]);
            _goresan.last.add(d.localPosition);
          }),
          onPanEnd: (_) => widget.onChanged?.call(!isEmpty),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.muted.withValues(alpha: 0.5)),
            ),
            child: CustomPaint(
              painter: _PelukisTtd(_goresan),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

class _PelukisTtd extends CustomPainter {
  final List<List<Offset>> goresan;

  _PelukisTtd(this.goresan);

  @override
  void paint(Canvas canvas, Size size) {
    final kuas = Paint()
      ..color = const Color(0xFF0A2558)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final g in goresan) {
      if (g.length < 2) continue;
      final path = Path()..moveTo(g.first.dx, g.first.dy);
      for (final t in g.skip(1)) {
        path.lineTo(t.dx, t.dy);
      }
      canvas.drawPath(path, kuas);
    }
  }

  // Goresan bertambah di tempat (list yang sama dimutasi), jadi perbandingan
  // identitas tidak akan pernah menandai perubahan — repaint selalu.
  @override
  bool shouldRepaint(_PelukisTtd old) => true;
}
