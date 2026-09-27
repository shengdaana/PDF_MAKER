import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../main.dart';
import '../models/pdf_page_item.dart';
import '../utils/image_processor.dart';
import '../views/crop_overlay_widget.dart';

class EditScreen extends StatefulWidget {
  final PdfPageItem pageItem;

  const EditScreen({super.key, required this.pageItem});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late int _pendingRotation;
  late EnhanceMode _pendingEnhanceMode;
  CropQuad _pendingCropQuad = const CropQuad();

  bool _isProcessing = true;
  img.Image? _normalizedSourceImage;
  img.Image? _basePreviewImage;
  Uint8List? _previewImageBytes;
  int _previewWidth = 1;
  int _previewHeight = 1;
  int _previewVersion = 0;

  @override
  void initState() {
    super.initState();
    _pendingRotation = widget.pageItem.rotationDegrees;
    _pendingEnhanceMode = widget.pageItem.enhanceMode;

    if (widget.pageItem.cropQuad != null) {
      _pendingCropQuad = widget.pageItem.cropQuad!;
    } else if (widget.pageItem.normalizedCropRect != null) {
      final r = widget.pageItem.normalizedCropRect!;
      _pendingCropQuad = CropQuad(
        topLeft: Offset(r.left, r.top),
        topRight: Offset(r.right, r.top),
        bottomRight: Offset(r.right, r.bottom),
        bottomLeft: Offset(r.left, r.bottom),
      );
    } else {
      _pendingCropQuad = const CropQuad();
    }

    _loadAndNormalize();
  }

