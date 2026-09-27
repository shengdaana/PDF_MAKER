import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/pdf_page_item.dart';

/// Compression profiles for PDF generation
enum PdfCompressionProfile {
  /// Standard: Universal default. ~1800px on longest side, 70% JPEG quality per image.
  /// Naturally scales with page count without artificial size ceilings.
  standard,

  /// High Compression: ~1200px max, 55% quality for ultra-compact files.
  highCompression,

  /// HD Original: Full camera resolution up to 3200px, 90% quality for archiving/print.
  hdOriginal,
}

/// Comprehensive Image Processing Engine for PDF Maker
/// Features:
/// - Unconditional perspective rectification (`img.copyRectify`) on manual 4-corner crop confirm (FIX 1)
/// - Non-destructive, live-updating three-tier Enhance modes (FIX 2): Original Color, Grayscale, B&W High Contrast
/// - Deterministic reversible processing pipeline
/// - Scaled per-image compression
class ImageProcessor {
  /// Rotates a normalized CropQuad clockwise by [degrees] (0, 90, 180, 270).
  static CropQuad rotateQuad(CropQuad quad, int degrees) {
    final int steps = ((degrees % 360 + 360) % 360) ~/ 90;
    CropQuad current = quad;
    for (int i = 0; i < steps; i++) {
      Offset rot90CW(Offset p) => Offset((1.0 - p.dy).clamp(0.0, 1.0), p.dx.clamp(0.0, 1.0));
      current = CropQuad(
        topLeft: rot90CW(current.bottomLeft),
        topRight: rot90CW(current.topLeft),
        bottomRight: rot90CW(current.topRight),
        bottomLeft: rot90CW(current.bottomRight),
      );
    }
    return current;
  }

  /// Loads an image file, bakes its EXIF orientation into actual pixels, and normalizes it.
  static Future<img.Image?> loadAndNormalizeExif(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }

