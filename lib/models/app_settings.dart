import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemePalette {
  indigoBlue,
  lightGreen,
  purple,
  pink,
  highContrastDark,
}

enum AppLanguage {
  english,
  everydayHindi,
  hinglish,
}

enum PdfPageSizing {
  freeDynamic,
  a4Standard,
}

enum PdfQualityPreset {
  standard,
  hdOriginal,
  alwaysAsk,
}

class AppSettings {
  AppThemePalette themePalette;
  AppLanguage language;
  PdfPageSizing pageSizing;
  PdfQualityPreset qualityPreset;
  bool ocrDefault;
  bool hideReorderArrows;
  bool mergePagesBetweenPages;
  bool premiumAnimations;
  String saveFolder;

  AppSettings({
    this.themePalette = AppThemePalette.indigoBlue,
    this.language = AppLanguage.english,
    this.pageSizing = PdfPageSizing.freeDynamic,
    this.qualityPreset = PdfQualityPreset.standard,
    this.ocrDefault = false,
    this.hideReorderArrows = false,
    this.mergePagesBetweenPages = false,
    this.premiumAnimations = false,
    this.saveFolder = 'Documents/PDF documents(pdf_maker)',
  });

  static const String _keyTheme = 'setting_theme';
  static const String _keyLang = 'setting_language';
  static const String _keySizing = 'setting_sizing';
  static const String _keyQuality = 'setting_quality';
  static const String _keyOcr = 'setting_ocr';
  static const String _keyHideArrows = 'setting_hide_arrows';
  static const String _keyMergePages = 'setting_merge_pages';
  static const String _keyAnimations = 'setting_animations';
  static const String _keyFolder = 'setting_folder';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, themePalette.name);
    await prefs.setString(_keyLang, language.name);
    await prefs.setString(_keySizing, pageSizing.name);
    await prefs.setString(_keyQuality, qualityPreset.name);
    await prefs.setBool(_keyOcr, ocrDefault);
    await prefs.setBool(_keyHideArrows, hideReorderArrows);
    await prefs.setBool(_keyMergePages, mergePagesBetweenPages);
    await prefs.setBool(_keyAnimations, premiumAnimations);
    await prefs.setString(_keyFolder, saveFolder);
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString(_keyTheme) ?? AppThemePalette.indigoBlue.name;
    final langStr = prefs.getString(_keyLang) ?? AppLanguage.english.name;
    final sizingStr = prefs.getString(_keySizing) ?? PdfPageSizing.freeDynamic.name;
    final qualityStr = prefs.getString(_keyQuality) ?? PdfQualityPreset.standard.name;

    return AppSettings(
      themePalette: AppThemePalette.values.firstWhere(
        (e) => e.name == themeStr,
        orElse: () => AppThemePalette.indigoBlue,
      ),
      language: AppLanguage.values.firstWhere(
        (e) => e.name == langStr,
        orElse: () => AppLanguage.english,
      ),
      pageSizing: PdfPageSizing.values.firstWhere(
        (e) => e.name == sizingStr,
        orElse: () => PdfPageSizing.freeDynamic,
      ),
      qualityPreset: PdfQualityPreset.values.firstWhere(
        (e) => e.name == qualityStr,
        orElse: () => PdfQualityPreset.standard,
      ),
      ocrDefault: prefs.getBool(_keyOcr) ?? false,
      hideReorderArrows: prefs.getBool(_keyHideArrows) ?? false,
      mergePagesBetweenPages: prefs.getBool(_keyMergePages) ?? false,
      premiumAnimations: prefs.getBool(_keyAnimations) ?? false,
      saveFolder: prefs.getString(_keyFolder) ?? 'Documents/PDF documents(pdf_maker)',
    );
  }
}

class AppStrings {
  final AppLanguage language;
  AppStrings(this.language);

