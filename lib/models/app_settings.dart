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
  bool isDarkMode;
  bool ocrDefault;
  bool hideReorderArrows;
  bool mergePagesBetweenPages;
  String saveFolder;

  AppSettings({
    this.themePalette = AppThemePalette.indigoBlue,
    this.language = AppLanguage.english,
    this.pageSizing = PdfPageSizing.freeDynamic,
    this.qualityPreset = PdfQualityPreset.standard,
    this.isDarkMode = false,
    this.ocrDefault = false,
    this.hideReorderArrows = false,
    this.mergePagesBetweenPages = false,
    this.saveFolder = 'Documents/PDF Maker',
  });

  static const String _keyTheme = 'setting_theme';
  static const String _keyLang = 'setting_language';
  static const String _keySizing = 'setting_sizing';
  static const String _keyQuality = 'setting_quality';
  static const String _keyDarkMode = 'setting_dark_mode';
  static const String _keyOcr = 'setting_ocr';
  static const String _keyHideArrows = 'setting_hide_arrows';
  static const String _keyMergePages = 'setting_merge_pages';
  static const String _keyFolder = 'setting_folder';

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyTheme, themePalette.name);
    await prefs.setString(_keyLang, language.name);
    await prefs.setString(_keySizing, pageSizing.name);
    await prefs.setString(_keyQuality, qualityPreset.name);
    await prefs.setBool(_keyDarkMode, isDarkMode);
    await prefs.setBool(_keyOcr, ocrDefault);
    await prefs.setBool(_keyHideArrows, hideReorderArrows);
    await prefs.setBool(_keyMergePages, mergePagesBetweenPages);
    await prefs.setString(_keyFolder, saveFolder);
  }

  static Future<AppSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString(_keyTheme) ?? AppThemePalette.indigoBlue.name;
    final langStr = prefs.getString(_keyLang) ?? AppLanguage.english.name;
    final sizingStr = prefs.getString(_keySizing) ?? PdfPageSizing.freeDynamic.name;
    final qualityStr = prefs.getString(_keyQuality) ?? PdfQualityPreset.standard.name;
    String folder = prefs.getString(_keyFolder) ?? 'Documents/PDF Maker';
    if (folder == 'Documents/PDF Maker Pro') {
      folder = 'Documents/PDF Maker';
    }

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
      isDarkMode: prefs.getBool(_keyDarkMode) ?? (themeStr == AppThemePalette.highContrastDark.name),
      ocrDefault: prefs.getBool(_keyOcr) ?? false,
      hideReorderArrows: prefs.getBool(_keyHideArrows) ?? false,
      mergePagesBetweenPages: prefs.getBool(_keyMergePages) ?? false,
      saveFolder: folder,
    );
  }
}

class AppStrings {
  final AppLanguage language;
  AppStrings(this.language);