  Future<void> _loadAndNormalize() async {
    setState(() => _isProcessing = true);
    try {
      final file = File(widget.pageItem.sourcePath);
      final normalized = await ImageProcessor.loadAndNormalizeExif(file);
      _normalizedSourceImage = normalized;
      if (normalized != null) {
        // Cache a clean, downsampled base image for instantaneous, non-destructive live filter previews (FIX 2)
        _basePreviewImage = ImageProcessor.downsampleForPreview(normalized, maxDimension: 1000);
      }

      await _renderLivePreview();
    } catch (e) {
      debugPrint('Error loading image for editing: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Immediately re-renders the on-screen preview from a fresh clone of [_basePreviewImage]
  /// whenever rotation or Enhance filter mode changes (FIX 2).
  Future<void> _renderLivePreview() async {
    final img.Image? sourceForPreview = _basePreviewImage ?? _normalizedSourceImage;
    if (sourceForPreview == null) return;

    // Always start from a fresh clone so in-place image operations never corrupt the base image
    img.Image working = sourceForPreview.clone();

    // 1. Apply rotation
    if (_pendingRotation % 360 != 0) {
      working = ImageProcessor.rotateByDegrees(working, _pendingRotation);
    }

    // 2. Apply selected Enhance mode (Original Color / Grayscale / B&W High Contrast)
    if (_pendingEnhanceMode != EnhanceMode.none) {
      working = ImageProcessor.applyEnhanceMode(working, _pendingEnhanceMode);
    }

    final previewBytes = Uint8List.fromList(img.encodeJpg(working, quality: 85));
    if (mounted) {
      setState(() {
        _previewImageBytes = previewBytes;
        _previewWidth = working.width;
        _previewHeight = working.height;
        _previewVersion++;
      });
    }
  }

  void _rotate90() {
    setState(() {
      _pendingRotation = (_pendingRotation + 90) % 360;
      _pendingCropQuad = ImageProcessor.rotateQuad(_pendingCropQuad, 90);
    });
    _renderLivePreview();
  }

  void _resetCrop() {
    setState(() {
      _pendingCropQuad = CropQuad.full;
    });
  }

  void _selectEnhanceMode(EnhanceMode mode) {
    setState(() {
      _pendingEnhanceMode = mode;
    });
    _renderLivePreview();
  }

  void _showEnhanceModeSelector() {
    final strings = AppStateScope.of(context).strings;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  strings.get('enhance_sheet_title'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.palette_rounded, color: Colors.indigo),
                  title: Text(
                    strings.get('enhance_mode_color_title'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(strings.get('enhance_mode_color_desc')),
                  trailing: _pendingEnhanceMode == EnhanceMode.originalColor
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectEnhanceMode(EnhanceMode.originalColor);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tonality_rounded, color: Colors.blueGrey),
                  title: Text(
                    strings.get('enhance_mode_gray_title'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(strings.get('enhance_mode_gray_desc')),
                  trailing: _pendingEnhanceMode == EnhanceMode.grayscale
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectEnhanceMode(EnhanceMode.grayscale);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.contrast_rounded, color: Colors.black87),
                  title: Text(
                    strings.get('enhance_mode_bw_title'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(strings.get('enhance_mode_bw_desc')),
                  trailing: _pendingEnhanceMode == EnhanceMode.bwHighContrast
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectEnhanceMode(EnhanceMode.bwHighContrast);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded, color: Colors.grey),
                  title: Text(strings.get('enhance_mode_off_title')),
                  subtitle: Text(strings.get('enhance_mode_off_desc')),
                  trailing: _pendingEnhanceMode == EnhanceMode.none
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    _selectEnhanceMode(EnhanceMode.none);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmEdits() async {
    if (_normalizedSourceImage == null) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // FIX 1: Unconditionally apply perspective-rectification (`img.copyRectify`)
      // using the user's 4 corner points in `_pendingCropQuad`.
      final img.Image result = ImageProcessor.processPipeline(
        sourceImage: _normalizedSourceImage!,
        rotationDegrees: _pendingRotation,
        cropQuad: _pendingCropQuad,
        enhanceMode: _pendingEnhanceMode,
      );

      final newPreviewPath = await ImageProcessor.saveToTempPreviewFile(
        result,
        'page_${widget.pageItem.id}',
      );

      final updatedItem = widget.pageItem.cloneWith(
        currentPreviewPath: newPreviewPath,
        rotationDegrees: _pendingRotation,
        enhanceMode: _pendingEnhanceMode,
        cropQuad: _pendingCropQuad,
      );

      if (mounted) {
        Navigator.pop(context, updatedItem);
      }
    } catch (e) {
      debugPrint('Error confirming edits: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
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
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 26),
          tooltip: strings.get('btn_discard'),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(strings.get('btn_crop_rotate')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: strings.get('tooltip_reset_crop'),
            onPressed: _resetCrop,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: TextButton.icon(
              onPressed: _isProcessing ? null : _confirmEdits,
              icon: const Icon(Icons.check_rounded, size: 22),
              label: Text(
                strings.get('btn_confirm'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              style: TextButton.styleFrom(
                foregroundColor: primaryColor,
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Preview & Crop Canvas Area
            Expanded(
              child: Container(
                color: const Color(0xFF141414),
                child: Center(
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : (_previewImageBytes == null)
                          ? Text(
                              strings.get('msg_could_not_load_image'),
                              style: const TextStyle(color: Colors.white),
                            )
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                final double containerW = constraints.maxWidth;
                                final double containerH = constraints.maxHeight;

                                final double imgAspect = _previewWidth / _previewHeight;

                                // Provide 36dp margin so corner handles stay well inside viewport
                                const double margin = 36.0;
                                final double availW = max(50.0, containerW - margin * 2);
                                final double availH = max(50.0, containerH - margin * 2);

                                double dispW, dispH;
                                if (imgAspect > (availW / availH)) {
                                  dispW = availW;
                                  dispH = dispW / imgAspect;
                                } else {
                                  dispH = availH;
                                  dispW = dispH * imgAspect;
                                }

                                final double dispL = (containerW - dispW) / 2.0;
                                final double dispT = (containerH - dispH) / 2.0;
                                final imageRect = Rect.fromLTWH(dispL, dispT, dispW, dispH);

                                return Stack(
                                  children: [
                                    // 1. Live-updating Positioned Image (FIX 2)
                                    Positioned(
                                      left: dispL,
                                      top: dispT,
                                      width: dispW,
                                      height: dispH,
                                      child: Image.memory(
                                        _previewImageBytes!,
                                        key: ValueKey(
                                          'preview_${_pendingEnhanceMode.name}_${_pendingRotation}_$_previewVersion',
                                        ),
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true,
                                      ),
                                    ),

                                    // 2. Unclipped 4-corner perspective crop overlay with magnifying loupe
                                    Positioned.fill(
                                      child: CropOverlayWidget(
                                        cropQuad: _pendingCropQuad,
                                        imageDisplayRect: imageRect,
                                        previewImageBytes: _previewImageBytes,
                                        onQuadChanged: (newQuad) {
                                          _pendingCropQuad = newQuad;
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                ),
              ),
            ),

            // Instructions Hint Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.black,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.touch_app_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      strings.get('crop_hint_bar'),
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

            // Bottom Action Bar: Rotate 90° and Enhance Modes (FIX 1: Auto Deskew removed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
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
                  // 1. Rotate 90°
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _rotate90,
                      icon: const Icon(Icons.rotate_right_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          strings.get('btn_rotate_90'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // 2. Enhance Modes (Original Color / Grayscale / B&W High Contrast)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pendingEnhanceMode != EnhanceMode.none
                            ? primaryColor
                            : theme.colorScheme.surface,
                        foregroundColor: _pendingEnhanceMode != EnhanceMode.none
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                        side: BorderSide(color: primaryColor.withOpacity(0.5)),
                        elevation: _pendingEnhanceMode != EnhanceMode.none ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _showEnhanceModeSelector,
                      icon: Icon(
                        _pendingEnhanceMode != EnhanceMode.none
                            ? Icons.auto_fix_high_rounded
                            : Icons.auto_fix_normal_rounded,
                        size: 20,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _pendingEnhanceMode == EnhanceMode.none
                              ? strings.get('btn_enhance')
                              : _pendingEnhanceMode == EnhanceMode.originalColor
                                  ? strings.get('btn_enhance_color')
                                  : _pendingEnhanceMode == EnhanceMode.grayscale
                                      ? strings.get('btn_enhance_gray')
                                      : strings.get('btn_enhance_bw'),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
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
