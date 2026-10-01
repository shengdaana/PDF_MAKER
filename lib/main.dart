import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'models/app_settings.dart';
import 'screens/home_screen.dart';
import 'screens/arrange_pages_screen.dart';
import 'screens/generated_pdfs_screen.dart';
import 'screens/settings_screen.dart';
import 'utils/image_processor.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Cap decoded image cache to 100 MB / 150 images for smooth 60fps memory behavior
  PaintingBinding.instance.imageCache.maximumSizeBytes = 100 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 150;

  final settings = await AppSettings.load();
  runApp(PdfMakerApp(initialSettings: settings));

  // Asynchronously clean up stale temporary preview files in the background
  ImageProcessor.cleanupOldTempFiles();
}

class AppStateScope extends InheritedWidget {
  final AppSettings settings;
  final AppStrings strings;
  final Function(AppSettings) onSettingsChanged;

  AppStateScope({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required super.child,
  }) : strings = AppStrings(settings.language);

  static AppStateScope of(BuildContext context) {
    final AppStateScope? result = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(result != null, 'No AppStateScope found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(AppStateScope oldWidget) {
    return true;
  }
}

class PdfMakerApp extends StatefulWidget {
  final AppSettings initialSettings;

  const PdfMakerApp({super.key, required this.initialSettings});

  @override
  State<PdfMakerApp> createState() => _PdfMakerAppState();
}

class _PdfMakerAppState extends State<PdfMakerApp> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.initialSettings;
  }

  void _updateSettings(AppSettings newSettings) {
    setState(() {
      _settings = newSettings;
    });
    _settings.save();
  }

  ThemeData _buildTheme(AppThemePalette palette, {required bool isDark}) {
    final bool effectiveDark = isDark || palette == AppThemePalette.highContrastDark;

    Color primary;
    Color background;
    Color surface;
    Color onSurface;
    Color cardColor;

    switch (palette) {
      case AppThemePalette.indigoBlue:
        primary = effectiveDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5);
        break;
      case AppThemePalette.lightGreen:
        primary = effectiveDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
        break;
      case AppThemePalette.purple:
        primary = effectiveDark ? const Color(0xFFA78BFA) : const Color(0xFF7C3AED);
        break;
      case AppThemePalette.pink:
        primary = effectiveDark ? const Color(0xFFF472B6) : const Color(0xFFDB2777);
        break;
      case AppThemePalette.highContrastDark:
        primary = const Color(0xFF818CF8);
        break;
    }

    if (effectiveDark) {
      final isHighContrast = palette == AppThemePalette.highContrastDark;
      background = isHighContrast ? const Color(0xFF000000) : const Color(0xFF121212);
      surface = isHighContrast ? const Color(0xFF141414) : const Color(0xFF1E1E1E);
      onSurface = Colors.white;
      cardColor = isHighContrast ? const Color(0xFF1E1E1E) : const Color(0xFF242424);
    } else {
      switch (palette) {
        case AppThemePalette.indigoBlue:
          background = const Color(0xFFF8FAFC);
          surface = Colors.white;
          onSurface = const Color(0xFF1A1C1E);
          cardColor = Colors.white;
          break;
        case AppThemePalette.lightGreen:
          background = const Color(0xFFF0FDF4);
          surface = Colors.white;
          onSurface = const Color(0xFF0F172A);
          cardColor = Colors.white;
          break;
        case AppThemePalette.purple:
          background = const Color(0xFFFAF5FF);
          surface = Colors.white;
          onSurface = const Color(0xFF1E1B4B);
          cardColor = Colors.white;
          break;
        case AppThemePalette.pink:
          background = const Color(0xFFFDF2F8);
          surface = Colors.white;
          onSurface = const Color(0xFF1F2937);
          cardColor = Colors.white;
          break;
        default:
          background = const Color(0xFFF8FAFC);
          surface = Colors.white;
          onSurface = const Color(0xFF1A1C1E);
          cardColor = Colors.white;
      }
    }

    final colorScheme = ColorScheme(
      brightness: effectiveDark ? Brightness.dark : Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      secondary: primary,
      onSecondary: Colors.white,
      error: Colors.redAccent,
      onError: Colors.white,
      surface: surface,
      onSurface: onSurface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      cardColor: cardColor,
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: effectiveDark ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: effectiveDark ? const BorderSide(color: Color(0xFF333333), width: 1.5) : BorderSide.none,
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 20,
          fontWeight: FontWeight.bold,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 2,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 2),
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      // Simple, lightweight page transitions everywhere by default (FIX 5)
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      settings: _settings,
      onSettingsChanged: _updateSettings,
      child: MaterialApp(
        title: 'PDF Maker',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(_settings.themePalette, isDark: false),
        darkTheme: _buildTheme(_settings.themePalette, isDark: true),
        themeMode: _settings.isDarkMode ? ThemeMode.dark : ThemeMode.light,
        initialRoute: '/',
        routes: {
          '/': (context) => const HomeScreen(),
          '/arrange': (context) => const ArrangePagesScreen(),
          '/library': (context) => const GeneratedPdfsScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}
