import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
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

  bool _searchableOcr = false;
  bool _initializedDeps = false;
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
    if (!_initializedDeps) {
      final settings = AppStateScope.of(context).settings;
      _searchableOcr = settings.ocrDefault;
      _initializedDeps = true;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Generates downsampled thumbnails in a background isolate once per photo (FIX 3)
  /// so list cards and EditScreen previews never decode full camera-resolution photos on the UI thread.
  Future<void> _loadInitialPhotos() async {
    setState(() => _isLoading = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final String tempDirPath = tempDir.path;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;

      for (int i = 0; i < widget.initialImagePaths.length; i++) {
        final String path = widget.initialImagePaths[i];
        final String id = '${nowMs}_$i';
        final String thumbPath = await ImageProcessor.generateDownsampledThumbnail(
          sourcePath: path,
          tempDirPath: tempDirPath,
          pageId: id,
          maxDimension: 960,
        );

        _pages.add(
          PdfPageItem(
            id: id,
            sourcePath: path,
            basePreviewPath: thumbPath,
            currentPreviewPath: thumbPath,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading initial photos: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addMorePhotos() async {
    try {
      final picked = await _picker.pickMultiImage(imageQuality: 100);
      if (picked.isEmpty) return;

      final double savedScrollOffset =
          _scrollController.hasClients ? _scrollController.offset : 0.0;

      setState(() => _isLoading = true);

      final tempDir = await getTemporaryDirectory();
      final String tempDirPath = tempDir.path;
      final int nowMs = DateTime.now().millisecondsSinceEpoch;
      final List<PdfPageItem> newItems = [];

      for (int i = 0; i < picked.length; i++) {
        final String path = picked[i].path;
        final String id = '${nowMs}_add_$i';
        final String thumbPath = await ImageProcessor.generateDownsampledThumbnail(
          sourcePath: path,
          tempDirPath: tempDirPath,
          pageId: id,
          maxDimension: 960,
        );
        newItems.add(
          PdfPageItem(
            id: id,
            sourcePath: path,
            basePreviewPath: thumbPath,
            currentPreviewPath: thumbPath,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _pages.addAll(newItems);
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(savedScrollOffset);
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking additional photos: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
    final strings = AppStateScope.of(context).strings;
    final deletedItem = _pages[index];
    final originalIndex = index;

    setState(() {
      _pages.removeAt(index);
    });

    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.pageDeleted(originalIndex + 1)),
        action: SnackBarAction(
          label: strings.get('btn_undo'),
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
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final settings = appScope.settings;

    setState(() {
      _isGeneratingPdf = true;
      _generationProgress = 0.0;
      _generationStatus = strings.get('status_preparing_pages');
    });

    try {
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
      debugPrint('PDF Generation Failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.get('msg_pdf_gen_failed')}: $e')),
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
            onPressed: (_isGeneratingPdf || _isLoading) ? null : _addMorePhotos,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Controls Card (OCR Search Toggle)
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                child: Row(
                  children: [
                    Icon(Icons.document_scanner_rounded, size: 18, color: primaryColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        strings.get('toggle_ocr'),
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
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
                        Text(
                          _generationStatus,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Hero Cards Page List (with downsampled thumbnails & cacheWidth for 60fps scroll - FIX 3)
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _pages.isEmpty
                      ? Center(child: Text(strings.get('no_pdfs_yet'), textAlign: TextAlign.center))
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 8.0),
                          itemCount: _pages.length,
                          itemBuilder: (context, index) {
                            final page = _pages[index];
                            final isFirst = index == 0;
                            final isLast = index == _pages.length - 1;

                            final cardContent = RepaintBoundary(
                              child: Card(
                                key: ValueKey(page.id),
                                margin: const EdgeInsets.symmetric(vertical: 10.0),
                                clipBehavior: Clip.antiAlias,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: InkWell(
                                  onTap: () => _openEditScreen(index),
                                  child: Stack(
                                    children: [
                                      // 1. Downsampled Photo Card Background with cacheWidth
                                      SizedBox(
                                        width: double.infinity,
                                        height: 300,
                                        child: Image.file(
                                          File(page.currentPreviewPath),
                                          fit: BoxFit.cover,
                                          width: double.infinity,
                                          height: 300,
                                          cacheWidth: 800,
                                          filterQuality: FilterQuality.low,
                                          gaplessPlayback: true,
                                          key: ValueKey(page.currentPreviewPath),
                                          errorBuilder: (_, __, ___) => const Center(
                                            child: Icon(
                                              Icons.broken_image_rounded,
                                              size: 48,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 2. Top-Left: Floating Page Badge
                                      Positioned(
                                        top: 12,
                                        left: 12,
                                        child: DecoratedBox(
                                          decoration: const BoxDecoration(
                                            color: Color(0xAA000000),
                                            borderRadius: BorderRadius.all(Radius.circular(12)),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            child: Text(
                                              strings.pageOf(index + 1, _pages.length),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12,
                                              ),
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
                                            child: Padding(
                                              padding: const EdgeInsets.all(8.0),
                                              child: Tooltip(
                                                message: strings.get('tooltip_delete_page'),
                                                child: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  size: 20,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 4. Right Side: Semi-Transparent Reorder Arrows Overlay
                                      if (!settings.hideReorderArrows)
                                        Positioned(
                                          right: 8,
                                          top: 90,
                                          bottom: 60,
                                          child: Center(
                                            child: DecoratedBox(
                                              decoration: const BoxDecoration(
                                                color: Color(0xAA000000),
                                                borderRadius: BorderRadius.all(Radius.circular(24)),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(
                                                  vertical: 4,
                                                  horizontal: 2,
                                                ),
                                                child: Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.arrow_upward_rounded,
                                                        size: 22,
                                                        color: Colors.white,
                                                      ),
                                                      tooltip: strings.get('tooltip_move_up'),
                                                      onPressed: isFirst
                                                          ? null
                                                          : () => _movePage(index, index - 1),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    IconButton(
                                                      icon: const Icon(
                                                        Icons.arrow_downward_rounded,
                                                        size: 22,
                                                        color: Colors.white,
                                                      ),
                                                      tooltip: strings.get('tooltip_move_down'),
                                                      onPressed: isLast
                                                          ? null
                                                          : () => _movePage(index, index + 1),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),

                                      // 5. Bottom Overlay: "Tap to crop or rotate" bar
                                      Positioned(
                                        bottom: 0,
                                        left: 0,
                                        right: 0,
                                        child: ColoredBox(
                                          color: const Color(0xB3000000),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 8,
                                              horizontal: 16,
                                            ),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Icon(
                                                  Icons.crop_rotate_rounded,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  strings.get('tap_to_edit'),
                                                  style: const TextStyle(
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
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );

                            return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                cardContent,
                                if (settings.mergePagesBetweenPages && !isLast)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 4.0),
                                    child: ActionChip(
                                      avatar: Icon(
                                        page.mergedWithNext
                                            ? Icons.merge_type_rounded
                                            : Icons.vertical_align_center_rounded,
                                        size: 16,
                                        color: page.mergedWithNext ? Colors.white : primaryColor,
                                      ),
                                      backgroundColor:
                                          page.mergedWithNext ? primaryColor : theme.cardColor,
                                      label: Text(
                                        strings.get('merge_next'),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: page.mergedWithNext
                                              ? Colors.white
                                              : theme.colorScheme.onSurface,
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          page.mergedWithNext = !page.mergedWithNext;
                                        });
                                      },
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
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, -2),
                  )
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: (_isGeneratingPdf || _isLoading) ? null : _addMorePhotos,
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
                      onPressed:
                          (_pages.isEmpty || _isGeneratingPdf || _isLoading) ? null : _onStartPdfCreation,
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