  static final Map<AppLanguage, Map<String, String>> _localizedValues = {
    AppLanguage.english: {
      'app_title': 'PDF Maker Pro',
      'banner_title': 'Convert Photos to PDF',
      'banner_desc': 'Select photos from your gallery to create high-quality PDFs to send on WhatsApp or save.',
      'btn_select_gallery': 'Select From Gallery',
      'btn_see_pdfs': 'See Generated PDFs',
      'tip_footer': 'Tip: You can also select photos in your phone Gallery and tap Share → PDF Maker Pro!',
      'settings_title': 'Settings',
      'arrange_title': 'Arrange PDF Pages',
      'pages_selected': 'Pages selected',
      'toggle_flatten_all': 'Flatten all pages',
      'toggle_ocr': 'Make PDF searchable (OCR)',
      'btn_add_photos': '+ Add Photos',
      'btn_create_pdf': 'Create PDF Now',
      'btn_crop_rotate': 'Crop / Rotate',
      'btn_rotate_90': 'Rotate 90°',
      'btn_enhance': 'Enhance',
      'btn_flatten': 'Flatten',
      'btn_confirm': 'Confirm',
      'btn_discard': 'Cancel',
      'page_badge': 'Page',
      'merge_next': 'Merge with Next Page',
      'pdf_ready_title': 'Your PDF is Created!',
      'pdf_ready_subtitle': 'Saved automatically to your device.',
      'btn_share_pdf': 'Share PDF',
      'btn_view_pdf': 'View / Save Document',
      'btn_rename_pdf': 'Rename PDF',
      'select_quality_title': 'Select PDF Quality',
      'quality_standard': 'Standard Quality (Recommended)',
      'quality_standard_desc': 'Optimized for fast sending on WhatsApp (~10MB target)',
      'quality_hd': 'HD Original Quality',
      'quality_hd_desc': 'Full camera resolution for printing and archiving',
      'delete_confirm_title': 'Delete PDF?',
      'delete_confirm_desc': 'Are you sure you want to permanently delete this PDF file?',
      'delete_btn': 'Delete',
      'cancel_btn': 'Cancel',
      'no_pdfs_yet': 'No PDFs generated yet.\nTap "Select From Gallery" to create your first document.',
      'soft_warning_title': 'Large Document Notice',
      'soft_warning_msg': 'You have selected over 100 pages. On low-spec devices, processing may take extra time.',
      'theme_title': 'Visual Theme',
      'lang_title': 'App Language',
      'sizing_title': 'PDF Page Sizing',
      'quality_preset_title': 'PDF Quality Preset',
      'ocr_default_title': 'Searchable PDF (OCR) Default',
      'reorder_arrows_title': 'Hide Reorder Arrows',
      'merge_toggle_title': 'Merge Pages Between Pages',
      'anim_toggle_title': 'Premium Animations',
      'anim_toggle_desc': 'Smooth transitions and motion. Keep OFF on low-spec phones for maximum speed.',
      'save_folder_title': 'Default Save Folder',
      'privacy_title': 'Privacy & Security Guarantee',
      'privacy_desc': 'Zero data collection, zero telemetry, 100% offline. PDF Maker Pro runs entirely offline. No analytics, no accounts, and no internet access required.',
      'licenses_title': 'Open Source Licenses',
    },
    AppLanguage.everydayHindi: {
      'app_title': 'पीडीएफ मेकर प्रो',
      'banner_title': 'फोटो से पीडीएफ बनाएं',
      'banner_desc': 'गैलरी से फोटो चुनें और व्हाट्सएप पर भेजने या सेव करने के लिए शानदार पीडीएफ बनाएं।',
      'btn_select_gallery': 'गैलरी से फोटो चुनें',
      'btn_see_pdfs': 'बनाई गई पीडीएफ देखें',
      'tip_footer': 'सुझाव: आप फोन गैलरी में फोटो चुनकर शेयर → पीडीएफ मेकर प्रो भी कर सकते हैं!',
      'settings_title': 'सेटिंग्स',
      'arrange_title': 'पेज आगे-पीछे करें',
      'pages_selected': 'पेज चुने गए',
      'toggle_flatten_all': 'सभी पेज सीधे (फ्लैट) करें',
      'toggle_ocr': 'पीडीएफ को सर्च योग्य बनाएं (OCR)',
      'btn_add_photos': '+ और फोटो जोड़ें',
      'btn_create_pdf': 'अब पीडीएफ बनाएं',
      'btn_crop_rotate': 'क्रॉप / घुमाएं',
      'btn_rotate_90': '90° घुमाएं',
      'btn_enhance': 'साफ करें (Enhance)',
      'btn_flatten': 'सीधा करें (Flatten)',
      'btn_confirm': 'हो गया (Confirm)',
      'btn_discard': 'रद्द करें',
      'page_badge': 'पेज',
      'merge_next': 'अगले पेज के साथ जोड़ें',
      'pdf_ready_title': 'आपकी पीडीएफ बन गई!',
      'pdf_ready_subtitle': 'आपके फोन में अपने आप सेव हो गई है।',
      'btn_share_pdf': 'पीडीएफ शेयर करें',
      'btn_view_pdf': 'पीडीएफ देखें या खोलें',
      'btn_rename_pdf': 'नाम बदलें',
      'select_quality_title': 'पीडीएफ क्वालिटी चुनें',
      'quality_standard': 'सामान्य क्वालिटी (सुझावित)',
      'quality_standard_desc': 'व्हाट्सएप पर जल्दी भेजने के लिए सबसे बढ़िया',
      'quality_hd': 'एचडी ओरिजिनल क्वालिटी',
      'quality_hd_desc': 'प्रिंट और साफ लिखावट के लिए पूरा रेजोल्यूशन',
      'delete_confirm_title': 'पीडीएफ हटाएं?',
      'delete_confirm_desc': 'क्या आप सच में इस पीडीएफ को हमेशा के लिए हटाना चाहते हैं?',
      'delete_btn': 'हटाएं',
      'cancel_btn': 'रहने दें',
      'no_pdfs_yet': 'अभी कोई पीडीएफ नहीं बनी है।\nशुरू करने के लिए "गैलरी से फोटो चुनें" दबाएं।',
      'soft_warning_title': 'बड़ी फाइल की सूचना',
      'soft_warning_msg': 'आपने 100 से ज्यादा पेज चुने हैं। पुराने फोन पर इसमें थोड़ा समय लग सकता है।',
      'theme_title': 'रंग थीम',
      'lang_title': 'भाषा',
      'sizing_title': 'पेज का साइज',
      'quality_preset_title': 'क्वालिटी सेटिंग',
      'ocr_default_title': 'सर्च योग्य पीडीएफ (OCR) डिफ़ॉल्ट',
      'reorder_arrows_title': 'ऊपर-नीचे वाले तीर छुपाएं',
      'merge_toggle_title': 'पेज आपस में जोड़ने का बटन',
      'anim_toggle_title': 'स्मूथ एनिमेशन (Animations)',
      'anim_toggle_desc': 'धीमे या पुराने फोन पर तेज़ चलने के लिए इसे बंद ही रखें।',
      'save_folder_title': 'सेव होने का फोल्डर',
      'privacy_title': 'प्राइवेसी और सुरक्षा गारंटी',
      'privacy_desc': 'शून्य डेटा संग्रह, शून्य इंटरनेट। ऐप 100% ऑफलाइन काम करता है। कोई अकाउंट नहीं चाहिए।',
      'licenses_title': 'ओपन सोर्स लाइसेंस',
    },
    AppLanguage.hinglish: {
      'app_title': 'PDF Maker Pro',
      'banner_title': 'Photos se PDF Banayein',
      'banner_desc': 'Gallery se photos select karein aur WhatsApp par send ya save karne ke liye high-quality PDF banayein.',
      'btn_select_gallery': 'Gallery Se Select Karein',
      'btn_see_pdfs': 'Bani Hui PDFs Dekhein',
      'tip_footer': 'Tip: Aap phone gallery se photos choose karke Share → PDF Maker Pro bhi kar sakte hain!',
      'settings_title': 'Settings',
      'arrange_title': 'PDF Pages Arrange Karein',
      'pages_selected': 'Pages select hue',
      'toggle_flatten_all': 'Sabhi pages seedhe (Flatten) karein',
      'toggle_ocr': 'PDF Searchable Banayein (OCR)',
      'btn_add_photos': '+ Aur Photos Add Karein',
      'btn_create_pdf': 'Abhi PDF Banayein',
      'btn_crop_rotate': 'Crop / Rotate',
      'btn_rotate_90': '90° Rotate Karein',
      'btn_enhance': 'Saaf Karein (Enhance)',
      'btn_flatten': 'Seedha Karein (Flatten)',
      'btn_confirm': 'Confirm Karein',
      'btn_discard': 'Cancel',
      'page_badge': 'Page',
      'merge_next': 'Next Page ke sath Merge karein',
      'pdf_ready_title': 'Aapki PDF Ban Gayi!',
      'pdf_ready_subtitle': 'Device me automatically save ho gayi hai.',
      'btn_share_pdf': 'PDF Share Karein',
      'btn_view_pdf': 'Document Open Karein',
      'btn_rename_pdf': 'Rename Karein',
      'select_quality_title': 'PDF Quality Choose Karein',
      'quality_standard': 'Standard Quality (Best)',
      'quality_standard_desc': 'WhatsApp pe fast send karne ke liye best (~10MB)',
      'quality_hd': 'HD Original Quality',
      'quality_hd_desc': 'Printing aur original clarity ke liye',
      'delete_confirm_title': 'PDF Delete Karein?',
      'delete_confirm_desc': 'Kya aap is PDF file ko permanently delete karna chahte hain?',
      'delete_btn': 'Delete',
      'cancel_btn': 'Cancel',
      'no_pdfs_yet': 'Abhi tak koi PDF nahi bani hai.\nStart karne ke liye "Gallery Se Select Karein" tap karein.',
      'soft_warning_title': 'Badi Document Notice',
      'soft_warning_msg': '100 se zyada pages hain. Processing me thoda extra time lag sakta hai.',
      'theme_title': 'Theme Color',
      'lang_title': 'App Language',
      'sizing_title': 'PDF Page Size',
      'quality_preset_title': 'Default Quality',
      'ocr_default_title': 'Searchable PDF (OCR) Default',
      'reorder_arrows_title': 'Reorder Arrows Chupayein',
      'merge_toggle_title': 'Page Merge Button Dikhayein',
      'anim_toggle_title': 'Premium Animations',
      'anim_toggle_desc': 'Low-spec phones pe tez speed ke liye OFF rakhein.',
      'save_folder_title': 'Default Save Folder',
      'privacy_title': 'Privacy & Security',
      'privacy_desc': 'Zero data collection, 100% offline. Koi internet access nahi lagta.',
      'licenses_title': 'Open Source Licenses',
    },
  };

  String get(String key) {
    return _localizedValues[language]?[key] ?? _localizedValues[AppLanguage.english]?[key] ?? key;
  }
}
