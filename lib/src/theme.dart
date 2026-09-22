import 'package:flutter/material.dart';

/// Garudashield palette shared with the Windows FaceID admin desk.
///
/// The Linux Visit app still has camera-first surfaces, so it keeps a deep
/// operational canvas. Navigation, panels, buttons, and status furniture follow
/// the FaceID desktop language: navy gradient, gold accents, restrained borders.
class AppTheme {
  // Brand
  static const brandBlue = Color(0xFF0F3D91);
  static const brandBlueBright = Color(0xFF1249AB);
  static const brandBlueDeep = Color(0xFF0A2558);
  static const brandGold = Color(0xFFF4C300);
  static const brandGoldDeep = Color(0xFFC29200);
  static const brandTint = Color(0xFFEAF2FF);
  static const brandBlueSoft = Color(0xFFEAF2FF);

  // Surfaces
  static const bg = Color(0xFF071634);
  static const bgGradientTop = Color(0xFF0A2558);
  static const bgGradientMid = Color(0xFF0F3D91);
  static const bgGradientBottom = Color(0xFF071634);
  static const panel = Color(0xFF0D2A5E);
  static const panelAlt = Color(0xFF14386F);
  static const panelRaised = Color(0xFF173F7B);
  static const panelSoft = Color(0xFF102F66);
  static const outline = Color(0xFF315B9D);

  // Text
  static const fg = Color(0xFFEAF2FF);
  static const muted = Color(0xFF9DBCF0);
  static const mutedStrong = Color(0xFFC7D7F0);

  // Status
  static const okGreen = Color(0xFF5BDFC1);
  static const badRed = Color(0xFFFF6B6B);
  static const warnAmber = Color(0xFFF4C300);
  static const accent = Color(0xFF7CC6FF);

  /// Resolved from the system via fontconfig (Ubuntu ships it as `fonts-ubuntu`),
  /// with a DejaVu Sans fallback so a box without it still renders.
  static const fontFamily = 'Ubuntu';
  static const _fontFallback = <String>['Ubuntu', 'DejaVu Sans'];

  static const backgroundGradient = LinearGradient(
    colors: [Color(0xFF061A3C), bgGradientTop, bgGradientBottom],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const panelGradient = LinearGradient(
    colors: [Color(0xE6153973), Color(0xCC0A2558)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static List<BoxShadow> softShadow([double alpha = 0.22]) => [
    BoxShadow(
      color: Colors.black.withValues(alpha: alpha),
      blurRadius: 28,
      offset: const Offset(0, 16),
    ),
  ];

  static const glassBorder = Color(0x24FFFFFF);
  static const glassBorderHighlight = Color(0x3DF4C300);

  static BoxDecoration cardDecoration({
    Color? color,
    BorderRadius? borderRadius,
    Border? border,
    List<BoxShadow>? shadows,
  }) =>
      BoxDecoration(
        color: color ?? panel.withValues(alpha: 0.55),
        borderRadius: borderRadius ?? BorderRadius.circular(16),
        border: border ?? Border.all(color: glassBorder),
        boxShadow: shadows ?? softShadow(0.14),
      );

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: base.colorScheme.copyWith(
        primary: brandGold,
        onPrimary: brandBlueDeep,
        secondary: accent,
        surface: panel,
      ),
      dividerColor: outline.withValues(alpha: 0.35),
      cardTheme: CardThemeData(
        color: panel.withValues(alpha: 0.65),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: glassBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: panel,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: glassBorder),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: brandBlueDeep,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: outline.withValues(alpha: 0.6)),
        ),
        textStyle: const TextStyle(
          color: fg,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        waitDuration: const Duration(milliseconds: 400),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return brandGold.withValues(alpha: 0.6);
          }
          if (states.contains(WidgetState.hovered)) {
            return muted.withValues(alpha: 0.5);
          }
          return muted.withValues(alpha: 0.25);
        }),
        radius: const Radius.circular(8),
        thickness: WidgetStateProperty.all(6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brandGold,
          foregroundColor: brandBlueDeep,
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: fg,
          side: BorderSide(color: muted.withValues(alpha: 0.35)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: panelRaised.withValues(alpha: 0.42),
        labelStyle: const TextStyle(color: muted),
        hintStyle: TextStyle(color: muted.withValues(alpha: 0.78)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.55)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: outline.withValues(alpha: 0.55)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: brandGold, width: 1.4),
        ),
      ),
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        fontFamilyFallback: _fontFallback,
      ),
    );
  }
}
