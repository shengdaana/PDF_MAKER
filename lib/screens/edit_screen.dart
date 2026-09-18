import 'dart:io';
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
  // Pending stacked edits state
  late int _pendingRotation;
  late bool _pendingEnhanced;
  late bool _pendingFlattened;
  Rect _pendingNormalizedCrop = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);

  bool _isProcessing = true;
  img.Image? _normalizedSourceImage;
  Uint8List? _previewImageBytes;

  @override
  void initState() {
    super.initState();
    _pendingRotation = widget.pageItem.rotationDegrees;
    _pendingEnhanced = widget.pageItem.isEnhanced;
    _pendingFlattened = widget.pageItem.isFlattened;
    if (widget.pageItem.normalizedCropRect != null) {
      _pendingNormalizedCrop = widget.pageItem.normalizedCropRect!;
    }
    _loadAndNormalize();
  }

  Future<void> _loadAndNormalize() async {
    setState(() => _isProcessing = true);
    try {
      // 4c. EXIF normalization on photo load
      final file = File(widget.pageItem.sourcePath);
      final normalized = await ImageProcessingService.loadAndNormalizeExif(file);
      _normalizedSourceImage = normalized;
      await _renderLivePreview();
    } catch (e) {
      debugPrint("Error loading image for editing: $e");
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  Future<void> _renderLivePreview() async {
    if (_normalizedSourceImage == null) return;

    // Apply rotation
    img.Image working = ImageProcessingService.rotateByDegrees(
      _normalizedSourceImage!,
      _pendingRotation,
    );

    // Apply Enhance if pending
    if (_pendingEnhanced) {
      working = ImageProcessingService.applyDocumentEnhance(working);
    }

    // Apply Flatten if pending
    if (_pendingFlattened) {
      working = ImageProcessingService.applyFlatten(working);
    }

    // Downsample preview for fast UI rendering
    final previewBytes = Uint8List.fromList(img.encodeJpg(working, quality: 80));
    if (mounted) {
      setState(() {
        _previewImageBytes = previewBytes;
      });
    }
  }

  void _rotate90() {
    setState(() {
      _pendingRotation = (_pendingRotation + 90) % 360;
      // Reset crop to full on rotation to prevent aspect mismatch
      _pendingNormalizedCrop = const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);
    });
    _renderLivePreview();
  }

  void _toggleEnhance() {
    setState(() {
      _pendingEnhanced = !_pendingEnhanced;
    });
    _renderLivePreview();
  }

  void _toggleFlatten() {
    setState(() {
      _pendingFlattened = !_pendingFlattened;
    });
    _renderLivePreview();
  }

  Future<void> _confirmEdits() async {
    if (_normalizedSourceImage == null) {
      Navigator.pop(context);
      return;
    }

    setState(() => _isProcessing = true);

    try {
      // Apply pending edits sequentially and bake into new preview thumbnail
      img.Image result = ImageProcessingService.rotateByDegrees(
        _normalizedSourceImage!,
        _pendingRotation,
      );

      // Apply crop
      if (_pendingNormalizedCrop != const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0)) {
        result = ImageProcessingService.cropNormalized(result, _pendingNormalizedCrop);
      }

      // Apply enhance
      if (_pendingEnhanced) {
        result = ImageProcessingService.applyDocumentEnhance(result);
      }

      // Apply flatten
      if (_pendingFlattened) {
        result = ImageProcessingService.applyFlatten(result);
      }

      // Save to disk preview file
      final newPreviewPath = await ImageProcessingService.saveToTempPreviewFile(
        result,
        'page_${widget.pageItem.id}',
      );

      final updatedItem = widget.pageItem.cloneWith(
        currentPreviewPath: newPreviewPath,
        rotationDegrees: _pendingRotation,
        isEnhanced: _pendingEnhanced,
        isFlattened: _pendingFlattened,
        normalizedCropRect: _pendingNormalizedCrop,
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
        // Discard silently on back button
        leading: IconButton(
          icon: const Icon(Icons.close_rounded, size: 26),
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
              child: Container(
                color: Colors.black87,
                child: Center(
                  child: _isProcessing
                      ? const CircularProgressIndicator(color: Colors.white)
                      : (_previewImageBytes == null)
                          ? const Text('Could not load image', style: TextStyle(color: Colors.white))
                          : LayoutBuilder(
                              builder: (context, constraints) {
                                return Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Image.memory(
                                      _previewImageBytes!,
                                      fit: BoxFit.contain,
                                      width: constraints.maxWidth,
                                      height: constraints.maxHeight,
                                    ),
                                    CropOverlayWidget(
                                      normalizedRect: _pendingNormalizedCrop,
                                      displaySize: Size(constraints.maxWidth, constraints.maxHeight),
                                      onCropChanged: (newCrop) {
                                        setState(() {
                                          _pendingNormalizedCrop = newCrop;
                                        });
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                ),
              ),
            ),

            // Bottom Action Bar with Flexible constraints to prevent UI overflow (4g)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 12.0),
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
                  // 1. Rotate 90° button
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

                  // 2. Enhance button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pendingEnhanced ? primaryColor : theme.colorScheme.surface,
                        foregroundColor: _pendingEnhanced ? Colors.white : theme.colorScheme.onSurface,
                        side: BorderSide(color: primaryColor.withOpacity(0.5)),
                        elevation: _pendingEnhanced ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _toggleEnhance,
                      icon: Icon(
                        _pendingEnhanced ? Icons.auto_fix_high_rounded : Icons.auto_fix_normal_rounded,
                        size: 20,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          strings.get('btn_enhance'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // 3. Flatten button
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _pendingFlattened ? primaryColor : theme.colorScheme.surface,
                        foregroundColor: _pendingFlattened ? Colors.white : theme.colorScheme.onSurface,
                        side: BorderSide(color: primaryColor.withOpacity(0.5)),
                        elevation: _pendingFlattened ? 2 : 0,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                        minimumSize: const Size(0, 48),
                      ),
                      onPressed: _isProcessing ? null : _toggleFlatten,
                      icon: Icon(
                        _pendingFlattened ? Icons.crop_landscape_rounded : Icons.filter_center_focus_rounded,
                        size: 20,
                      ),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          strings.get('btn_flatten'),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
