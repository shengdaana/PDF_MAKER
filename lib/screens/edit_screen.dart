import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../main.dart';
import '../models/pdf_page_item.dart';
import '../utils/image_processing.dart';
import '../views/crop_overlay_widget.dart';

class EditScreen extends StatefulWidget {
  final PdfPageItem pageItem;

  const EditScreen({super.key, required this.pageItem});

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  // Pending stacked edits state (Fix 3: deterministic & completely reversible)
  late int _pendingRotation;
  late EnhanceMode _pendingEnhanceMode;
  late bool _pendingFlattened;
  CropQuad _pendingCropQuad = const CropQuad();

  bool _isProcessing = true;
  img.Image? _normalizedSourceImage;
  Uint8List? _previewImageBytes;
  int _previewWidth = 1;
  int _previewHeight = 1;

  @override
  void initState() {
    super.initState();
    _pendingRotation = widget.pageItem.rotationDegrees;
    _pendingEnhanceMode = widget.pageItem.enhanceMode;
    _pendingFlattened = widget.pageItem.isFlattened;

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
    }

    _loadAndNormalize();
  }

  Future<void> _loadAndNormalize() async {
    setState(() => _isProcessing = true);
    try {
      final file = File(widget.pageItem.sourcePath);
      final normalized = await ImageProcessor.loadAndNormalizeExif(file);
      _normalizedSourceImage = normalized;

      // If no custom crop was set yet, auto-detect document quad (Fix 1 & 2)
      if (widget.pageItem.cropQuad == null && normalized != null) {
        _pendingCropQuad = ImageProcessor.detectDocumentQuad(normalized);
      }

      await _renderLivePreview();
    } catch (e) {
      debugPrint("Error loading image for editing: $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  /// Always renders preview from the clean original normalizedSourceImage (Fix 3)
  Future<void> _renderLivePreview() async {
    if (_normalizedSourceImage == null) return;

    img.Image working = _normalizedSourceImage!;

    // 1. Apply rotation
    if (_pendingRotation % 360 != 0) {
      working = ImageProcessor.rotateByDegrees(working, _pendingRotation);
    }

    // 2. Apply Enhance mode (REDESIGN 6)
    if (_pendingEnhanceMode != EnhanceMode.none) {
      working = ImageProcessor.applyEnhanceMode(working, _pendingEnhanceMode);
    }

    // Downsample preview for snappy UI rendering
    const int maxDim = 1000;
    img.Image display = working;
    if (working.width > maxDim || working.height > maxDim) {
      if (working.width >= working.height) {
        display = img.copyResize(working, width: maxDim, interpolation: img.Interpolation.linear);
      } else {
        display = img.copyResize(working, height: maxDim, interpolation: img.Interpolation.linear);
      }
    }

    final previewBytes = Uint8List.fromList(img.encodeJpg(display, quality: 82));
    if (mounted) {
      setState(() {
        _previewImageBytes = previewBytes;
        _previewWidth = display.width;
        _previewHeight = display.height;
      });
    }
  }

  void _rotate90() {
    setState(() {
      _pendingRotation = (_pendingRotation + 90) % 360;
      // Reset crop quad to full frame on rotation to prevent aspect mismatch
      _pendingCropQuad = CropQuad.full;
    });
    _renderLivePreview();
  }

  void _autoDetectFlatten() {
    if (_normalizedSourceImage == null) return;
    setState(() {
      _pendingFlattened = true;
      _pendingCropQuad = ImageProcessor.detectDocumentQuad(_normalizedSourceImage!);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Document corners auto-detected'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _resetCrop() {
    setState(() {
      _pendingCropQuad = CropQuad.full;
      _pendingFlattened = false;
    });
  }

  void _showEnhanceModeSelector() {
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
                const Text(
                  'Enhance Filter Mode',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const Icon(Icons.palette_rounded, color: Colors.indigo),
                  title: const Text('Original Color (Default)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Boosts sharpness and contrast, preserves colors as-is'),
                  trailing: _pendingEnhanceMode == EnhanceMode.originalColor
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _pendingEnhanceMode = EnhanceMode.originalColor);
                    _renderLivePreview();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.tonality_rounded, color: Colors.blueGrey),
                  title: const Text('Grayscale', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Desaturated with smooth tonal shading (photos, signatures)'),
                  trailing: _pendingEnhanceMode == EnhanceMode.grayscale
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _pendingEnhanceMode = EnhanceMode.grayscale);
                    _renderLivePreview();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.contrast_rounded, color: Colors.black87),
                  title: const Text('B&W High Contrast', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Clean black & white scan mode for faded notes'),
                  trailing: _pendingEnhanceMode == EnhanceMode.bwHighContrast
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _pendingEnhanceMode = EnhanceMode.bwHighContrast);
                    _renderLivePreview();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.close_rounded, color: Colors.grey),
                  title: const Text('Filter Off'),
                  subtitle: const Text('Revert to unaltered camera image'),
                  trailing: _pendingEnhanceMode == EnhanceMode.none
                      ? const Icon(Icons.check_circle_rounded, color: Colors.indigo)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() => _pendingEnhanceMode = EnhanceMode.none);
                    _renderLivePreview();
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
      // FIX 2: When user confirms, automatically apply perspective-correction logic
      // to straighten the resulting crop using the user's 4 corner points
      img.Image result = ImageProcessor.processPipeline(
        sourceImage: _normalizedSourceImage!,
        rotationDegrees: _pendingRotation,
        cropQuad: _pendingCropQuad,
        enhanceMode: _pendingEnhanceMode,
        isFlattened: _pendingFlattened,
      );

      // Save to temporary preview file for fast UI rendering
      final newPreviewPath = await ImageProcessor.saveToTempPreviewFile(
        result,
        'page_${widget.pageItem.id}',
      );

      final updatedItem = widget.pageItem.cloneWith(
        currentPreviewPath: newPreviewPath,
        rotationDegrees: _pendingRotation,
        enhanceMode: _pendingEnhanceMode,
        isFlattened: _pendingFlattened || !_pendingCropQuad.isFullFrame,
        cropQuad: _pendingCropQuad,
      );

      if (mounted) {
        Navigator.pop(context, updatedItem);
      }
    } catch (e) {
      debugPrint("Error confirming edits: $e");
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
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(strings.get('btn_crop_rotate')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reset Crop to Full Frame',
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
                          ? const Text('Could not load image', style: TextStyle(color: Colors.white))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                // Fix 4: Calculate precise imageDisplayRect with generous padding
                                // so corner handles sitting at edges are NEVER clipped or cut off!
                                final double containerW = constraints.maxWidth;
                                final double containerH = constraints.maxHeight;

                                final double imgAspect = _previewWidth / _previewHeight;
                                final double containerAspect = containerW / containerH;

                                // Provide 36dp margin so handles (radius 16dp) stay well inside viewport
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
                                    // 1. Positioned Image
                                    Positioned(
                                      left: dispL,
                                      top: dispT,
                                      width: dispW,
                                      height: dispH,
                                      child: Image.memory(
                                        _previewImageBytes!,
                                        fit: BoxFit.fill,
                                      ),
                                    ),

                                    // 2. Unclipped 4-corner perspective crop overlay (Fixes 1, 2, 4)
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
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.touch_app_rounded, size: 16, color: Colors.white70),
                  SizedBox(width: 8),
                  Text(
                    'Drag 4 corners to straighten document automatically',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),

            // Bottom Action Bar with Flexible constraints
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _rotate90,
                      icon: const Icon(Icons.rotate_right_rounded, size: 20),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          strings.get('btn_rotate_90'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 2. Enhance Modes (REDESIGN 6)
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
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
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
                                  ? 'Color Enhanced'
                                  : _pendingEnhanceMode == EnhanceMode.grayscale
                                      ? 'Grayscale'
                                      : 'B&W Contrast',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Auto Deskew / Flatten (Fix 1)
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pendingFlattened
                            ? primaryColor
                            : theme.colorScheme.surface,
                        foregroundColor: _pendingFlattened
                            ? Colors.white
                            : theme.colorScheme.onSurface,
                        side: BorderSide(color: primaryColor.withOpacity(0.5)),
                        elevation: _pendingFlattened ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _autoDetectFlatten,
                      icon: const Icon(
                        Icons.filter_center_focus_rounded,
                        size: 20,
                      ),
                      label: const FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Auto Deskew',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
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
