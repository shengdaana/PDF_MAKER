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
            // Dark Mode Switch
            Card(
              child: SwitchListTile(
                secondary: Icon(
                  settings.isDarkMode ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                  color: primaryColor,
                ),
                title: Text(
                  strings.get('dark_mode_title'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(strings.get('dark_mode_desc')),
                value: settings.isDarkMode,
                onChanged: (val) {
                  settings.isDarkMode = val;
                  update(settings);
                },
              ),
            ),

            const SizedBox(height: 16),

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
                    title: strings.get('theme_indigo'),
                    color: const Color(0xFF4F46E5),
                    selected: settings.themePalette == AppThemePalette.indigoBlue,
                    onTap: () {
                      settings.themePalette = AppThemePalette.indigoBlue;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: strings.get('theme_green'),
                    color: const Color(0xFF16A34A),
                    selected: settings.themePalette == AppThemePalette.lightGreen,
                    onTap: () {
                      settings.themePalette = AppThemePalette.lightGreen;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: strings.get('theme_purple'),
                    color: const Color(0xFF7C3AED),
                    selected: settings.themePalette == AppThemePalette.purple,
                    onTap: () {
                      settings.themePalette = AppThemePalette.purple;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: strings.get('theme_pink'),
                    color: const Color(0xFFDB2777),
                    selected: settings.themePalette == AppThemePalette.pink,
                    onTap: () {
                      settings.themePalette = AppThemePalette.pink;
                      update(settings);
                    },
                  ),
                  _themeCard(
                    title: strings.get('theme_high_contrast'),
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
                    title: Text(strings.get('lang_opt_english')),
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
                    title: Text(strings.get('lang_opt_hindi')),
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
                    title: Text(strings.get('lang_opt_hinglish')),
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
                    title: Text(strings.get('sizing_free_title')),
                    subtitle: Text(strings.get('sizing_free_desc')),
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
                    title: Text(strings.get('sizing_a4_title')),
                    subtitle: Text(strings.get('sizing_a4_desc')),
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
                    title: Text(strings.get('quality_std_setting_title')),
                    subtitle: Text(strings.get('quality_standard_desc')),
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
                    title: Text(strings.get('quality_hd')),
                    subtitle: Text(strings.get('quality_hd_desc')),
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
                    title: Text(strings.get('quality_ask_title')),
                    subtitle: Text(strings.get('quality_ask_desc')),
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

            // 5. Controls (FIX 5: Premium Animations toggle removed)
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: Text(strings.get('ocr_default_title')),
                    subtitle: Text(strings.get('ocr_default_desc')),
                    value: settings.ocrDefault,
                    onChanged: (val) {
                      settings.ocrDefault = val;
                      update(settings);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(strings.get('reorder_arrows_title')),
                    subtitle: Text(strings.get('reorder_arrows_desc')),
                    value: settings.hideReorderArrows,
                    onChanged: (val) {
                      settings.hideReorderArrows = val;
                      update(settings);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: Text(strings.get('merge_toggle_title')),
                    subtitle: Text(strings.get('merge_toggle_desc')),
                    value: settings.mergePagesBetweenPages,
                    onChanged: (val) {
                      settings.mergePagesBetweenPages = val;
                      update(settings);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Divider(),

            // 6. Default Save Folder
            Card(
              child: ListTile(
                leading: const Icon(Icons.folder_shared_rounded),
                title: Text(strings.get('save_folder_title')),
                subtitle: Text(settings.saveFolder),
                trailing: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(strings.get('msg_folder_active'))),
                    );
                  },
                  child: Text(strings.get('btn_change_folder')),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // 7. Privacy & Security Footer
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
                        Expanded(
                          child: Text(
                            strings.get('privacy_title'),
                            style: TextStyle(fontWeight: FontWeight.bold, color: primaryColor),
                          ),
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

            // 8. Open Source Licenses
            Card(
              child: ListTile(
                leading: const Icon(Icons.policy_rounded),
                title: Text(strings.get('licenses_title')),
                subtitle: const Text('Apache License 2.0'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      title: Row(
                        children: [
                          Icon(Icons.policy_rounded, color: primaryColor),
                          const SizedBox(width: 10),
                          Expanded(child: Text(strings.get('license_dialog_title'))),
                        ],
                      ),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            strings.get('app_title'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            strings.get('license_version'),
                            style: TextStyle(
                              color: theme.colorScheme.onSurface.withOpacity(0.6),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            strings.get('license_label'),
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: primaryColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: primaryColor.withOpacity(0.2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.verified_outlined, size: 18, color: primaryColor),
                                const SizedBox(width: 8),
                                const Text(
                                  'Apache License 2.0',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            strings.get('license_libs_note'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withOpacity(0.65),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(strings.get('close_btn')),
                        ),
                      ],
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
