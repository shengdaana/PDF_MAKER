import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import '../main.dart';
import '../models/app_settings.dart';
import '../models/pdf_page_item.dart';
import '../services/pdf_service.dart';
import '../utils/image_processor.dart';
import 'edit_screen.dart';

class PdfEditorScreen extends StatefulWidget {
  final File pdfFile;

  const PdfEditorScreen({super.key, required this.pdfFile});

  @override
  State<PdfEditorScreen> createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  final List<PdfPageItem> _pages = [];
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _picker = ImagePicker();

  bool _isLoading = true;
  String _loadingMessage = '';
  bool _isSaving = false;
  double _savingProgress = 0.0;
  String _savingStatus = '';

  late PdfPageSizing _pageSizing;
  bool _enableOcr = false;
  bool _initializedDeps = false;

  @override
  void initState() {
    super.initState();
    _loadPdfPages();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedDeps) {
      final settings = AppStateScope.of(context).settings;
      _pageSizing = settings.pageSizing;
      _enableOcr = settings.ocrDefault;
      _loadingMessage = AppStateScope.of(context).strings.get('status_rasterizing_pdf');
      _initializedDeps = true;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadPdfPages() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final Uint8List pdfBytes = await widget.pdfFile.readAsBytes();
      final tempDir = await getTemporaryDirectory();
      int pageIndex = 0;

      await for (final page in Printing.raster(pdfBytes, dpi: 150)) {
        final Uint8List pngBytes = await page.toPng();
        final String imagePath =
            '${tempDir.path}/raster_${DateTime.now().microsecondsSinceEpoch}_$pageIndex.png';
        final File imgFile = File(imagePath);
        await imgFile.writeAsBytes(pngBytes);

        _pages.add(
          PdfPageItem(
            id: 'page_${DateTime.now().millisecondsSinceEpoch}_$pageIndex',
            sourcePath: imagePath,
            basePreviewPath: imagePath,
            currentPreviewPath: imagePath,
          ),
        );
        pageIndex++;
        if (mounted) {
          final strings = AppStateScope.of(context).strings;
          setState(() {
            _loadingMessage = strings.extractedPages(pageIndex);
          });
        }
      }
    } catch (e) {
      debugPrint('Error rasterizing PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
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
      final List<PdfPageItem> added = [];

      for (int i = 0; i < picked.length; i++) {
        final String path = picked[i].path;
        final String id = 'added_${nowMs}_$i';
        final String thumbPath = await ImageProcessor.generateDownsampledThumbnail(
          sourcePath: path,
          tempDirPath: tempDirPath,
          pageId: id,
          maxDimension: 960,
        );
        added.add(
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
          _pages.addAll(added);
          _isLoading = false;
        });

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(savedScrollOffset);
          }
        });
      }
    } catch (e) {
      debugPrint('Error picking additional images: $e');
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
    if (_pages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.get('msg_cannot_delete_only_page'))),
      );
      return;
    }

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

  Future<void> _rotatePage(int index) async {
    final page = _pages[index];
    final int newRotation = (page.rotationDegrees + 90) % 360;
    final CropQuad rotatedQuad = page.cropQuad != null
        ? ImageProcessor.rotateQuad(page.cropQuad!, 90)
        : CropQuad.full;

    setState(() => _isLoading = true);
    try {
      final tempDir = await getTemporaryDirectory();
      final String newPreview = await ImageProcessor.confirmEditsInIsolate(
        sourcePath: page.sourcePath,
        basePreviewPath: page.basePreviewPath,
        tempDirPath: tempDir.path,
        pageId: page.id,
        rotationDegrees: newRotation,
        cropQuad: rotatedQuad,
      );

      page.rotationDegrees = newRotation;
      page.cropQuad = rotatedQuad.isFullFrame ? null : rotatedQuad;
      page.currentPreviewPath = newPreview;
    } catch (e) {
      debugPrint('Error rotating page: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _openEditPage(int index) async {
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

  Future<void> _saveEditedPdf({required bool saveAsNewCopy}) async {
    if (_pages.isEmpty) return;
    final strings = AppStateScope.of(context).strings;

    setState(() {
      _isSaving = true;
      _savingProgress = 0.0;
      _savingStatus = strings.get('status_preparing_pages');
    });

    try {
      final appSettings = AppStateScope.of(context).settings;
      final effectiveSettings = AppSettings(
        themePalette: appSettings.themePalette,
        language: appSettings.language,
        pageSizing: _pageSizing,
        qualityPreset: appSettings.qualityPreset,
        isDarkMode: appSettings.isDarkMode,
        ocrDefault: _enableOcr,
        hideReorderArrows: appSettings.hideReorderArrows,
        mergePagesBetweenPages: appSettings.mergePagesBetweenPages,
        saveFolder: appSettings.saveFolder,
      );

      final result = await PdfService.generatePdf(
        pages: _pages,
        settings: effectiveSettings,
        enableOcr: _enableOcr,
        compressionProfile: PdfCompressionProfile.standard,
        onProgress: (progress, status) {
          if (mounted) {
            setState(() {
              _savingProgress = progress;
              _savingStatus = status;
            });
          }
        },
      );

      if (!saveAsNewCopy) {
        await result.file.copy(widget.pdfFile.path);
        try {
          if (result.file.path != widget.pdfFile.path) {
            await result.file.delete();
          }
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(saveAsNewCopy
                ? '${strings.get('msg_saved_new_copy')} ${result.fileName}'
                : '${strings.get('msg_changes_saved_to')} ${widget.pdfFile.uri.pathSegments.last}'),
          ),
        );
        Navigator.pop(context, saveAsNewCopy ? result.file : widget.pdfFile);
      }
    } catch (e) {
      debugPrint('Error saving edited PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${strings.get('msg_pdf_gen_failed')}: $e')),
        );
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final appScope = AppStateScope.of(context);
    final strings = appScope.strings;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('${strings.get('pdf_editor_title')} (${_pages.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_photo_alternate_rounded, size: 26),
            tooltip: strings.get('btn_add_photos'),
            onPressed: (_isLoading || _isSaving) ? null : _addMorePhotos,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Editor Toolbar Card
            Card(
              margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
              elevation: 1,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.aspect_ratio_rounded, color: primaryColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.get('sizing_title'),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        SegmentedButton<PdfPageSizing>(
                          segments: [
                            ButtonSegment(
                              value: PdfPageSizing.a4Standard,
                              label: Text(
                                strings.get('sizing_a4_short'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              icon: const Icon(Icons.description_outlined, size: 16),
                            ),
                            ButtonSegment(
                              value: PdfPageSizing.freeDynamic,
                              label: Text(
                                strings.get('sizing_orig_short'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              icon: const Icon(Icons.fit_screen_outlined, size: 16),
                            ),
                          ],
                          selected: {_pageSizing},
                          onSelectionChanged: (Set<PdfPageSizing> newSelection) {
                            setState(() {
                              _pageSizing = newSelection.first;
                            });
                          },
                        ),
                      ],
                    ),
                    const Divider(height: 12),
                    Row(
                      children: [
                        Icon(
                          Icons.document_scanner_rounded,
                          size: 18,
                          color: _enableOcr ? primaryColor : Colors.grey,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            strings.get('toggle_ocr'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _enableOcr ? FontWeight.bold : FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Switch(
                          value: _enableOcr,
                          onChanged: (v) => setState(() => _enableOcr = v),
                          activeColor: primaryColor,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            if (_isSaving)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        LinearProgressIndicator(value: _savingProgress),
                        const SizedBox(height: 8),
                        Text(_savingStatus, style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),

            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(_loadingMessage, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                    )
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

                            return RepaintBoundary(
                              child: Card(
                                key: ValueKey(page.id),
                                margin: const EdgeInsets.symmetric(vertical: 8.0),
                                clipBehavior: Clip.antiAlias,
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(
                                    color: theme.colorScheme.outline.withOpacity(0.15),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    GestureDetector(
                                      onTap: () => _openEditPage(index),
                                      child: Stack(
                                        children: [
                                          Container(
                                            width: double.infinity,
                                            height: 230,
                                            color: Colors.black.withOpacity(0.04),
                                            child: Center(
                                              child: Image.file(
                                                File(page.currentPreviewPath),
                                                fit: BoxFit.contain,
                                                width: double.infinity,
                                                height: 230,
                                                cacheWidth: 800,
                                                filterQuality: FilterQuality.low,
                                                gaplessPlayback: true,
                                                key: ValueKey(page.currentPreviewPath),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 10,
                                            left: 10,
                                            child: DecoratedBox(
                                              decoration: const BoxDecoration(
                                                color: Color(0xB8000000),
                                                borderRadius: BorderRadius.all(Radius.circular(12)),
                                              ),
                                              child: Padding(
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 5,
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
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 4.0,
                                      ),
                                      color: theme.cardColor,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 4,
                                              ),
                                              minimumSize: Size.zero,
                                            ),
                                            onPressed: () => _openEditPage(index),
                                            icon: const Icon(Icons.crop_rotate_rounded, size: 18),
                                            label: Text(strings.get('edit_crop_btn')),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.rotate_right_rounded, size: 20),
                                            tooltip: strings.get('btn_rotate_90'),
                                            onPressed: () => _rotatePage(index),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
                                            tooltip: strings.get('tooltip_move_up'),
                                            onPressed: isFirst
                                                ? null
                                                : () => _movePage(index, index - 1),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                                            tooltip: strings.get('tooltip_move_down'),
                                            onPressed: isLast
                                                ? null
                                                : () => _movePage(index, index + 1),
                                          ),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 20,
                                              color: Colors.redAccent,
                                            ),
                                            tooltip: strings.get('tooltip_delete_page'),
                                            onPressed: () => _deletePage(index),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),

            Container(
              padding: const EdgeInsets.all(14.0),
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
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: (_isSaving || _isLoading || _pages.isEmpty)
                          ? null
                          : () => _saveEditedPdf(saveAsNewCopy: true),
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: FittedBox(
                        child: Text(
                          strings.get('save_as_copy'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: (_isSaving || _isLoading || _pages.isEmpty)
                          ? null
                          : () => _saveEditedPdf(saveAsNewCopy: false),
                      icon: const Icon(Icons.save_rounded, size: 20),
                      label: FittedBox(
                        child: Text(
                          strings.get('save_changes'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
