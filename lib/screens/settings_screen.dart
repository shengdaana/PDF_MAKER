import 'package:flutter/material.dart';
import '../main.dart';
import '../models/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final settings = appScope.settings;
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    void update(AppSettings newSettings) {
      appScope.onSettingsChanged(newSettings);
      setState(() {});
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(strings.get('settings_title')),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16.0),
          children: [
            // 1. Visual Theme (5 High-Contrast Palettes)
            Text(
              strings.get('theme_title'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _themeCard(
                    title: 'Indigo / Blue',
                    color: const Color(0xFF4F46E5),
                    selected: settings.themePalette == AppThemePalette.indigoBlue,
                    onTap: () {
                      settings.themePalette = AppThemePalette.indigoBlue;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: 'Forest Green',
                    color: const Color(0xFF16A34A),
                    selected: settings.themePalette == AppThemePalette.lightGreen,
                    onTap: () {
                      settings.themePalette = AppThemePalette.lightGreen;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: 'Deep Purple',
                    color: const Color(0xFF7C3AED),
                    selected: settings.themePalette == AppThemePalette.purple,
                    onTap: () {
                      settings.themePalette = AppThemePalette.purple;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: 'Rose Pink',
                    color: const Color(0xFFDB2777),
                    selected: settings.themePalette == AppThemePalette.pink,
                    onTap: () {
                      settings.themePalette = AppThemePalette.pink;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: 'High Contrast Dark',
                    color: const Color(0xFF1A1A1A),
                    accentBorder: const Color(0xFF818CF8),
                    selected: settings.themePalette == AppThemePalette.highContrastDark,
                    onTap: () {
                      settings.themePalette = AppThemePalette.highContrastDark;
                      update(settings);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 2. App Language
            Text(
              strings.get('lang_title'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<AppLanguage>(
                    title: const Text('English (Default)'),
                    value: AppLanguage.english,
                    groupValue: settings.language,
                    onChanged: (val) {
                      if (val != null) {
                        settings.language = val;
                        update(settings);
                      }
                    },
                  ),
                  RadioListTile<AppLanguage>(
                    title: const Text('व्यावहारिक हिंदी (Everyday Hindi)'),
                    value: AppLanguage.everydayHindi,
                    groupValue: settings.language,
                    onChanged: (val) {
                      if (val != null) {
                        settings.language = val;
                        update(settings);
                      }
                    },
                  ),
                  RadioListTile<AppLanguage>(
                    title: const Text('Hinglish (Roman Hindi)'),
                    value: AppLanguage.hinglish,
                    groupValue: settings.language,
                    onChanged: (val) {
                      if (val != null) {
                        settings.language = val;
                        update(settings);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 3. PDF Page Sizing
            Text(
              strings.get('sizing_title'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<PdfPageSizing>(
                    title: const Text('Free / Dynamic (Native Aspect Ratio)'),
                    subtitle: const Text('Zero margins, no black bars, exact photo size'),
                    value: PdfPageSizing.freeDynamic,
                    groupValue: settings.pageSizing,
                    onChanged: (val) {
                      if (val != null) {
                        settings.pageSizing = val;
                        update(settings);
                      }
                    },
                  ),
                  RadioListTile<PdfPageSizing>(
                    title: const Text('A4 Standard'),
                    subtitle: const Text('Standard document page with margin borders'),
                    value: PdfPageSizing.a4Standard,
                    groupValue: settings.pageSizing,
                    onChanged: (val) {
                      if (val != null) {
                        settings.pageSizing = val;
                        update(settings);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 4. Quality Preset
            Text(
              strings.get('quality_preset_title'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  RadioListTile<PdfQualityPreset>(
                    title: const Text('Standard Quality (Default)'),
                    subtitle: const Text('Optimized for WhatsApp (~10MB limit)'),
                    value: PdfQualityPreset.standard,
                    groupValue: settings.qualityPreset,
                    onChanged: (val) {
                      if (val != null) {
                        settings.qualityPreset = val;
                        update(settings);
                      }
                    },
                  ),
                  RadioListTile<PdfQualityPreset>(
                    title: const Text('HD Original Quality'),
                    subtitle: const Text('Maximum clarity for printing & archiving'),
                    value: PdfQualityPreset.hdOriginal,
                    groupValue: settings.qualityPreset,
                    onChanged: (val) {
                      if (val != null) {
                        settings.qualityPreset = val;
                        update(settings);
                      }
                    },
                  ),
                  RadioListTile<PdfQualityPreset>(
                    title: const Text('Always Ask'),
                    subtitle: const Text('Prompt every time before creating PDF'),
                    value: PdfQualityPreset.alwaysAsk,
                    groupValue: settings.qualityPreset,
                    onChanged: (val) {
                      if (val != null) {
                        settings.qualityPreset = val;
                        update(settings);
                      }
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 5 & 6. Simplified Mode & Controls
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(strings.get('ocr_default_title')),
                    subtitle: const Text('Start Arrange screen with OCR toggle enabled'),
                    value: settings.ocrDefault,
                    onChanged: (val) {
                      settings.ocrDefault = val;
                      update(settings);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(strings.get('reorder_arrows_title')),
                    subtitle: const Text('Hides ▲/▼ arrows on page cards'),
                    value: settings.hideReorderArrows,
                    onChanged: (val) {
                      settings.hideReorderArrows = val;
                      update(settings);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(strings.get('merge_toggle_title')),
                    subtitle: const Text('Enables vertical page merge button on Arrange screen'),
                    value: settings.mergePagesBetweenPages,
                    onChanged: (val) {
                      settings.mergePagesBetweenPages = val;
                      update(settings);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(strings.get('anim_toggle_title')),
                    subtitle: Text(strings.get('anim_toggle_desc')),
                    value: settings.premiumAnimations,
                    onChanged: (val) {
                      settings.premiumAnimations = val;
                      update(settings);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 7. Default Save Folder
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_shared_rounded),
                title: Text(strings.get('save_folder_title')),
                subtitle: Text(settings.saveFolder),
                trailing: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Standard public documents directory is active.')),
                    );
                  },
                  child: const Text('Change'),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 8. Privacy & Security Footer
            Card(
              color: primaryColor.withOpacity(0.08),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security_rounded, color: primaryColor, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          strings.get('privacy_title'),
                          style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.get('privacy_desc'),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 9. Open Source Licenses
            Card(
              child: ListTile(
                leading: const Icon(Icons.policy_rounded),
                title: Text(strings.get('licenses_title')),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  showLicensePage(
                    context: context,
                    applicationName: 'PDF Maker Pro',
                    applicationVersion: '1.0.0',
                    applicationIcon: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Icon(Icons.picture_as_pdf_rounded, size: 48, color: primaryColor),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _themeCard({
    required String title,
    required Color color,
    Color? accentBorder,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? Colors.amberAccent : (accentBorder ?? Colors.transparent),
            width: selected ? 3.0 : 1.0,
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: Colors.amberAccent.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 2,
              )
          ],
        ),
        width: 120,
        height: 85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (selected)
              const Align(
                alignment: Alignment.topRight,
                child: Icon(Icons.check_circle_rounded, color: Colors.amberAccent, size: 18),
              )
            else
              const SizedBox(height: 18),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
