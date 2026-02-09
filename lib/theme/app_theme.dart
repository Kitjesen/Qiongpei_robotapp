import 'package:flutter/material.dart';

/// Available brand color presets.
enum BrandColor {
  purple('Purple', Color(0xFF422AFB)),
  blue('Blue', Color(0xFF2563EB)),
  teal('Teal', Color(0xFF0D9488)),
  green('Green', Color(0xFF059669)),
  orange('Orange', Color(0xFFEA580C)),
  pink('Pink', Color(0xFFDB2777));

  final String label;
  final Color color;
  const BrandColor(this.label, this.color);
}

class AppTheme {
  AppTheme._();

  /// Current brand color — mutable, changed via sidebar.
  static Color brand = BrandColor.purple.color;

  static const Color green = Color(0xFF01B574);
  static const Color red = Color(0xFFEE5D50);
  static const Color orange = Color(0xFFFFB547);
  static const Color yellow = Color(0xFFFFC312);
  static const Color teal = Color(0xFF2B77E7);
  static const Color purple = Color(0xFF7551FF);

  static const _lBg = Color(0xFFF4F7FE);
  static const _lCard = Colors.white;
  static const _lText = Color(0xFF000000);
  static const _lGray = Color(0xFF555555);
  static const _dBg = Color(0xFF0B1437);
  static const _dCard = Color(0xFF111C44);
  static const _dText = Color(0xFFF5F5F5);
  static const _dGray = Color(0xFF9A9AAF);

  static const _fallback = ['Microsoft YaHei UI', 'PingFang SC', 'Noto Sans SC', 'sans-serif'];

  static BoxDecoration cardDeco(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return BoxDecoration(
      color: dark ? _dCard : _lCard,
      borderRadius: BorderRadius.circular(14),
      boxShadow: dark ? [] : const [BoxShadow(color: Color(0x08000000), blurRadius: 20, offset: Offset(0, 4))],
    );
  }

  static ThemeData light([Color? brandOverride]) => _make(Brightness.light, _lBg, _lCard, _lText, _lGray, brandOverride ?? brand);
  static ThemeData dark([Color? brandOverride]) => _make(Brightness.dark, _dBg, _dCard, _dText, _dGray, brandOverride ?? brand);

  static ThemeData _make(Brightness b, Color bg, Color card, Color text, Color gray, Color brandC) {
    final isL = b == Brightness.light;
    return ThemeData(
      brightness: b,
      useMaterial3: true,
      fontFamily: 'Inter',
      fontFamilyFallback: _fallback,
      scaffoldBackgroundColor: bg,
      colorScheme: (isL ? const ColorScheme.light() : const ColorScheme.dark()).copyWith(
        primary: brandC, onPrimary: Colors.white, surface: card, onSurface: text,
        outline: isL ? const Color(0xFFE9EDF7) : const Color(0xFF1B254B),
        surfaceContainerHighest: isL ? Colors.white : _dCard,
      ),
      cardTheme: CardThemeData(elevation: 0, color: card, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), margin: EdgeInsets.zero),
      dividerColor: isL ? const Color(0xFFE9EDF7) : const Color(0xFF1B254B),
      textTheme: TextTheme(
        headlineLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        headlineMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        headlineSmall: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        titleLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        titleMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: text, fontFamilyFallback: _fallback),
        bodyLarge: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: text, fontFamilyFallback: _fallback),
        bodyMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: gray, fontFamilyFallback: _fallback),
        bodySmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: gray, fontFamilyFallback: _fallback),
        labelLarge: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: text, fontFamilyFallback: _fallback),
        labelMedium: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: gray, fontFamilyFallback: _fallback),
        labelSmall: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: gray, letterSpacing: 0.5, fontFamilyFallback: _fallback),
      ),
    );
  }
}
