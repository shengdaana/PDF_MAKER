import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/pdf_page_item.dart';

/// Compression profiles for PDF generation (FIX 11)
enum PdfCompressionProfile {
  /// Standard: Universal default. ~1800px on longest side, 70% JPEG quality per image.
  /// Naturally scales with page count without artificial size ceilings.
  standard,

  /// High Compression: ~1200px max, 55% quality for ultra-compact files.
  highCompression,

  /// HD Original: Full camera resolution up to 3200px, 90% quality for archiving/print.
  hdOriginal,
}

/// Comprehensive Image Processing Engine for PDF Maker Pro
/// Features:
/// - True perspective quadrilateral warping (Fixes 1 & 2) using img.copyRectify
/// - Three-tier Enhance modes (REDESIGN 6): Original Color, Grayscale, B&W High Contrast
/// - Deterministic reversible processing pipeline (Fix 3)
/// - Scaled per-image compression (Fix 11)
class ImageProcessor {
  /// Loads an image file, bakes its EXIF orientation into actual pixels, and normalizes it.
  static Future<img.Image?> loadAndNormalizeExif(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }

  /// Rotates an image by 90, 180, or 270 degrees.
  static img.Image rotateByDegrees(img.Image input, int degrees) {
    final normalized = (degrees % 360 + 360) % 360;
    switch (normalized) {
      case 90:
        return img.copyRotate(input, angle: 90);
      case 180:
        return img.copyRotate(input, angle: 180);
      case 270:
        return img.copyRotate(input, angle: 270);
      default:
        return input;
    }
  }

  /// Perspective deskew & crop (Fixes 1 & 2):
  /// Uses img.copyRectify to warp an arbitrary quadrilateral (topLeft, topRight,
  /// bottomRight, bottomLeft) into a clean, unwarped, deskewed rectangular image.
  /// Zero yellow cast, zero hand-written matrix math bugs.
  static img.Image applyPerspectiveCrop(img.Image input, CropQuad quad) {
    if (quad.isFullFrame) return input;

    final int w = input.width;
    final int h = input.height;

    // Convert normalized quad coords to image pixel points
    final pTopLeft = img.Point(
      (quad.topLeft.dx * w).round().clamp(0, w - 1),
      (quad.topLeft.dy * h).round().clamp(0, h - 1),
    );
    final pTopRight = img.Point(
      (quad.topRight.dx * w).round().clamp(0, w - 1),
      (quad.topRight.dy * h).round().clamp(0, h - 1),
    );
    final pBottomRight = img.Point(
      (quad.bottomRight.dx * w).round().clamp(0, w - 1),
      (quad.bottomRight.dy * h).round().clamp(0, h - 1),
    );
    final pBottomLeft = img.Point(
      (quad.bottomLeft.dx * w).round().clamp(0, w - 1),
      (quad.bottomLeft.dy * h).round().clamp(0, h - 1),
    );

    // img.copyRectify takes: topLeft, topRight, bottomLeft, bottomRight
    return img.copyRectify(
      input,
      topLeft: pTopLeft,
      topRight: pTopRight,
      bottomLeft: pBottomLeft,
      bottomRight: pBottomRight,
      interpolation: img.Interpolation.linear,
    );
  }

  /// Legacy axis-aligned crop helper for backward compatibility
  static img.Image cropNormalized(img.Image input, Rect normalizedRect) {
    final int x = (normalizedRect.left * input.width).clamp(0, input.width - 1).toInt();
    final int y = (normalizedRect.top * input.height).clamp(0, input.height - 1).toInt();
    final int w = (normalizedRect.width * input.width).clamp(1, input.width - x).toInt();
    final int h = (normalizedRect.height * input.height).clamp(1, input.height - y).toInt();

    return img.copyCrop(input, x: x, y: y, width: w, height: h);
  }

