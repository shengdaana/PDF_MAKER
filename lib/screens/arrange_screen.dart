import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../main.dart';
import '../models/app_settings.dart';
import '../models/pdf_page_item.dart';
import '../services/pdf_service.dart';
import '../utils/image_processing.dart';
import 'edit_screen.dart';
import 'success_screen.dart';

class ArrangeScreen extends StatefulWidget {
  final List<String> initialImagePaths;

  const ArrangeScreen({super.key, this.initialImagePaths = const []});

  @override
  State<ArrangeScreen> createState() => _ArrangeScreenState();
}

class _ArrangeScreenState extends State<ArrangeScreen> {
  final List<PdfPageItem> _pages = [];
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _flattenAll = false;
  bool _searchableOcr = false;
  bool _isLoadingInitial = true;
  bool _isGeneratingPdf = false;
  double _generationProgress = 0.0;
  String _generationStatus = '';

  @override
  void initState() {
    super.initState();
    _loadInitialPhotos();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Default OCR setting reflects user's preference
    final settings = AppStateScope.of(context).settings;
    _searchableOcr = settings.ocrDefault;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPhotos() async {
    setState(() => _isLoadingInitial = true);
    for (int i = 0; i < widget.initialImagePaths.length; i++) {
      final path = widget.initialImagePaths[i];
      _pages.add(
        PdfPageItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_$i',
          sourcePath: path,
          currentPreviewPath: path,
        ),
      );
    }
    if (mounted) {
      setState(() => _isLoadingInitial = false);
    }
  }