  static final Map<AppLanguage, Map<String, String>> _localizedValues = {
    AppLanguage.english: {
      'app_title': 'PDF Maker',
      'banner_title': 'Convert Photos to PDF',
      'banner_desc': 'Select photos from your gallery to create clear, high-quality PDFs to send on WhatsApp or save.',
      'btn_select_gallery': 'Select From Gallery',
      'btn_see_pdfs': 'See Generated PDFs',
      'tip_footer': 'Tip: You can also select photos in your phone Gallery and tap Share → PDF Maker!',
      'settings_title': 'Settings',
      'arrange_title': 'Arrange PDF Pages',
      'pages_selected': 'Pages',
      'toggle_ocr': 'Make PDF searchable (OCR)',
      'btn_add_photos': '+ Add Photos',
      'btn_create_pdf': 'Create PDF Now',
      'btn_crop_rotate': 'Crop / Rotate',
      'btn_rotate_90': 'Rotate 90°',
      'btn_reset_crop': 'Reset Crop',
      'btn_confirm': 'Confirm',
      'btn_discard': 'Cancel',
      'btn_undo': 'UNDO',
      'page_badge': 'Page',
      'tap_to_edit': 'Tap to crop or rotate',
      'merge_next': 'Merge with Next Page',
      'tooltip_move_up': 'Move page up',
      'tooltip_move_down': 'Move page down',
      'tooltip_delete_page': 'Delete page',
      'tooltip_reset_crop': 'Reset Crop to Full Frame',
      'crop_hint_bar': 'Drag 4 corners to crop & straighten document',
      'msg_could_not_load_image': 'Could not load image',
      'msg_storage_perm_needed': 'Photo permission is needed to select pictures.',
      'msg_error_picking_images': 'Error picking photos',
      'status_preparing_pages': 'Preparing pages...',
      'status_finalizing_pdf': 'Finalizing and saving PDF...',
      'msg_pdf_gen_failed': 'Could not create PDF',
      'pdf_ready_title': 'Your PDF is Created!',
      'pdf_ready_subtitle': 'Saved directly to your phone Documents folder.',
      'btn_share_pdf': 'Share PDF',
      'btn_share_short': 'Share',
      'btn_view_pdf': 'Open / View PDF',
      'btn_rename_pdf': 'Rename PDF',
      'label_location': 'Saved in',
      'share_pdf_text': 'Sharing PDF',
      'msg_could_not_open_pdf': 'Could not open PDF viewer',
      'msg_renamed_to': 'Renamed to',
      'select_quality_title': 'Select PDF Quality',
      'quality_standard': 'Standard Quality (Recommended)',
      'quality_standard_desc': 'Clear text & small file size (~1800px, 70% quality per page)',
      'quality_hd': 'HD Original Quality',
      'quality_hd_desc': 'Full camera resolution for printing and archiving',
      'quality_std_setting_title': 'Standard Quality (Default)',
      'quality_ask_title': 'Always Ask',
      'quality_ask_desc': 'Ask every time before creating a PDF',
      'delete_confirm_title': 'Delete PDF?',
      'delete_confirm_desc': 'Are you sure you want to delete this PDF from your phone?',
      'delete_batch_desc': 'Are you sure you want to permanently delete the selected PDFs?',
      'delete_btn': 'Delete',
      'delete_all_btn': 'Delete All',
      'cancel_btn': 'Cancel',
      'no_pdfs_yet': 'No PDFs created yet.\nTap "Select From Gallery" to make your first PDF.',
      'no_pdfs_match': 'No PDFs found for',
      'search_pdfs_hint': 'Search saved PDFs...',
      'tooltip_batch_select': 'Select multiple PDFs',
      'tooltip_refresh': 'Refresh list',
      'soft_warning_title': 'Large Document Notice',
      'soft_warning_msg': 'You selected over 100 pages. Creating the PDF may take a little extra time.',
      'theme_title': 'Color Theme',
      'theme_indigo': 'Indigo / Blue',
      'theme_green': 'Forest Green',
      'theme_purple': 'Deep Purple',
      'theme_pink': 'Rose Pink',
      'theme_high_contrast': 'High Contrast Dark',
      'lang_title': 'App Language',
      'lang_opt_english': 'English (Default)',
      'lang_opt_hindi': 'हिंदी (आम बोलचाल की भाषा)',
      'lang_opt_hinglish': 'Hinglish (Bolchal wali Hindi)',
      'sizing_title': 'PDF Page Size',
      'sizing_free_title': 'Original Photo Size (No Borders)',
      'sizing_free_desc': 'No white margins, keeps exact cropped photo shape',
      'sizing_a4_title': 'A4 Page Size',
      'sizing_a4_desc': 'Standard A4 sheet layout for printing',
      'sizing_a4_short': 'A4 Size',
      'sizing_orig_short': 'Original',
      'quality_preset_title': 'PDF Quality Setting',
      'ocr_default_title': 'Keep OCR On by Default',
      'ocr_default_desc': 'Automatically turn on text search (OCR) when arranging pages',
      'reorder_arrows_title': 'Hide Up/Down Arrows',
      'reorder_arrows_desc': 'Hide the ▲/▼ move buttons on page cards',
      'merge_toggle_title': 'Show "Merge Pages" Button',
      'merge_toggle_desc': 'Join two photos vertically onto a single PDF page',
      'dark_mode_title': 'Dark Mode',
      'dark_mode_desc': 'Use dark background across the app',
      'batch_export': 'Export to Downloads',
      'batch_export_short': 'Export',
      'batch_delete': 'Delete Selected',
      'select_all': 'Select All',
      'selected_count': 'Selected',
      'edit_pdf': 'Edit PDF',
      'tooltip_edit_pdf': 'Preview / Edit PDF',
      'tooltip_export_pdf': 'Save copy to Downloads',
      'msg_exported_single': 'Saved copy to Downloads/PDF Maker:',
      'msg_export_failed': 'Could not export to Downloads',
      'delete_pages_confirm_title': 'Delete Selected Pages?',
      'delete_pages_confirm_desc': 'Are you sure you want to remove the selected pages from this document?',
      'pdf_editor_title': 'Edit PDF',
      'edit_crop_btn': 'Crop / Rotate',
      'ocr_search_short': 'OCR Search',
      'save_changes': 'Save Changes',
      'save_as_copy': 'Save New Copy',
      'save_folder_title': 'Saved PDFs Folder',
      'btn_change_folder': 'Info',
      'msg_folder_active': 'PDFs are saved in your phone\'s public Documents/PDF Maker folder so they stay safe even if you uninstall the app.',
      'privacy_title': '100% Offline & Private',
      'privacy_desc': 'No internet permission, no ads, and no data tracking. All your photos and PDFs stay only on your phone.',
      'licenses_title': 'Open Source Licenses',
      'license_dialog_title': 'App & License Info',
      'license_version': 'Version 1.0.0',
      'license_label': 'License:',
      'license_libs_note': 'Built with open-source libraries: Flutter, pdf, printing, image, image_picker, receive_sharing_intent, share_plus, path_provider, shared_preferences, permission_handler (Apache 2.0 / BSD / MIT), and on-device ML Kit text recognition.',
      'close_btn': 'Close',
      'date_today': 'Today',
      'date_yesterday': 'Yesterday',
      'doc_name_label': 'PDF File Name',
      'tooltip_open_external': 'Open in PDF app',
      'rendering_previews': 'Loading PDF pages...',
      'tap_open_viewer': 'Tap above to open this PDF in your viewer app',
      'msg_cannot_delete_only_page': 'Cannot delete the only page in the PDF.',
      'msg_saved_new_copy': 'Saved new copy:',
      'msg_changes_saved_to': 'Changes saved to',
      'status_rasterizing_pdf': 'Opening PDF pages...',
    },
    AppLanguage.everydayHindi: {
      'app_title': 'PDF Maker',
      'banner_title': 'फोटो से PDF बनाएं',
      'banner_desc': 'गैलरी से फोटो चुनें और WhatsApp पर भेजने या फोन में सेव करने के लिए एकदम साफ PDF बनाएं।',
      'btn_select_gallery': 'गैलरी से फोटो चुनें',
      'btn_see_pdfs': 'बनी हुई PDF देखें',
      'tip_footer': 'टिप: आप सीधे फोन की Gallery से फोटो चुनकर Share → PDF Maker भी कर सकते हैं!',
      'settings_title': 'सेटिंग्स (Settings)',
      'arrange_title': 'पेज सेट करें',
      'pages_selected': 'पेज',
      'toggle_ocr': 'PDF में टेक्स्ट सर्च चालू करें (OCR)',
      'btn_add_photos': '+ और फोटो जोड़ें',
      'btn_create_pdf': 'अभी PDF बनाएं',
      'btn_crop_rotate': 'क्रॉप / घुमाएं',
      'btn_rotate_90': '90° घुमाएं',
      'btn_reset_crop': 'पूरी फोटो (Reset)',
      'btn_confirm': 'ठीक है (Done)',
      'btn_discard': 'रद्द करें',
      'btn_undo': 'वापस लाएं',
      'page_badge': 'पेज',
      'tap_to_edit': 'क्रॉप या घुमाने के लिए छुएं',
      'merge_next': 'अगले पेज के साथ एक ही पेज पर जोड़ें',
      'tooltip_move_up': 'पेज ऊपर ले जाएं',
      'tooltip_move_down': 'पेज नीचे ले जाएं',
      'tooltip_delete_page': 'पेज हटाएं',
      'tooltip_reset_crop': 'पूरी फोटो सिलेक्ट करें (Reset)',
      'crop_hint_bar': 'पेज को क्रॉप और सीधा करने के लिए चारों कोने सेट करें',
      'msg_could_not_load_image': 'फोटो लोड नहीं हो पाई',
      'msg_storage_perm_needed': 'गैलरी से फोटो चुनने के लिए परमिशन जरूरी है।',
      'msg_error_picking_images': 'फोटो चुनने में दिक्कत आई',
      'status_preparing_pages': 'पेज तैयार हो रहे हैं...',
      'status_finalizing_pdf': 'PDF फाइल सेव हो रही है...',
      'msg_pdf_gen_failed': 'PDF बनाने में दिक्कत आई',
      'pdf_ready_title': 'आपकी PDF तैयार है!',
      'pdf_ready_subtitle': 'आपके फोन के Documents फोल्डर में सेव हो गई है।',
      'btn_share_pdf': 'PDF शेयर करें',
      'btn_share_short': 'शेयर करें',
      'btn_view_pdf': 'PDF खोलकर देखें',
      'btn_rename_pdf': 'नाम बदलें (Rename)',
      'label_location': 'सेव जगह',
      'share_pdf_text': 'PDF फाइल',
      'msg_could_not_open_pdf': 'PDF खोलने के लिए फोन में कोई ऐप नहीं मिला',
      'msg_renamed_to': 'नया नाम सेव हो गया:',
      'select_quality_title': 'PDF की क्वालिटी चुनें',
      'quality_standard': 'नॉर्मल क्वालिटी (WhatsApp के लिए बेस्ट)',
      'quality_standard_desc': 'एकदम साफ अक्षर और कम साइज — जल्दी भेजने के लिए बढ़िया',
      'quality_hd': 'HD ओरिजिनल क्वालिटी',
      'quality_hd_desc': 'प्रिंट निकालने या फुल क्लैरिटी में रखने के लिए',
      'quality_std_setting_title': 'नॉर्मल क्वालिटी (डिफ़ॉल्ट)',
      'quality_ask_title': 'हर बार पूछें (Always Ask)',
      'quality_ask_desc': 'PDF बनाते समय हर बार क्वालिटी पूछें',
      'delete_confirm_title': 'PDF डिलीट करें?',
      'delete_confirm_desc': 'क्या आप सच में यह PDF फाइल फोन से डिलीट करना चाहते हैं?',
      'delete_batch_desc': 'क्या आप सच में चुनी हुई सभी PDF फाइलें डिलीट करना चाहते हैं?',
      'delete_btn': 'डिलीट करें',
      'delete_all_btn': 'सभी डिलीट करें',
      'cancel_btn': 'रहने दें',
      'no_pdfs_yet': 'अभी तक कोई PDF नहीं बनाई है।\nशुरू करने के लिए "गैलरी से फोटो चुनें" बटन दबाएं।',
      'no_pdfs_match': 'इस नाम की कोई PDF नहीं मिली:',
      'search_pdfs_hint': 'नाम से PDF खोजें...',
      'tooltip_batch_select': 'एक साथ कई PDF चुनें',
      'tooltip_refresh': 'लिस्ट रिफ्रेश करें',
      'soft_warning_title': 'बड़ी फाइल की जानकारी',
      'soft_warning_msg': 'आपने 100 से ज्यादा पेज चुने हैं। PDF बनने में थोड़ा सा ज्यादा समय लग सकता है।',
      'theme_title': 'ऐप का रंग (Theme)',
      'theme_indigo': 'नीला (Indigo)',
      'theme_green': 'हरा (Green)',
      'theme_purple': 'पर्पल (Purple)',
      'theme_pink': 'गुलाबी (Pink)',
      'theme_high_contrast': 'डार्क हाई-कॉन्ट्रास्ट',
      'lang_title': 'ऐप की भाषा (Language)',
      'lang_opt_english': 'English (अंग्रेजी)',
      'lang_opt_hindi': 'हिंदी (आम बोलचाल की भाषा)',
      'lang_opt_hinglish': 'Hinglish (बोलचाल वाली हिंदी)',
      'sizing_title': 'PDF पेज का साइज',
      'sizing_free_title': 'फोटो के साइज का पेज (बिना बॉर्डर)',
      'sizing_free_desc': 'चारों तरफ सफेद बॉर्डर नहीं आएगी, जितनी फोटो क्रॉप की है उतना ही पेज बनेगा',
      'sizing_a4_title': 'A4 साइज (प्रिंटिंग के लिए)',
      'sizing_a4_desc': 'फोटोकॉपी या प्रिंट निकालने वाले A4 कागज का साइज',
      'sizing_a4_short': 'A4 साइज',
      'sizing_orig_short': 'ओरिजिनल साइज',
      'quality_preset_title': 'PDF क्वालिटी सेटिंग',
      'ocr_default_title': 'टेक्स्ट सर्च (OCR) हमेशा चालू रखें',
      'ocr_default_desc': 'नई PDF बनाते समय OCR अपने आप चालू रहेगा',
      'reorder_arrows_title': 'ऊपर-नीचे करने वाले तीर छुपाएं',
      'reorder_arrows_desc': 'पेज कार्ड पर दिखने वाले ▲/▼ बटन छुपाएं',
      'merge_toggle_title': '"दो पेज जोड़ें" वाला बटन दिखाएं',
      'merge_toggle_desc': 'दो फोटो को ऊपर-नीचे एक ही पेज पर जोड़ने का ऑप्शन दिखाएं',
      'dark_mode_title': 'डार्क मोड (Dark Mode)',
      'dark_mode_desc': 'रात में आंखों के आराम के लिए काली स्क्रीन चालू करें',
      'batch_export': 'Downloads में सेव करें',
      'batch_export_short': 'एक्सपोर्ट',
      'batch_delete': 'एक साथ डिलीट करें',
      'select_all': 'सभी चुनें',
      'selected_count': 'चुने गए',
      'edit_pdf': 'PDF एडिट करें',
      'tooltip_edit_pdf': 'PDF देखें / एडिट करें',
      'tooltip_export_pdf': 'Downloads में कॉपी सेव करें',
      'msg_exported_single': 'Downloads/PDF Maker में सेव हो गई:',
      'msg_export_failed': 'Downloads में सेव नहीं हो पाई',
      'delete_pages_confirm_title': 'चुने हुए पेज हटाएं?',
      'delete_pages_confirm_desc': 'क्या आप चुने हुए सभी पेज इस लिस्ट से हटाना चाहते हैं?',
      'pdf_editor_title': 'PDF एडिट करें',
      'edit_crop_btn': 'क्रॉप / घुमाएं',
      'ocr_search_short': 'टेक्स्ट सर्च (OCR)',
      'save_changes': 'बदलाव सेव करें',
      'save_as_copy': 'नई कॉपी सेव करें',
      'save_folder_title': 'PDF सेव होने का फोल्डर',
      'btn_change_folder': 'जानकारी',
      'msg_folder_active': 'आपकी सभी PDF फोन के Documents/PDF Maker फोल्डर में सेव होती हैं। ऐप अनइंस्टॉल करने पर भी आपकी PDF डिलीट नहीं होंगी।',
      'privacy_title': '100% ऑफलाइन और सुरक्षित',
      'privacy_desc': 'यह ऐप बिना इंटरनेट के चलता है। कोई विज्ञापन नहीं, कोई डेटा ट्रैक नहीं होता — आपकी फोटो और PDF सिर्फ आपके फोन में रहती हैं।',
      'licenses_title': 'ओपन सोर्स लाइसेंस (Licenses)',
      'license_dialog_title': 'ऐप और लाइसेंस जानकारी',
      'license_version': 'वर्ज़न 1.0.0',
      'license_label': 'लाइसेंस:',
      'license_libs_note': 'ओपन-सोर्स टूल्स से बना: Flutter, pdf, printing, image, image_picker, receive_sharing_intent, share_plus, path_provider, shared_preferences, permission_handler (Apache 2.0 / BSD / MIT) और ऑफलाइन ML Kit OCR.',
      'close_btn': 'बंद करें',
      'date_today': 'आज',
      'date_yesterday': 'कल',
      'doc_name_label': 'PDF फाइल का नाम',
      'tooltip_open_external': 'दूसरे ऐप में खोलें',
      'rendering_previews': 'PDF के पेज लोड हो रहे हैं...',
      'tap_open_viewer': 'PDF देखने के लिए ऊपर ओपन बटन दबाएं',
      'msg_cannot_delete_only_page': 'PDF में कम से कम एक पेज होना जरूरी है।',
      'msg_saved_new_copy': 'नई कॉपी सेव हो गई:',
      'msg_changes_saved_to': 'बदलाव सेव हो गए:',
      'status_rasterizing_pdf': 'PDF के पेज निकाले जा रहे हैं...',
    },
    AppLanguage.hinglish: {
      'app_title': 'PDF Maker',
      'banner_title': 'Photos se PDF Banayein',
      'banner_desc': 'Gallery se photos select karo aur WhatsApp pe bhejne ya save karne ke liye ekdum clear PDF banao.',
      'btn_select_gallery': 'Gallery se Photos Chunein',
      'btn_see_pdfs': 'Bani Hui PDFs Dekhein',
      'tip_footer': 'Tip: Aap seedha phone Gallery me photos select karke Share → PDF Maker bhi kar sakte ho!',
      'settings_title': 'Settings',
      'arrange_title': 'PDF Pages Set Karein',
      'pages_selected': 'Pages',
      'toggle_ocr': 'PDF me text search on karein (OCR)',
      'btn_add_photos': '+ Aur Photos Jodein',
      'btn_create_pdf': 'Abhi PDF Banayein',
      'btn_crop_rotate': 'Crop / Rotate',
      'btn_rotate_90': '90° Ghumayein',
      'btn_reset_crop': 'Poori Photo (Reset)',
      'btn_confirm': 'Done (Save)',
      'btn_discard': 'Cancel',
      'btn_undo': 'WAPAS LAYEIN',
      'page_badge': 'Page',
      'tap_to_edit': 'Crop ya rotate karne ke liye tap karein',
      'merge_next': 'Agle page ke sath ek hi page pe jodein',
      'tooltip_move_up': 'Page upar le jayein',
      'tooltip_move_down': 'Page neeche le jayein',
      'tooltip_delete_page': 'Page hatayein',
      'tooltip_reset_crop': 'Poori photo select karein (Reset)',
      'crop_hint_bar': 'Page seedha karne ke liye charo corners drag karke set karein',
      'msg_could_not_load_image': 'Photo load nahi ho payi',
      'msg_storage_perm_needed': 'Gallery se photos lene ke liye permission zaroori hai.',
      'msg_error_picking_images': 'Photo select karne me dikkat aayi',
      'status_preparing_pages': 'Pages taiyar ho rahe hain...',
      'status_finalizing_pdf': 'PDF save ho rahi hai...',
      'msg_pdf_gen_failed': 'PDF nahi ban payi',
      'pdf_ready_title': 'Aapki PDF Ready Hai!',
      'pdf_ready_subtitle': 'Phone ke Documents folder me save ho gayi hai.',
      'btn_share_pdf': 'PDF Share Karein',
      'btn_share_short': 'Share',
      'btn_view_pdf': 'PDF Open Karein',
      'btn_rename_pdf': 'Naam Badlein (Rename)',
      'label_location': 'Save location',
      'share_pdf_text': 'Sharing PDF',
      'msg_could_not_open_pdf': 'PDF kholne ke liye phone me koi viewer app nahi mila',
      'msg_renamed_to': 'Naya naam save hua:',
      'select_quality_title': 'PDF Quality Chunein',
      'quality_standard': 'Standard Quality (WhatsApp ke liye best)',
      'quality_standard_desc': 'Clear text aur chota file size — jaldi send karne ke liye badhiya',
      'quality_hd': 'HD Original Quality',
      'quality_hd_desc': 'Print nikalne aur full camera clarity ke liye',
      'quality_std_setting_title': 'Standard Quality (Default)',
      'quality_ask_title': 'Har Baar Poochein (Always Ask)',
      'quality_ask_desc': 'PDF banate waqt har baar quality poochein',
      'delete_confirm_title': 'PDF Delete Karein?',
      'delete_confirm_desc': 'Kya aap sach me ye PDF file phone se delete karna chahte ho?',
      'delete_batch_desc': 'Kya aap sach me select ki hui saari PDFs delete karna chahte ho?',
      'delete_btn': 'Delete Karein',
      'delete_all_btn': 'Sab Delete Karein',
      'cancel_btn': 'Rehne Dein',
      'no_pdfs_yet': 'Abhi tak koi PDF nahi bani hai.\nShuru karne ke liye "Gallery se Photos Chunein" tap karein.',
      'no_pdfs_match': 'Is naam ki koi PDF nahi mili:',
      'search_pdfs_hint': 'Naam se PDF search karein...',
      'tooltip_batch_select': 'Ek sath kai PDF select karein',
      'tooltip_refresh': 'List refresh karein',
      'soft_warning_title': 'Badi PDF Notice',
      'soft_warning_msg': 'Aapne 100 se zyada pages select kiye hain. PDF banne me thoda extra time lag sakta hai.',
      'theme_title': 'App ka Color Theme',
      'theme_indigo': 'Indigo / Blue',
      'theme_green': 'Forest Green',
      'theme_purple': 'Deep Purple',
      'theme_pink': 'Rose Pink',
      'theme_high_contrast': 'High Contrast Dark',
      'lang_title': 'App ki Bhasha (Language)',
      'lang_opt_english': 'English (Default)',
      'lang_opt_hindi': 'हिंदी (आम बोलचाल की भाषा)',
      'lang_opt_hinglish': 'Hinglish (Bolchal wali Hindi)',
      'sizing_title': 'PDF Page ka Size',
      'sizing_free_title': 'Photo ke Size ka Page (Bina Border)',
      'sizing_free_desc': 'Koi white margin nahi aayegi, jitni photo crop ki hai utna hi page banega',
      'sizing_a4_title': 'A4 Standard Size',
      'sizing_a4_desc': 'Print nikalne wale normal A4 paper ka size',
      'sizing_a4_short': 'A4 Size',
      'sizing_orig_short': 'Original Size',
      'quality_preset_title': 'Default PDF Quality',
      'ocr_default_title': 'Text Search (OCR) Hamesha ON Rakhein',
      'ocr_default_desc': 'Nayi PDF banate waqt OCR toggle pehle se ON rahega',
      'reorder_arrows_title': 'Up/Down Arrows Chupayein',
      'reorder_arrows_desc': 'Page card pe dikhne wale ▲/▼ buttons hide karein',
      'merge_toggle_title': '"Merge Pages" Button Dikhayein',
      'merge_toggle_desc': 'Do photos ko upar-neeche ek hi PDF page pe jodne ka button dikhayein',
      'dark_mode_title': 'Dark Mode',
      'dark_mode_desc': 'Poore app me dark background chalu karein',
      'batch_export': 'Downloads me Save Karein',
      'batch_export_short': 'Export',
      'batch_delete': 'Ek Sath Delete Karein',
      'select_all': 'Sab Chunein',
      'selected_count': 'Selected',
      'edit_pdf': 'PDF Edit Karein',
      'tooltip_edit_pdf': 'PDF Dekhein / Edit Karein',
      'tooltip_export_pdf': 'Downloads me copy save karein',
      'msg_exported_single': 'Downloads/PDF Maker me save ho gayi:',
      'msg_export_failed': 'Downloads me save nahi ho payi',
      'delete_pages_confirm_title': 'Selected Pages Hatayein?',
      'delete_pages_confirm_desc': 'Kya aap select kiye hue saare pages hatana chahte ho?',
      'pdf_editor_title': 'PDF Edit Karein',
      'edit_crop_btn': 'Crop / Rotate',
      'ocr_search_short': 'Text Search (OCR)',
      'save_changes': 'Changes Save Karein',
      'save_as_copy': 'Nayi Copy Save Karein',
      'save_folder_title': 'PDF Save Hone ka Folder',
      'btn_change_folder': 'Info',
      'msg_folder_active': 'Aapki saari PDFs phone ke public Documents/PDF Maker folder me save hoti hain. App uninstall karne pe bhi PDFs delete nahi hongi.',
      'privacy_title': '100% Offline & Safe',
      'privacy_desc': 'Bina internet ke chalta hai. Koi ads nahi, koi data tracking nahi — aapke photos aur PDFs sirf aapke phone me rehte hain.',
      'licenses_title': 'Open Source Licenses',
      'license_dialog_title': 'App & License Info',
      'license_version': 'Version 1.0.0',
      'license_label': 'License:',
      'license_libs_note': 'Open-source libraries se bana: Flutter, pdf, printing, image, image_picker, receive_sharing_intent, share_plus, path_provider, shared_preferences, permission_handler (Apache 2.0 / BSD / MIT) aur offline ML Kit OCR.',
      'close_btn': 'Band Karein',
      'date_today': 'Aaj (Today)',
      'date_yesterday': 'Kal (Yesterday)',
      'doc_name_label': 'PDF File ka Naam',
      'tooltip_open_external': 'PDF viewer app me kholein',
      'rendering_previews': 'PDF ke pages load ho rahe hain...',
      'tap_open_viewer': 'PDF dekhne ke liye upar open button dabayein',
      'msg_cannot_delete_only_page': 'PDF me kam se kam ek page hona zaroori hai.',
      'msg_saved_new_copy': 'Nayi copy save ho gayi:',
      'msg_changes_saved_to': 'Changes save ho gaye:',
      'status_rasterizing_pdf': 'PDF ke pages nikale ja rahe hain...',
    },
  };

