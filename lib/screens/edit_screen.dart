import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
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
  CropQuad _pendingCropQuad = CropQuad.full;

  bool _isProcessing = true;
  Uint8List? _basePreviewBytes;
  Uint8List? _previewImageBytes;
  int _previewWidth = 1;
  int _previewHeight = 1;
  int _previewVersion = 0;

  @override
  void initState() {
    super.initState();
    _pendingRotation = widget.pageItem.rotationDegrees;

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
      // FIX 2: Default to full-frame [0.0 .. 1.0] so untouched pages are never cropped
      _pendingCropQuad = CropQuad.full;
    }

    _loadDownsampledPreview();
  }

  /// Loads a downsampled working preview off the main UI isolate (FIX 3).
  /// Reuses the existing downsampled thumbnail (`basePreviewPath`) when available so opening
  /// the Edit screen never decodes the full-resolution photo on the UI thread.
  Future<void> _loadDownsampledPreview() async {
    setState(() => _isProcessing = true);
    try {
      final PreviewRenderData? previewData = await ImageProcessor.loadEditPreviewInIsolate(
        sourcePath: widget.pageItem.sourcePath,
        basePreviewPath: widget.pageItem.basePreviewPath,
        rotationDegrees: _pendingRotation,
      );

      if (previewData != null && mounted) {
        setState(() {
          _basePreviewBytes = previewData.baseBytes;
          _previewImageBytes = previewData.displayBytes;
          _previewWidth = previewData.width;
          _previewHeight = previewData.height;
          _previewVersion++;
        });
      }
    } catch (e) {
      debugPrint('Error loading preview for editing: $e');
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _rotate90() async {
    final int nextRotation = (_pendingRotation + 90) % 360;
    final CropQuad rotatedQuad = ImageProcessor.rotateQuad(_pendingCropQuad, 90);

    setState(() {
      _pendingRotation = nextRotation;
      _pendingCropQuad = rotatedQuad;
    });

    if (_basePreviewBytes == null) return;

    final PreviewRenderData? rotated = await ImageProcessor.rotatePreviewInIsolate(
      baseBytes: _basePreviewBytes!,
      rotationDegrees: nextRotation,
    );

    if (rotated != null && mounted) {
      setState(() {
        _previewImageBytes = rotated.displayBytes;
        _previewWidth = rotated.width;
        _previewHeight = rotated.height;
        _previewVersion++;
      });
    }
  }

  void _resetCrop() {
    setState(() {
      _pendingCropQuad = CropQuad.full;
    });
  }

  Future<void> _confirmEdits() async {
    final bool hasCustomCrop = !_pendingCropQuad.isFullFrame;
    final bool hasRotation = (_pendingRotation % 360) != 0;

    // FIX 2: If the user left the 4 corners at default full-frame and rotation is unchanged at 0°,
    // return immediately without running perspective correction or re-encoding.
    if (!hasCustomCrop &&
        !hasRotation &&
        widget.pageItem.rotationDegrees == 0 &&
        !widget.pageItem.hasCustomCrop) {
      Navigator.pop(context, widget.pageItem);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final String newPreviewPath = await ImageProcessor.confirmEditsInIsolate(
        sourcePath: widget.pageItem.sourcePath,
        basePreviewPath: widget.pageItem.basePreviewPath,
        tempDirPath: tempDir.path,
        pageId: widget.pageItem.id,
        rotationDegrees: _pendingRotation,
        cropQuad: _pendingCropQuad,
      );

      final updatedItem = widget.pageItem.cloneWith(
        currentPreviewPath: newPreviewPath,
        rotationDegrees: _pendingRotation,
        cropQuad: hasCustomCrop ? _pendingCropQuad : null,
        clearCropQuad: !hasCustomCrop,
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
              child: ColoredBox(
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
                                    // 1. Downsampled Preview Image (with cacheWidth for low GPU memory)
                                    Positioned(
                                      left: dispL,
                                      top: dispT,
                                      width: dispW,
                                      height: dispH,
                                      child: Image.memory(
                                        _previewImageBytes!,
                                        key: ValueKey('preview_${_pendingRotation}_$_previewVersion'),
                                        fit: BoxFit.fill,
                                        gaplessPlayback: true,
                                        cacheWidth: 960,
                                        filterQuality: FilterQuality.low,
                                      ),
                                    ),

                                    // 2. 4-corner perspective crop overlay with magnifying loupe
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

            // Balanced Bottom Action Bar: Rotate 90° and Reset Crop
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
              decoration: BoxDecoration(
                color: theme.cardColor,
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 6,
                    offset: Offset(0, -2),
                  ),
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

                  // 2. Reset Crop to Full Frame
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _resetCrop,
                      icon: const Icon(Icons.crop_free_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          strings.get('btn_reset_crop'),
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