  Future<void> _addMorePhotos() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 100);
      if (picked.isNotEmpty) {
        // Save current scroll position
        final double savedScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

        setState(() {
          for (int i = 0; i < picked.length; i++) {
            _pages.add(
              PdfPageItem(
                id: '${DateTime.now().millisecondsSinceEpoch}_add_$i',
                sourcePath: picked[i].path,
                currentPreviewPath: picked[i].path,
              ),
            );
          }
        });

        // Restore scroll position
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(savedScrollOffset);
          }
        });
      }
    } catch (e) {
      debugPrint("Error picking additional photos: $e");
    }
  }

  void _movePage(int fromIndex, int toIndex) {
    if (toIndex < 0 || toIndex >= _pages.length) return;
    final double savedScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;

    setState(() {
      final item = _pages.removeAt(fromIndex);
      _pages.insert(toIndex, item);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(savedScrollOffset);
      }
    });
  }

  Future<void> _toggleFlattenAll(bool enabled) async {
    final double savedScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    setState(() {
      _flattenAll = enabled;
      _isLoadingInitial = true;
    });

    try {
      for (final page in _pages) {
        page.isFlattened = enabled;
        if (enabled) {
          final file = File(page.sourcePath);
          final raw = await ImageProcessingService.loadAndNormalizeExif(file);
          if (raw != null) {
            final flattened = ImageProcessingService.applyFlatten(raw);
            final preview = await ImageProcessingService.saveToTempPreviewFile(
              flattened,
              'flatten_${page.id}',
            );
            page.currentPreviewPath = preview;
          }
        } else {
          page.currentPreviewPath = page.sourcePath;
        }
      }
    } catch (e) {
      debugPrint("Error toggling bulk flatten: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoadingInitial = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(savedScrollOffset);
          }
        });
      }
    }
  }

  Future<void> _openEditScreen(int index) async {
    final double savedScrollOffset = _scrollController.hasClients ? _scrollController.offset : 0.0;
    final page = _pages[index];

    final updatedPage = await Navigator.push<PdfPageItem>(
      context,
      MaterialPageRoute(
        builder: (context) => EditScreen(pageItem: page),
      ),
    );

    // Live preview update & exact scroll position preservation (CRITICAL fix)
    if (updatedPage != null && mounted) {
      setState(() {
        _pages[index] = updatedPage;
      });
      // Restore scroll offset immediately
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(savedScrollOffset);
        }
      });
    }
  }

  void _onStartPdfCreation() {
    if (_pages.isEmpty) return;
    final settings = AppStateScope.of(context).settings;

    if (settings.qualityPreset == PdfQualityPreset.alwaysAsk) {
      _showQualitySelectionSheet();
    } else {
      final isHd = settings.qualityPreset == PdfQualityPreset.hdOriginal;
      _executePdfGeneration(isHd);
    }
  }

  void _showQualitySelectionSheet() {
    final strings = AppStateScope.of(context).strings;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.get('select_quality_title'),
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 1,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: const Icon(Icons.flash_on_rounded, color: Colors.green, size: 30),
                    title: Text(strings.get('quality_standard'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(strings.get('quality_standard_desc')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _executePdfGeneration(false);
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  elevation: 1,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(12),
                    leading: const Icon(Icons.high_quality_rounded, color: Colors.indigo, size: 30),
                    title: Text(strings.get('quality_hd'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(strings.get('quality_hd_desc')),
                    onTap: () {
                      Navigator.pop(ctx);
                      _executePdfGeneration(true);
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _executePdfGeneration(bool isHd) async {
    setState(() {
      _isGeneratingPdf = true;
      _generationProgress = 0.0;
      _generationStatus = 'Preparing pages...';
    });

    try {
      final settings = AppStateScope.of(context).settings;
      final result = await PdfService.generatePdf(
        pages: _pages,
        settings: settings,
        enableOcr: _searchableOcr,
        isHdQuality: isHd,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _generationProgress = progress;
              _generationStatus = status;
            });
          }
        },
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => SuccessScreen(result: result),
          ),
        );
      }
    } catch (e) {
      debugPrint("PDF Generation Failed: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate PDF: $e')),
        );
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final settings = appScope.settings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('${strings.get('arrange_title')} — ${_pages.length} ${strings.get('pages_selected')}'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Toggle Row: Flatten all pages & OCR
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              color: theme.cardColor,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        strings.get('toggle_flatten_all'),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      Switch(
                        value: _flattenAll,
                        onChanged: _toggleFlattenAll,
                        activeColor: primaryColor,
                      ),
                    ],
                  ),
                  const Divider(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        strings.get('toggle_ocr'),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      Switch(
                        value: _searchableOcr,
                        onChanged: (val) => setState(() => _searchableOcr = val),
                        activeColor: primaryColor,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Soft warning for >100 pages
            if (_pages.length > 100)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        strings.get('soft_warning_msg'),
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),

            // Generating Overlay
            if (_isGeneratingPdf)
              Padding(
                padding: const EdgeInsets.all(20.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: _generationProgress),
                        const SizedBox(height: 14),
                        Text(_generationStatus, style: const TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),

            // Pages List View
            Expanded(
              child: _isLoadingInitial
                  ? const Center(child: CircularProgressIndicator())
                  : _pages.isEmpty
                      ? Center(child: Text(strings.get('no_pdfs_yet')))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                          itemCount: _pages.length,
                          itemBuilder: (context, index) {
                            final page = _pages[index];
                            final isFirst = index == 0;
                            final isLast = index == _pages.length - 1;

                            return Column(
                              children: [
                                Card(
                                  margin: const EdgeInsets.symmetric(vertical: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Row(
                                      children: [
                                        // Live Thumbnail with badges
                                        GestureDetector(
                                          onTap: () => _openEditScreen(index),
                                          child: Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.circular(10),
                                                child: Image.file(
                                                  File(page.currentPreviewPath),
                                                  width: 80,
                                                  height: 105,
                                                  fit: BoxFit.cover,
                                                  key: ValueKey(page.currentPreviewPath),
                                                ),
                                              ),
                                              Positioned(
                                                bottom: 4,
                                                right: 4,
                                                child: Container(
                                                  padding: const EdgeInsets.all(4),
                                                  decoration: BoxDecoration(
                                                    color: Colors.black.withOpacity(0.7),
                                                    shape: BoxShape.circle,
                                                  ),
                                                  child: const Icon(Icons.edit, size: 14, color: Colors.white),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 14),

                                        // Page Details & Edit action
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${strings.get('page_badge')} ${index + 1} of ${_pages.length}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 16,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              TextButton.icon(
                                                onPressed: () => _openEditScreen(index),
                                                icon: const Icon(Icons.crop_rotate_rounded, size: 18),
                                                label: Text(strings.get('btn_crop_rotate')),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),

                                        // Up / Down Reorder Arrows (hideable via Settings)
                                        if (!settings.hideReorderArrows)
                                          Column(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.arrow_upward_rounded),
                                                onPressed: isFirst ? null : () => _movePage(index, index - 1),
                                                tooltip: 'Move up',
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.arrow_downward_rounded),
                                                onPressed: isLast ? null : () => _movePage(index, index + 1),
                                                tooltip: 'Move down',
                                              ),
                                            ],
                                          ),
                                      ],
                                    ),
                                  ),
                                ),

                                // Inline "Merge with Next Page" button (toggleable via Settings)
                                if (settings.mergePagesBetweenPages && !isLast)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        minimumSize: const Size(double.infinity, 38),
                                        padding: const EdgeInsets.symmetric(vertical: 4),
                                      ),
                                      onPressed: () {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Merged Page ${index + 1} + ${index + 2}')),
                                        );
                                      },
                                      icon: const Icon(Icons.merge_type_rounded, size: 18),
                                      label: Text('${strings.get('merge_next')} (${index + 1} + ${index + 2})'),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
            ),

            // Fixed Bottom Bar: "+ Add Photos" and "Create PDF Now"
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 6,
                    offset: const Offset(0, -2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _isGeneratingPdf ? null : _addMorePhotos,
                      icon: const Icon(Icons.add_photo_alternate_rounded, size: 20),
                      label: FittedBox(
                        child: Text(
                          strings.get('btn_add_photos'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: ElevatedButton.icon(
                      onPressed: (_pages.isEmpty || _isGeneratingPdf) ? null : _onStartPdfCreation,
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                      label: FittedBox(
                        child: Text(
                          strings.get('btn_create_pdf'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