  String get(String key) {
    return _localizedValues[language]?[key] ?? _localizedValues[AppLanguage.english]?[key] ?? key;
  }

  String pageOf(int current, int total) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return 'पेज $current / $total';
      case AppLanguage.hinglish:
        return 'Page $current / $total';
      case AppLanguage.english:
        return 'Page $current of $total';
    }
  }

  String pageDeleted(int pageNum) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return 'पेज $pageNum हटा दिया गया';
      case AppLanguage.hinglish:
        return 'Page $pageNum hata diya gaya';
      case AppLanguage.english:
        return 'Page $pageNum deleted';
    }
  }

  String processingPage(int current, int total) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return 'पेज $current / $total तैयार हो रहा है...';
      case AppLanguage.hinglish:
        return 'Page $current / $total taiyar ho raha hai...';
      case AppLanguage.english:
        return 'Processing page $current of $total...';
    }
  }

  String runningOcrOnPage(int current) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return 'पेज $current पर टेक्स्ट पहचाना जा रहा है (OCR)...';
      case AppLanguage.hinglish:
        return 'Page $current pe text read ho raha hai (OCR)...';
      case AppLanguage.english:
        return 'Running on-device OCR on page $current...';
    }
  }

  String extractedPages(int count) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return '$count पेज निकाले गए...';
      case AppLanguage.hinglish:
        return '$count pages nikale gaye...';
      case AppLanguage.english:
        return 'Extracted $count pages...';
    }
  }

  String deleteMultipleTitle(int count) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return '$count PDF फाइलें डिलीट करें?';
      case AppLanguage.hinglish:
        return '$count PDFs delete karein?';
      case AppLanguage.english:
        return 'Delete $count PDFs?';
    }
  }

  String deletedSingleFile(String name) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return '$name डिलीट कर दी गई';
      case AppLanguage.hinglish:
        return '$name delete kar di gayi';
      case AppLanguage.english:
        return 'Deleted $name';
    }
  }

  String deletedMultipleFiles(int count) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return '$count फाइलें डिलीट कर दी गईं';
      case AppLanguage.hinglish:
        return '$count files delete kar di gayin';
      case AppLanguage.english:
        return 'Deleted $count files';
    }
  }

  String exportedMultipleFiles(int count) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return '$count PDF फाइलें Downloads/PDF Maker फोल्डर में सेव हो गईं';
      case AppLanguage.hinglish:
        return '$count PDFs Downloads/PDF Maker folder me save ho gayin';
      case AppLanguage.english:
        return 'Exported $count PDFs to Downloads/PDF Maker';
    }
  }

  String deletedMultiplePages(int count) {
    switch (language) {
      case AppLanguage.everydayHindi:
        return '$count पेज हटा दिए गए';
      case AppLanguage.hinglish:
        return '$count pages hata diye gaye';
      case AppLanguage.english:
        return 'Removed $count pages';
    }
  }

  String formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final fileDate = DateTime(dt.year, dt.month, dt.day);

    final difference = today.difference(fileDate).inDays;
    if (difference == 0) return get('date_today');
    if (difference == 1) return get('date_yesterday');

    if (language == AppLanguage.everydayHindi) {
      if (difference < 7) {
        const weekdaysHi = ['सोमवार', 'मंगलवार', 'बुधवार', 'गुरुवार', 'शुक्रवार', 'शनिवार', 'रविवार'];
        return weekdaysHi[dt.weekday - 1];
      }
      const monthsHi = [
        'जनवरी', 'फरवरी', 'मार्च', 'अप्रैल', 'मई', 'जून',
        'जुलाई', 'अगस्त', 'सितंबर', 'अक्टूबर', 'नवंबर', 'दिसंबर'
      ];
      return '${dt.day} ${monthsHi[dt.month - 1]} ${dt.year}';
    }

    if (difference < 7) {
      const weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return weekdays[dt.weekday - 1];
    }
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}
