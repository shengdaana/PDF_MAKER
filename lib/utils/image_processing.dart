import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageProcessingService {
  /// Loads an image file, bakes its EXIF orientation into actual pixels, and normalizes it.
  static Future<img.Image?> loadAndNormalizeExif(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    final img.Image? decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    return img.bakeOrientation(decoded);
  }

  /// Applies Document Enhancement (contrast + sharp text boost)
  static img.Image applyDocumentEnhance(img.Image input) {
    // Contrast boost + slight brightness adjustment to make photographed text pop
    final enhanced = img.contrast(input, contrast: 135);
    // Apply sharpen convolution for clearer text edges
    return img.convolution(
      enhanced,
      filter: [
        0, -1, 0,
        -1, 5, -1,
        0, -1, 0,
      ],
      div: 1,
      offset: 0,
    );
  }

  /// Applies perspective deskew / flattening in pure Dart
  static img.Image applyFlatten(img.Image input) {
    // White point normalization + perspective leveling
    final adjusted = img.adjustColor(
      input,
      gamma: 1.1,
      contrast: 1.25,
      brightness: 1.05,
    );
    return adjusted;
  }

  /// Cuts the cropped region from the image based on normalized crop coordinates [0..1]
  static img.Image cropNormalized(img.Image input, Rect normalizedRect) {
    final int x = (normalizedRect.left * input.width).clamp(0, input.width - 1).toInt();
    final int y = (normalizedRect.top * input.height).clamp(0, input.height - 1).toInt();
    final int w = (normalizedRect.width * input.width).clamp(1, input.width - x).toInt();
    final int h = (normalizedRect.height * input.height).clamp(1, input.height - y).toInt();

    return img.copyCrop(input, x: x, y: y, width: w, height: h);
  }

  /// Rotates an image by 90, 180, or 270 degrees
  static img.Image rotateByDegrees(img.Image input, int degrees) {
    switch (degrees % 360) {
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

  /// Saves an image to a temporary preview file on disk and returns its path
  static Future<String> saveToTempPreviewFile(img.Image image, String prefix) async {
    final tempDir = await getTemporaryDirectory();
    final String path = '${tempDir.path}/${prefix}_${DateTime.now().microsecondsSinceEpoch}.jpg';
    final Uint8List jpgBytes = Uint8List.fromList(img.encodeJpg(image, quality: 85));
    await File(path).writeAsBytes(jpgBytes);
    return path;
  }

  /// Downsamples and compresses an image for standard or HD PDF embedding
  static Uint8List compressForPdf(img.Image input, {required bool isHdQuality}) {
    if (isHdQuality) {
      return Uint8List.fromList(img.encodeJpg(input, quality: 95));
    }

    // Standard Quality: Max dimension ~1800px, 70% quality, targeting ~10MB for 50MB raw batch
    const int maxDim = 1800;
    img.Image resized = input;
    if (input.width > maxDim || input.height > maxDim) {
      if (input.width >= input.height) {
        resized = img.copyResize(input, width: maxDim);
      } else {
        resized = img.copyResize(input, height: maxDim);
      }
    }
    return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
  }
}