  /// Rotates an image by 90, 180, or 270 degrees (returns a new Image).
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
        return input.clone();
    }
  }

  /// Perspective deskew & crop (FIX 1):
  /// Unconditionally warps and straightens the 4-corner quadrilateral placed by the user
  /// using `img.copyRectify` while computing the true physical Euclidean edge lengths so the
  /// resulting page preserves the exact aspect ratio of the cropped document.
  static img.Image applyPerspectiveCrop(img.Image input, CropQuad quad) {
    final int w = input.width;
    final int h = input.height;
    if (w <= 2 || h <= 2) return input.clone();

    final double tlX = (quad.topLeft.dx * w).clamp(0.0, (w - 1).toDouble());
    final double tlY = (quad.topLeft.dy * h).clamp(0.0, (h - 1).toDouble());
    final double trX = (quad.topRight.dx * w).clamp(0.0, (w - 1).toDouble());
    final double trY = (quad.topRight.dy * h).clamp(0.0, (h - 1).toDouble());
    final double brX = (quad.bottomRight.dx * w).clamp(0.0, (w - 1).toDouble());
    final double brY = (quad.bottomRight.dy * h).clamp(0.0, (h - 1).toDouble());
    final double blX = (quad.bottomLeft.dx * w).clamp(0.0, (w - 1).toDouble());
    final double blY = (quad.bottomLeft.dy * h).clamp(0.0, (h - 1).toDouble());

    // Compute true Euclidean edge lengths for aspect-correct output dimensions
    final double topEdge = sqrt(pow(trX - tlX, 2) + pow(trY - tlY, 2));
    final double bottomEdge = sqrt(pow(brX - blX, 2) + pow(brY - blY, 2));
    final double leftEdge = sqrt(pow(blX - tlX, 2) + pow(blY - tlY, 2));
    final double rightEdge = sqrt(pow(brX - trX, 2) + pow(brY - trY, 2));

    final int outWidth = max(topEdge, bottomEdge).round().clamp(16, w);
    final int outHeight = max(leftEdge, rightEdge).round().clamp(16, h);

    final pTopLeft = img.Point(tlX.round(), tlY.round());
    final pTopRight = img.Point(trX.round(), trY.round());
    final pBottomRight = img.Point(brX.round(), brY.round());
    final pBottomLeft = img.Point(blX.round(), blY.round());

    final img.Image targetImage = img.Image(width: outWidth, height: outHeight);

    // img.copyRectify straightens the 4-corner quadrilateral into targetImage
    return img.copyRectify(
      input,
      topLeft: pTopLeft,
      topRight: pTopRight,
      bottomLeft: pBottomLeft,
      bottomRight: pBottomRight,
      interpolation: img.Interpolation.linear,
      toImage: targetImage,
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

  /// ENHANCE FILTER MODES (FIX 2):
  /// Always clones [input] before applying `package:image` filters because `img.grayscale`,
  /// `img.contrast`, `img.adjustColor`, and `img.convolution` mutate pixel buffers in-place.
  /// Cloning guarantees non-destructive live preview updates when switching between modes!
  static img.Image applyEnhanceMode(img.Image input, EnhanceMode mode) {
    if (mode == EnhanceMode.none) {
      return input.clone();
    }

    // Clone input so we NEVER mutate cached source/preview images in-place
    final img.Image working = input.clone();

    switch (mode) {
      case EnhanceMode.none:
        return working;

      case EnhanceMode.originalColor:
        // 1. Contrast boost preserving all color channels
        final img.Image contrasted = img.contrast(working, contrast: 118);
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
        final img.Image gray = img.grayscale(working);
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
        final img.Image gray = img.grayscale(working);
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

  /// Downsamples an image to [maxDimension] on its longest side for fast interactive UI previews.
  static img.Image downsampleForPreview(img.Image input, {int maxDimension = 1000}) {
    if (input.width <= maxDimension && input.height <= maxDimension) {
      return input.clone();
    }
    if (input.width >= input.height) {
      return img.copyResize(input, width: maxDimension, interpolation: img.Interpolation.linear);
    } else {
      return img.copyResize(input, height: maxDimension, interpolation: img.Interpolation.linear);
    }
  }

  /// Full deterministic processing pipeline (FIX 1 & FIX 2):
  /// Always transforms directly from clean sourceImage so changes are 100% reversible.
  /// Whenever [cropQuad] is provided (confirmed in the crop tool), perspective-rectification
  /// (`applyPerspectiveCrop`) is unconditionally applied using those 4 corner points.
  static img.Image processPipeline({
    required img.Image sourceImage,
    required int rotationDegrees,
    CropQuad? cropQuad,
    Rect? normalizedCropRect,
    EnhanceMode enhanceMode = EnhanceMode.none,
    bool isEnhanced = false,
  }) {
    img.Image result = sourceImage.clone();

    // 1. Rotation
    if (rotationDegrees % 360 != 0) {
      result = rotateByDegrees(result, rotationDegrees);
    }

    // 2. Unconditional Perspective Crop & Straightening on confirmed cropQuad (FIX 1)
    if (cropQuad != null) {
      result = applyPerspectiveCrop(result, cropQuad);
    } else if (normalizedCropRect != null &&
        normalizedCropRect != const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0)) {
      result = cropNormalized(result, normalizedCropRect);
    }

    // 3. Enhance Filter Modes (FIX 2)
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
    final img.Image previewSized = downsampleForPreview(image, maxDimension: 1200);
    final Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(previewSized, quality: 84));
    await File(path).writeAsBytes(jpgBytes);
    return path;
  }

  /// Downsamples and compresses an image for PDF embedding.
  /// Standard Quality: ~1800px on longest side, 70% JPEG quality per image.
  static Uint8List compressForPdf(
    img.Image input, {
    PdfCompressionProfile profile = PdfCompressionProfile.standard,
  }) {
    switch (profile) {
      case PdfCompressionProfile.standard:
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
