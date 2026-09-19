import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import '../main.dart';
import '../services/share_handler_service.dart';
import 'arrange_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Listen for shared images from Gallery apps (both cold and warm starts)
    ShareHandlerService.init(
      onImagesReceived: (List<String> paths) {
        if (!mounted) return;
        _navigateToArrange(paths);
      },
    );
  }

  @override
  void dispose() {
    ShareHandlerService.dispose();
    super.dispose();
  }

  Future<void> _checkPermissionAndPickImages() async {
    setState(() => _isLoading = true);

    try {
      // Modern Android 13+ uses photos permission; legacy uses storage
      if (Platform.isAndroid) {
        final photosStatus = await Permission.photos.status;
        if (!photosStatus.isGranted && !photosStatus.isLimited) {
          final req = await Permission.photos.request();
          if (!req.isGranted && !req.isLimited) {
            // Fallback to legacy storage on Android 12 and below
            final storageStatus = await Permission.storage.request();
            if (!storageStatus.isGranted) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Storage permission is needed to select photos.')),
                );
              }
              setState(() => _isLoading = false);
              return;
            }
          }
        }
      }

      final List<XFile> picked = await _picker.pickMultiImage(
        imageQuality: 100, // We handle lossless EXIF & scaling ourselves
      );

      if (picked.isNotEmpty && mounted) {
        final paths = picked.map((e) => e.path).toList();
        _navigateToArrange(paths);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking images: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _navigateToArrange(List<String> paths) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ArrangeScreen(initialImagePaths: paths),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final bool enableAnim = appScope.settings.premiumAnimations;

    Widget content = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 12),

                    // 1. Header Banner Card
                    Card(
                      elevation: 1,
                      child: Padding(
                        padding: const EdgeInsets.all(22.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: primaryColor.withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(Icons.picture_as_pdf_rounded,
                                      color: primaryColor, size: 30),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    strings.get('banner_title'),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 20,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Text(
                              strings.get('banner_desc'),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.onSurface.withOpacity(0.75),
                                height: 1.4,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const Spacer(),

                    // 2. Primary Action Buttons (Adaptive, touch targets >= 48dp)
                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: _checkPermissionAndPickImages,
                        icon: const Icon(Icons.photo_library_rounded, size: 24),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            strings.get('btn_select_gallery'),
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 54),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onPressed: () {
                          Navigator.pushNamed(context, '/library');
                        },
                        icon: const Icon(Icons.folder_open_rounded, size: 24),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            strings.get('btn_see_pdfs'),
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],

                    const Spacer(),

                    // 3. Tip Card
                    Card(
                      elevation: 0,
                      color: primaryColor.withOpacity(0.08),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(color: primaryColor.withOpacity(0.2), width: 1),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 14.0),
                        child: Row(
                          children: [
                            Icon(Icons.lightbulb_outline_rounded,
                                color: primaryColor, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                strings.get('tip_footer'),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    if (enableAnim) {
      content = TweenAnimationBuilder<double>(
        tween: Tween(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
        builder: (context, val, child) {
          return Opacity(
            opacity: val,
            child: Transform.translate(
              offset: Offset(0, 16 * (1 - val)),
              child: child,
            ),
          );
        },
        child: content,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('app_title')),
        actions: [
          // Quick Dark Mode Toggle
          IconButton(
            icon: Icon(
              appScope.settings.isDarkMode
                  ? Icons.dark_mode_rounded
                  : Icons.light_mode_rounded,
              size: 24,
            ),
            tooltip: strings.get('dark_mode_title'),
            onPressed: () {
              appScope.settings.isDarkMode = !appScope.settings.isDarkMode;
              appScope.onSettingsChanged(appScope.settings);
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, size: 26),
            tooltip: strings.get('settings_title'),
            onPressed: () {
              Navigator.pushNamed(context, '/settings');
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(child: content),
    );
  }
}
