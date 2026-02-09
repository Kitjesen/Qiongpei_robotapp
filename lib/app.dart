import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'pages/shell_page.dart';

class QiongPeiApp extends StatefulWidget {
  const QiongPeiApp({super.key});

  @override
  State<QiongPeiApp> createState() => _QiongPeiAppState();
}

class _QiongPeiAppState extends State<QiongPeiApp> {
  ThemeMode _themeMode = ThemeMode.light;
  double _textScale = 1.0;
  BrandColor _brandColor = BrandColor.purple;

  void toggleTheme() {
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  void _changeBrandColor(BrandColor c) {
    setState(() {
      _brandColor = c;
      AppTheme.brand = c.color;
    });
  }

  void _onScaleUp() {
    setState(() { _textScale = (_textScale + 0.05).clamp(0.8, 1.4); });
  }

  void _onScaleDown() {
    setState(() { _textScale = (_textScale - 0.05).clamp(0.8, 1.4); });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '穹沛科技',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(_brandColor.color),
      darkTheme: AppTheme.dark(_brandColor.color),
      themeMode: _themeMode,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(_textScale)),
          child: child!,
        );
      },
      home: ShellPage(
        onToggleTheme: toggleTheme,
        isDark: _themeMode == ThemeMode.dark,
        textScale: _textScale,
        onScaleUp: _onScaleUp,
        onScaleDown: _onScaleDown,
        brandColor: _brandColor,
        onChangeBrandColor: _changeBrandColor,
      ),
    );
  }
}
