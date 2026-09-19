import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import '../main.dart';
import '../models/app_settings.dart';
import '../models/pdf_page_item.dart';
import '../services/pdf_service.dart';
import '../utils/image_processor.dart';
import 'edit_screen.dart';
import 'success_screen.dart';

class ArrangePagesScreen extends StatefulWidget {
  final List<String> initialImagePaths;

  const ArrangePagesScreen({super.key, this.initialImagePaths = const []});

  @override
  State<ArrangePagesScreen> createState() => _ArrangePagesScreenState();
}

class _ArrangePagesScreenState extends State<ArrangePagesScreen> {
  final List<PdfPageItem> _pages = [];
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _flattenAll = false;
  bool _enhanceAll = false;
  bool _searchableOcr = false;
  bool _isLoading = true;
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
    final settings = AppStateScope.of(context).settings;
    _searchableOcr = settings.ocrDefault;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialPhotos() async {
    setState(() => _isLoading = true);
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
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addMorePhotos() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 100);
      if (picked.isNotEmpty) {
        final double savedScrollOffset =
            _scrollController.hasClients ? _scrollController.offset : 0.0;

        setState(() {
          for (int i = 0; i < picked.length; i++) {
            _pages.add(
              PdfPageItem(
                id: '${DateTime.now().millisecondsSinceEpoch}_add_$i',
                sourcePath: picked[i].path,
                currentPreviewPath: picked[i].path,
                isEnhanced: _enhanceAll,
                isFlattened: _flattenAll,
              ),
            );
          }
        });

        // Apply active bulk filters to newly added photos if needed
        if (_enhanceAll || _flattenAll) {
          _reprocessAllPreviews();
        }

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
    final double savedScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

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

  void _deletePage(int index) {
    final deletedItem = _pages[index];
    final originalIndex = index;

    setState(() {
      _pages.removeAt(index);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Page ${originalIndex + 1} deleted'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () {
            setState(() {
              _pages.insert(originalIndex, deletedItem);
            });
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<void> _rotatePage(int index) async {
    final page = _pages[index];
    final int newRotation = (page.rotationDegrees + 90) % 360;

    setState(() => _isLoading = true);
    try {
      final sourceFile = File(page.sourcePath);
      final raw = await ImageProcessor.loadAndNormalizeExif(sourceFile);
      if (raw != null) {
        final processed = ImageProcessor.processPipeline(
          sourceImage: raw,
          rotationDegrees: newRotation,
          cropQuad: page.cropQuad,
          normalizedCropRect: page.normalizedCropRect,
          enhanceMode: page.enhanceMode,
          isFlattened: page.isFlattened,
        );
        final newPreview = await ImageProcessor.saveToTempPreviewFile(
          processed,
          'rot_${page.id}',
        );
        page.rotationDegrees = newRotation;
        page.currentPreviewPath = newPreview;
      }
    } catch (e) {
      debugPrint("Error rotating page: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _toggleFlattenAll(bool enabled) async {
    setState(() {
      _flattenAll = enabled;
      for (final page in _pages) {
        page.isFlattened = enabled;
      }
    });
    await _reprocessAllPreviews();
  }

  Future<void> _toggleEnhanceAll(bool enabled) async {
    setState(() {
      _enhanceAll = enabled;
      for (final page in _pages) {
        page.enhanceMode = enabled ? EnhanceMode.originalColor : EnhanceMode.none;
      }
    });
    await _reprocessAllPreviews();
  }

  Future<void> _reprocessAllPreviews() async {
    final double savedScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    setState(() => _isLoading = true);

    try {
      for (final page in _pages) {
        if (page.enhanceMode == EnhanceMode.none &&
            !page.isFlattened &&
            page.rotationDegrees == 0 &&
            (page.cropQuad == null || page.cropQuad!.isFullFrame) &&
            page.normalizedCropRect == null) {
          page.currentPreviewPath = page.sourcePath;
          continue;
        }

        final file = File(page.sourcePath);
        final raw = await ImageProcessor.loadAndNormalizeExif(file);
        if (raw != null) {
          final processed = ImageProcessor.processPipeline(
            sourceImage: raw,
            rotationDegrees: page.rotationDegrees,
            cropQuad: page.cropQuad,
            normalizedCropRect: page.normalizedCropRect,
            enhanceMode: page.enhanceMode,
            isFlattened: page.isFlattened,
          );
          final preview = await ImageProcessor.saveToTempPreviewFile(
            processed,
            'prev_${page.id}',
          );
          page.currentPreviewPath = preview;
        }
      }
    } catch (e) {
      debugPrint("Error reprocessing previews: $e");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(savedScrollOffset);
          }
        });
      }
    }
  }

  Future<void> _openEditScreen(int index) async {
    final double savedScrollOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final page = _pages[index];

    final updatedPage = await Navigator.push<PdfPageItem>(
      context,
      MaterialPageRoute(
        builder: (context) => EditScreen(pageItem: page),
      ),
    );

    if (updatedPage != null && mounted) {
      setState(() {
        _pages[index] = updatedPage;
      });
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                    leading: const Icon(Icons.flash_on_rounded, color: Colors.green, size: 32),
                    title: Text(
                      strings.get('quality_standard'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
                    leading: const Icon(Icons.high_quality_rounded, color: Colors.indigo, size: 32),
                    title: Text(
                      strings.get('quality_hd'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
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
        compressionProfile: isHd ? PdfCompressionProfile.hdOriginal : PdfCompressionProfile.standard,
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
        title: Text('${strings.get('arrange_title')} (${_pages.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 26),
            tooltip: strings.get('btn_add_photos'),
            onPressed: _isGeneratingPdf ? null : _addMorePhotos,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Bulk Action Controls Card (Flatten All, Enhance All, OCR)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.filter_center_focus_rounded,
                                  size: 18, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.get('toggle_flatten_all'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _flattenAll,
                          onChanged: _isGeneratingPdf ? null : _toggleFlattenAll,
                          activeColor: primaryColor,
                        ),
                      ],
                    ),
                    const Divider(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.auto_fix_high_rounded,
                                  size: 18, color: primaryColor),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Enhance All (Clean B&W Scan)',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _enhanceAll,
                          onChanged: _isGeneratingPdf ? null : _toggleEnhanceAll,
                          activeColor: primaryColor,
                        ),
                      ],
                    ),
                    const Divider(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.document_scanner_rounded,
                                  size: 18, color: primaryColor),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  strings.get('toggle_ocr'),
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _searchableOcr,
                          onChanged: _isGeneratingPdf
                              ? null
                              : (val) => setState(() => _searchableOcr = val),
                          activeColor: primaryColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Large Document Notice (>100 pages)
            if (_pages.length > 100)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.get('soft_warning_msg'),
                        style: TextStyle(color: Colors.amber.shade900, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // Progress Banner During Generation
            if (_isGeneratingPdf)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: _generationProgress),
                        const SizedBox(height: 10),
                        Text(_generationStatus,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                  ),
                ),
              ),

            // Overhauled Hero Cards Page List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _pages.isEmpty
                      ? Center(child: Text(strings.get('no_pdfs_yet')))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                          itemCount: _pages.length,
                          itemBuilder: (context, index) {
                            final page = _pages[index];
                            final isFirst = index == 0;
                            final isLast = index == _pages.length - 1;

                            final cardContent = Card(
                              key: ValueKey(page.id),
                              margin: const EdgeInsets.symmetric(vertical: 10.0),
                              clipBehavior: Clip.antiAlias,
                              elevation: 3,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: InkWell(
                                onTap: () => _openEditScreen(index),
                                child: Stack(
                                  children: [
                                    // 1. Edge-to-Edge Photo as Card Background (Hero Style)
                                    SizedBox(
                                      width: double.infinity,
                                      height: 300,
                                      child: Image.file(
                                        File(page.currentPreviewPath),
                                        fit: BoxFit.cover,
                                        width: double.infinity,
                                        height: 300,
                                        key: ValueKey(page.currentPreviewPath),
                                        errorBuilder: (_, __, ___) => const Center(
                                          child: Icon(Icons.broken_image_rounded, size: 48, color: Colors.grey),
                                        ),
                                      ),
                                    ),

                                    // 2. Top-Left: Floating Page Badge
                                    Positioned(
                                      top: 12,
                                      left: 12,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: const Color(0xAA000000),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          '${strings.get('page_badge')} ${index + 1} of ${_pages.length}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 3. Top-Right: Floating Delete Page Button
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: Material(
                                        color: const Color(0xAA000000),
                                        shape: const CircleBorder(),
                                        child: InkWell(
                                          customBorder: const CircleBorder(),
                                          onTap: () => _deletePage(index),
                                          child: const Padding(
                                            padding: EdgeInsets.all(8.0),
                                            child: Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // 4. Right Side: Semi-Transparent Reorder Arrows Overlay (REDESIGN 5)
                                    if (!settings.hideReorderArrows)
                                      Positioned(
                                        right: 8,
                                        top: 90,
                                        bottom: 60,
                                        child: Center(
                                          child: Container(
                                            decoration: BoxDecoration(
                                              color: const Color(0xAA000000),
                                              borderRadius: BorderRadius.circular(24),
                                            ),
                                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: const Icon(Icons.arrow_upward_rounded, size: 22, color: Colors.white),
                                                  tooltip: 'Move page up',
                                                  onPressed: isFirst ? null : () => _movePage(index, index - 1),
                                                ),
                                                const SizedBox(height: 4),
                                                IconButton(
                                                  icon: const Icon(Icons.arrow_downward_rounded, size: 22, color: Colors.white),
                                                  tooltip: 'Move page down',
                                                  onPressed: isLast ? null : () => _movePage(index, index + 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),

                                    // 5. Bottom Overlay: "Tap to edit" bar (REDESIGN 5)
                                    Positioned(
                                      bottom: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                                        color: const Color(0xB3000000),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.edit_rounded, size: 16, color: Colors.white),
                                            SizedBox(width: 8),
                                            Text(
                                              'Tap to edit',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );

                            if (settings.premiumAnimations) {
                              return AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                opacity: 1.0,
                                child: cardContent,
                              );
                            }
                            return cardContent;
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