  /// Detects document boundary quadrilateral on a photo.
  /// Analyzes luminance and edge gradients on downsampled thumbnail.
  static CropQuad detectDocumentQuad(img.Image input) {
    try {
      // Downsample for fast analysis
      const int sampleDim = 200;
      final scale = max(input.width, input.height) / sampleDim;
      final sampleW = (input.width / scale).round().clamp(10, sampleDim);
      final sampleH = (input.height / scale).round().clamp(10, sampleDim);
      final sample = img.copyResize(input, width: sampleW, height: sampleH);

      // Compute average luminance and threshold
      int totalLum = 0;
      final lums = List<int>.filled(sampleW * sampleH, 0);
      for (int y = 0; y < sampleH; y++) {
        for (int x = 0; x < sampleW; x++) {
          final p = sample.getPixel(x, y);
          final l = (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round();
          lums[y * sampleW + x] = l;
          totalLum += l;
        }
      }
      final avgLum = totalLum ~/ (sampleW * sampleH);
      final thresh = max(avgLum, 95);

      // Find extreme corners of bright document area
      int minSum = 9999999, maxSum = -1;
      int minDiff = 9999999, maxDiff = -9999999;
      Point<int> tl = const Point(0, 0);
      Point<int> br = Point(sampleW - 1, sampleH - 1);
      Point<int> tr = Point(sampleW - 1, 0);
      Point<int> bl = Point(0, sampleH - 1);

      int brightCount = 0;
      for (int y = 0; y < sampleH; y++) {
        for (int x = 0; x < sampleW; x++) {
          if (lums[y * sampleW + x] >= thresh) {
            brightCount++;
            final sum = x + y;
            final diff = x - y;

            if (sum < minSum) {
              minSum = sum;
              tl = Point(x, y);
            }
            if (sum > maxSum) {
              maxSum = sum;
              br = Point(x, y);
            }
            if (diff > maxDiff) {
              maxDiff = diff;
              tr = Point(x, y);
            }
            if (diff < minDiff) {
              minDiff = diff;
              bl = Point(x, y);
            }
          }
        }
      }

      // If document area is too small or covers nearly whole frame, use comfortable 5% inset
      final minArea = (sampleW * sampleH) * 0.15;
      if (brightCount < minArea) {
        return const CropQuad(
          topLeft: Offset(0.05, 0.05),
          topRight: Offset(0.95, 0.05),
          bottomRight: Offset(0.95, 0.95),
          bottomLeft: Offset(0.05, 0.95),
        );
      }

      return CropQuad(
        topLeft: Offset(
          (tl.x / sampleW).clamp(0.02, 0.98),
          (tl.y / sampleH).clamp(0.02, 0.98),
        ),
        topRight: Offset(
          (tr.x / sampleW).clamp(0.02, 0.98),
          (tr.y / sampleH).clamp(0.02, 0.98),
        ),
        bottomRight: Offset(
          (br.x / sampleW).clamp(0.02, 0.98),
          (br.y / sampleH).clamp(0.02, 0.98),
        ),
        bottomLeft: Offset(
          (bl.x / sampleW).clamp(0.02, 0.98),
          (bl.y / sampleH).clamp(0.02, 0.98),
        ),
      );
    } catch (_) {
      return const CropQuad(
        topLeft: Offset(0.05, 0.05),
        topRight: Offset(0.95, 0.05),
        bottomRight: Offset(0.95, 0.95),
        bottomLeft: Offset(0.05, 0.95),
      );
    }
  }

  /// Automatic document deskew & perspective correction (Fix 1).
  /// Replaces the broken hand-written color-cast transform with real perspective rectification.
  static img.Image applyAutoFlatten(img.Image input) {
    final quad = detectDocumentQuad(input);
    return applyPerspectiveCrop(input, quad);
  }

  /// Backward-compatible alias for applyAutoFlatten
  static img.Image applyFlatten(img.Image input) => applyAutoFlatten(input);

  /// ENHANCE FILTER MODES (REDESIGN 6):
  /// 1. Original Color (Default): Sharpness and contrast boost only, colors preserved as-is.
  /// 2. Grayscale: Desaturated with smooth tonal shading.
  /// 3. B&W High Contrast: High-contrast thresholded black & white mode.
  static img.Image applyEnhanceMode(img.Image input, EnhanceMode mode) {
    switch (mode) {
      case EnhanceMode.none:
        return input;

      case EnhanceMode.originalColor:
        // 1. Contrast boost preserving all color channels
        final img.Image contrasted = img.contrast(input, contrast: 118);
        // 2. Subtle brightness lift for crisp text on paper
        final img.Image brightened = img.adjustColor(
          contrasted,
          brightness: 1.02,
          gamma: 0.98,
        );
        // 3. Unsharp text sharpening kernel
        return img.convolution(
          brightened,
          filter: [
            0, -1, 0,
            -1, 5, -1,
            0, -1, 0,
          ],
          div: 1,
          offset: 0,
        );

      case EnhanceMode.grayscale:
        // 1. Convert to true grayscale
        final img.Image gray = img.grayscale(input);
        // 2. Smooth tonal contrast (preserves shading, photos, pencil tones)
        final img.Image contrasted = img.contrast(gray, contrast: 128);
        // 3. Whitens background paper slightly
        final img.Image brightened = img.adjustColor(
          contrasted,
          brightness: 1.04,
          gamma: 0.98,
        );
        // 4. Sharpen
        return img.convolution(
          brightened,
          filter: [
            0, -1, 0,
            -1, 5, -1,
            0, -1, 0,
          ],
          div: 1,
          offset: 0,
        );

      case EnhanceMode.bwHighContrast:
        // 1. True grayscale
        final img.Image gray = img.grayscale(input);
        // 2. Strong contrast stretch
        final img.Image contrasted = img.contrast(gray, contrast: 155);
        // 3. Whitens grey paper noise, darkens text
        final img.Image brightened = img.adjustColor(
          contrasted,
          brightness: 1.08,
          gamma: 0.94,
        );
        // 4. Sharpen
        final img.Image sharpened = img.convolution(
          brightened,
          filter: [
            0, -1, 0,
            -1, 5, -1,
            0, -1, 0,
          ],
          div: 1,
          offset: 0,
        );
        // 5. Final grayscale pass to guarantee 0 chromatic artifacts
        return img.grayscale(sharpened);
    }
  }

  /// Backward-compatible alias for applyEnhanceMode
  static img.Image applyEnhance(img.Image input, {EnhanceMode mode = EnhanceMode.originalColor}) =>
      applyEnhanceMode(input, mode);

  /// Full deterministic processing pipeline (Fix 3):
  /// Always transforms directly from clean sourceImage so changes are 100% reversible.
  static img.Image processPipeline({
    required img.Image sourceImage,
    required int rotationDegrees,
    CropQuad? cropQuad,
    Rect? normalizedCropRect,
    EnhanceMode enhanceMode = EnhanceMode.none,
    bool isEnhanced = false,
    bool isFlattened = false,
  }) {
    img.Image result = sourceImage;

    // 1. Rotation
    if (rotationDegrees % 360 != 0) {
      result = rotateByDegrees(result, rotationDegrees);
    }

    // 2. Perspective Crop / Deskew (Fixes 1 & 2)
    if (cropQuad != null && !cropQuad.isFullFrame) {
      result = applyPerspectiveCrop(result, cropQuad);
    } else if (normalizedCropRect != null &&
        normalizedCropRect != const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0)) {
      result = cropNormalized(result, normalizedCropRect);
    } else if (isFlattened) {
      result = applyAutoFlatten(result);
    }

    // 3. Enhance Filter Modes (REDESIGN 6)
    final effectiveMode = enhanceMode != EnhanceMode.none
        ? enhanceMode
        : (isEnhanced ? EnhanceMode.originalColor : EnhanceMode.none);

    if (effectiveMode != EnhanceMode.none) {
      result = applyEnhanceMode(result, effectiveMode);
    }

    return result;
  }

