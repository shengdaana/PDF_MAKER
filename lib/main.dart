import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/app_settings.dart';
import 'screens/home_screen.dart';
import 'screens/arrange_screen.dart';
import 'screens/edit_screen.dart';
import 'screens/pdf_library_screen.dart';
import 'screens/success_screen.dart';
import 'screens/settings_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await AppSettings.load();
  runApp(PdfMakerProApp(initialSettings: settings));
}

class AppStateScope extends InheritedWidget {
  final AppSettings settings;
  final Function(AppSettings) onSettingsChanged;

  const AppStateScope({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
    required super.child,
  });

  static AppStateScope of(BuildContext context) {
    final AppStateScope? result = context.dependOnInheritedWidgetOfExactType<AppStateScope>();
    assert(result != null, 'No AppStateScope found in context');
    return result!;
  }

  AppStrings get strings => AppStrings(settings.language);

  @override
  bool updateShouldNotify(AppStateScope oldWidget) {
    return settings != oldWidget.settings;
  }
}

class PdfMakerProApp extends StatefulWidget {
  final AppSettings initialSettings;

  const PdfMakerProApp({super.key, required this.initialSettings});

  @override
  State<PdfMakerProApp> createState() => _PdfMakerProAppState();
}

class _PdfMakerProAppState extends State<PdfMakerProApp> {
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

  ThemeData _buildTheme(AppThemePalette palette) {
    final bool isDark = palette == AppThemePalette.highContrastDark;

    Color primary;
    Color background;
    Color surface;
    Color onSurface;
    Color cardColor;

    switch (palette) {
      case AppThemePalette.indigoBlue:
        primary = const Color(0xFF4F46E5); // Indigo
        background = const Color(0xFFF8FAFC); // Clean off-white
        surface = Colors.white;
        onSurface = const Color(0xFF1A1C1E); // Deep Slate
        cardColor = Colors.white;
        break;
      case AppThemePalette.lightGreen:
        primary = const Color(0xFF16A34A); // Forest Green
        background = const Color(0xFFF0FDF4); // Soft pale green
        surface = Colors.white;
        onSurface = const Color(0xFF0F172A);
        cardColor = Colors.white;
        break;
      case AppThemePalette.purple:
        primary = const Color(0xFF7C3AED); // Deep Purple
        background = const Color(0xFFFAF5FF);
        surface = Colors.white;
        onSurface = const Color(0xFF1E1B4B);
        cardColor = Colors.white;
        break;
      case AppThemePalette.pink:
        primary = const Color(0xFFDB2777); // Rose / Pink
        background = const Color(0xFFFDF2F8);
        surface = Colors.white;
        onSurface = const Color(0xFF1F2937);
        cardColor = Colors.white;
        break;
      case AppThemePalette.highContrastDark:
        primary = const Color(0xFF818CF8); // Bright Indigo for dark contrast
        background = const Color(0xFF000000); // True Black
        surface = const Color(0xFF141414);
        onSurface = Colors.white;
        cardColor = const Color(0xFF1E1E1E);
        break;
    }

    final colorScheme = ColorScheme(
      brightness: isDark ? Brightness.dark : Brightness.light,
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
        elevation: isDark ? 0 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: isDark ? const BorderSide(color: Color(0xFF333333), width: 1.5) : BorderSide.none,
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
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 3,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: primary,
          side: BorderSide(color: primary, width: 2),
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      pageTransitionsTheme: _settings.premiumAnimations
          ? PageTransitionsTheme(
              builders: {
                TargetPlatform.android: const ZoomPageTransitionsBuilder(),
                TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
              },
            )
          : const PageTransitionsTheme(
              builders: {
                // Instant zero-cost transition for low-spec phones
                TargetPlatform.android: _NoAnimationPageTransitionsBuilder(),
                TargetPlatform.iOS: _NoAnimationPageTransitionsBuilder(),
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
        title: 'PDF Maker Pro',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(_settings.themePalette),
        initialRoute: '/',
        routes: {
          '/': (context) => const HomeScreen(),
          '/arrange': (context) => const ArrangeScreen(),
          '/library': (context) => const PdfLibraryScreen(),
          '/settings': (context) => const SettingsScreen(),
        },
      ),
    );
  }
}

class _NoAnimationPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimationPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<T> animation,
    Animation<T> secondaryAnimation,
    Widget child,
  ) {
    return child; // Instant render without GPU-heavy tween animations
  }
}
