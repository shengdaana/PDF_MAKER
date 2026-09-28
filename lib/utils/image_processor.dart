import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import '../models/pdf_page_item.dart';

/// Compression profiles for PDF generation
enum PdfCompressionProfile {
  /// Standard: Universal default. ~1800px on longest side, 70% JPEG quality per image.
  standard,

  /// High Compression: ~1200px max, 55% quality for ultra-compact files.
  highCompression,

  /// HD Original: Full camera resolution up to 3200px, 90% quality for archiving/print.
  hdOriginal,
}

class PreviewRenderData {
  final Uint8List baseBytes;
  final Uint8List displayBytes;
  final int width;
  final int height;

  const PreviewRenderData({
    required this.baseBytes,
    required this.displayBytes,
    required this.width,
    required this.height,
  });
}

class CompressedPageData {
  final Uint8List bytes;
  final double width;
  final double height;

  const CompressedPageData({
    required this.bytes,
    required this.width,
    required this.height,
  });
}

/// Image Processing Engine for PDF Maker
/// - All heavy decoding, EXIF normalization, perspective rectification (`img.copyRectify`),
///   rotation, and JPEG compression run off the main UI isolate via `Isolate.run`.
/// - Untouched full-frame crop corners bypass perspective warp completely.
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

  /// Synchronous helper (intended to run inside an Isolate):
  /// Loads an image file and bakes its EXIF orientation into actual pixels.
  static img.Image? decodeAndNormalizeSync(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) return null;
    final Uint8List bytes = file.readAsBytesSync();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }

  /// Loads an image file and normalizes EXIF orientation off the main UI isolate (FIX 3).
  static Future<img.Image?> loadAndNormalizeExif(File file) async {
    final String path = file.path;
    return Isolate.run(() => decodeAndNormalizeSync(path));
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

  /// Perspective deskew & crop:
  /// Warps and straightens the 4-corner quadrilateral placed by the user
  /// using `img.copyRectify` while preserving the true Euclidean edge-length aspect ratio.
  static img.Image applyPerspectiveCrop(img.Image input, CropQuad quad) {
    if (quad.isFullFrame) {
      return input;
    }

    final int w = input.width;
    final int h = input.height;
    if (w <= 2 || h <= 2) return input;

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

  /// Legacy axis-aligned crop helper
  static img.Image cropNormalized(img.Image input, Rect normalizedRect) {
    if (normalizedRect == const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0)) {
      return input;
    }
    final int x = (normalizedRect.left * input.width).clamp(0, input.width - 1).toInt();
    final int y = (normalizedRect.top * input.height).clamp(0, input.height - 1).toInt();
    final int w = (normalizedRect.width * input.width).clamp(1, input.width - x).toInt();
    final int h = (normalizedRect.height * input.height).clamp(1, input.height - y).toInt();

    return img.copyCrop(input, x: x, y: y, width: w, height: h);
  }

  /// Downsamples an image to [maxDimension] on its longest side for fast UI previews.
  static img.Image downsampleForPreview(img.Image input, {int maxDimension = 960}) {
    if (input.width <= maxDimension && input.height <= maxDimension) {
      return input;
    }
    if (input.width >= input.height) {
      return img.copyResize(input, width: maxDimension, interpolation: img.Interpolation.linear);
    } else {
      return img.copyResize(input, height: maxDimension, interpolation: img.Interpolation.linear);
    }
  }

  /// Deterministic processing pipeline (FIX 1 & FIX 2):
  /// - Only rotates if [rotationDegrees] % 360 != 0.
  /// - Only runs [applyPerspectiveCrop] if [cropQuad] is non-null and NOT full-frame.
  /// - If neither rotation nor custom crop was applied, returns [sourceImage] directly as-is.
  static img.Image processPipeline({
    required img.Image sourceImage,
    required int rotationDegrees,
    CropQuad? cropQuad,
    Rect? normalizedCropRect,
  }) {
    final bool hasRotation = (rotationDegrees % 360) != 0;
    final bool hasQuadCrop = cropQuad != null && !cropQuad.isFullFrame;
    final bool hasRectCrop = normalizedCropRect != null &&
        normalizedCropRect != const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0);

    // FIX 2: Untouched pages return the EXIF-normalized source image directly as-is
    if (!hasRotation && !hasQuadCrop && !hasRectCrop) {
      return sourceImage;
    }

    img.Image result = sourceImage;

    // 1. Rotation
    if (hasRotation) {
      result = rotateByDegrees(result, rotationDegrees);
    }

    // 2. Perspective Crop & Straightening only when corners were moved away from full-frame (FIX 2)
    if (hasQuadCrop) {
      result = applyPerspectiveCrop(result, cropQuad);
    } else if (hasRectCrop) {
      result = cropNormalized(result, normalizedCropRect);
    }

    return result;
  }

  /// Generates a lightweight downsampled thumbnail file in a background isolate (FIX 3)
  /// so Arrange screen cards and Edit screen previews never decode full camera-resolution photos.
  static Future<String> generateDownsampledThumbnail({
    required String sourcePath,
    required String tempDirPath,
    required String pageId,
    int maxDimension = 960,
  }) async {
    return Isolate.run(() {
      try {
        final img.Image? normalized = decodeAndNormalizeSync(sourcePath);
        if (normalized == null) return sourcePath;

        // If already small enough, still write a clean EXIF-normalized preview copy
        final img.Image thumb = downsampleForPreview(normalized, maxDimension: maxDimension);
        final Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(thumb, quality: 82));
        final String outPath = '$tempDirPath/thumb_$pageId.jpg';
        File(outPath).writeAsBytesSync(jpgBytes, flush: true);
        return outPath;
      } catch (_) {
        return sourcePath;
      }
    });
  }

  /// Loads the downsampled preview in a background isolate for the Edit screen (FIX 3).
  /// Never blocks the main UI isolate and reuses the existing downsampled base preview when available.
  static Future<PreviewRenderData?> loadEditPreviewInIsolate({
    required String sourcePath,
    required String basePreviewPath,
    required int rotationDegrees,
  }) async {
    return Isolate.run(() {
      img.Image? baseImg;

      // Reuse already-downsampled basePreviewPath if it differs from raw sourcePath and exists
      if (basePreviewPath != sourcePath && File(basePreviewPath).existsSync()) {
        final bytes = File(basePreviewPath).readAsBytesSync();
        baseImg = img.decodeImage(bytes);
      }

      if (baseImg == null) {
        final normalized = decodeAndNormalizeSync(sourcePath);
        if (normalized == null) return null;
        baseImg = downsampleForPreview(normalized, maxDimension: 960);
      }

      final Uint8List baseBytes = Uint8List.fromList(img.encodeJpg(baseImg, quality: 85));

      if (rotationDegrees % 360 == 0) {
        return PreviewRenderData(
          baseBytes: baseBytes,
          displayBytes: baseBytes,
          width: baseImg.width,
          height: baseImg.height,
        );
      }

      final img.Image rotated = rotateByDegrees(baseImg, rotationDegrees);
      final Uint8List displayBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 85));
      return PreviewRenderData(
        baseBytes: baseBytes,
        displayBytes: displayBytes,
        width: rotated.width,
        height: rotated.height,
      );
    });
  }

  /// Rotates the already-downsampled preview bytes in a background isolate (FIX 3)
  /// when the user taps Rotate 90° in EditScreen.
  static Future<PreviewRenderData?> rotatePreviewInIsolate({
    required Uint8List baseBytes,
    required int rotationDegrees,
  }) async {
    return Isolate.run(() {
      final img.Image? baseImg = img.decodeImage(baseBytes);
      if (baseImg == null) return null;

      if (rotationDegrees % 360 == 0) {
        return PreviewRenderData(
          baseBytes: baseBytes,
          displayBytes: baseBytes,
          width: baseImg.width,
          height: baseImg.height,
        );
      }

      final img.Image rotated = rotateByDegrees(baseImg, rotationDegrees);
      final Uint8List displayBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 85));
      return PreviewRenderData(
        baseBytes: baseBytes,
        displayBytes: displayBytes,
        width: rotated.width,
        height: rotated.height,
      );
    });
  }

  /// Executes EditScreen Confirm in a background isolate (FIX 2 & FIX 3):
  /// - If the user left crop corners at full-frame and rotation is 0°, returns [basePreviewPath]
  ///   immediately without touching or re-encoding the image.
  /// - If only rotated (crop corners at full-frame), rotates the preview without running perspective crop.
  /// - If crop corners were moved away from full-frame, runs perspective crop (`copyRectify`)
  ///   in the background isolate and saves a downsampled preview file.
  static Future<String> confirmEditsInIsolate({
    required String sourcePath,
    required String basePreviewPath,
    required String tempDirPath,
    required String pageId,
    required int rotationDegrees,
    required CropQuad cropQuad,
  }) async {
    final bool hasRotation = (rotationDegrees % 360) != 0;
    final bool hasCustomCrop = !cropQuad.isFullFrame;

    // FIX 2: If neither rotation nor crop corners were changed, return original preview immediately
    if (!hasRotation && !hasCustomCrop) {
      if (File(basePreviewPath).existsSync()) {
        return basePreviewPath;
      }
    }

    return Isolate.run(() {
      // Fast path when only rotation changed and we already have a downsampled base preview
      if (!hasCustomCrop &&
          basePreviewPath != sourcePath &&
          File(basePreviewPath).existsSync()) {
        final baseBytes = File(basePreviewPath).readAsBytesSync();
        final baseDecoded = img.decodeImage(baseBytes);
        if (baseDecoded != null) {
          final rotated = rotateByDegrees(baseDecoded, rotationDegrees);
          final outPath = '$tempDirPath/page_${pageId}_${DateTime.now().microsecondsSinceEpoch}.jpg';
          final jpgBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 84));
          File(outPath).writeAsBytesSync(jpgBytes, flush: true);
          return outPath;
        }
      }

      // Full-resolution source processing in background isolate when custom crop is confirmed
      final img.Image? normalized = decodeAndNormalizeSync(sourcePath);
      if (normalized == null) return basePreviewPath;

      final img.Image processed = processPipeline(
        sourceImage: normalized,
        rotationDegrees: rotationDegrees,
        cropQuad: hasCustomCrop ? cropQuad : null,
      );

      final img.Image previewSized = downsampleForPreview(processed, maxDimension: 960);
      final Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(previewSized, quality: 84));
      final String outPath = '$tempDirPath/page_${pageId}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      File(outPath).writeAsBytesSync(jpgBytes, flush: true);
      return outPath;
    });
  }

  /// Saves an image to a temporary file on disk inside a background isolate.
  static Future<String> saveToTempPreviewFile(img.Image image, String prefix) async {
    final tempDir = await getTemporaryDirectory();
    final String tempDirPath = tempDir.path;
    return Isolate.run(() {
      final String path = '$tempDirPath/${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final img.Image previewSized = downsampleForPreview(image, maxDimension: 960);
      final Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(previewSized, quality: 84));
      File(path).writeAsBytesSync(jpgBytes, flush: true);
      return path;
    });
  }

  /// Downsamples and compresses an image for PDF embedding, returning both bytes and dimensions
  /// so the caller never has to re-decode the compressed JPEG (FIX 3).
  static CompressedPageData compressForPdfWithDimensions(
    img.Image input, {
    PdfCompressionProfile profile = PdfCompressionProfile.standard,
  }) {
    int maxDim;
    int quality;

    switch (profile) {
      case PdfCompressionProfile.standard:
        maxDim = 1800;
        quality = 70;
        break;
      case PdfCompressionProfile.highCompression:
        maxDim = 1200;
        quality = 55;
        break;
      case PdfCompressionProfile.hdOriginal:
        maxDim = 3200;
        quality = 90;
        break;
    }

    img.Image resized = input;
    if (input.width > maxDim || input.height > maxDim) {
      if (input.width >= input.height) {
        resized = img.copyResize(input, width: maxDim, interpolation: img.Interpolation.linear);
      } else {
        resized = img.copyResize(input, height: maxDim, interpolation: img.Interpolation.linear);
      }
    }

    final Uint8List bytes = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
    return CompressedPageData(
      bytes: bytes,
      width: resized.width.toDouble(),
      height: resized.height.toDouble(),
    );
  }

  /// Backward-compatible byte-only compression helper
  static Uint8List compressForPdf(
    img.Image input, {
    PdfCompressionProfile profile = PdfCompressionProfile.standard,
  }) {
    return compressForPdfWithDimensions(input, profile: profile).bytes;
  }
}