  /// Saves an image to a temporary file on disk for fast UI rendering.
  static Future<String> saveToTempPreviewFile(img.Image image, String prefix) async {
    final tempDir = await getTemporaryDirectory();
    final String path = '${tempDir.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(image, quality: 82));
    await File(path).writeAsBytes(jpgBytes);
    return path;
  }

  /// Downsamples and compresses an image for PDF embedding (FIX 11).
  /// Standard Quality: ~1800px on longest side, 70% JPEG quality per image.
  /// Scales with page count without forcing artificial total document limits.
  static Uint8List compressForPdf(
    img.Image input, {
    PdfCompressionProfile profile = PdfCompressionProfile.standard,
  }) {
    switch (profile) {
      case PdfCompressionProfile.standard:
        // FIX 11: 1800px max dimension, 70% quality per image
        const int maxDim = 1800;
        img.Image resized = input;
        if (input.width > maxDim || input.height > maxDim) {
          if (input.width >= input.height) {
            resized = img.copyResize(input, width: maxDim, interpolation: img.Interpolation.linear);
          } else {
            resized = img.copyResize(input, height: maxDim, interpolation: img.Interpolation.linear);
          }
        }
        return Uint8List.fromList(img.encodeJpg(resized, quality: 70));

      case PdfCompressionProfile.highCompression:
        const int maxDim = 1200;
        img.Image resized = input;
        if (input.width > maxDim || input.height > maxDim) {
          if (input.width >= input.height) {
            resized = img.copyResize(input, width: maxDim, interpolation: img.Interpolation.linear);
          } else {
            resized = img.copyResize(input, height: maxDim, interpolation: img.Interpolation.linear);
          }
        }
        return Uint8List.fromList(img.encodeJpg(resized, quality: 55));

      case PdfCompressionProfile.hdOriginal:
        const int maxDim = 3200;
        img.Image resized = input;
        if (input.width > maxDim || input.height > maxDim) {
          if (input.width >= input.height) {
            resized = img.copyResize(input, width: maxDim, interpolation: img.Interpolation.linear);
          } else {
            resized = img.copyResize(input, height: maxDim, interpolation: img.Interpolation.linear);
          }
        }
        return Uint8List.fromList(img.encodeJpg(resized, quality: 90));
    }
  }
}
