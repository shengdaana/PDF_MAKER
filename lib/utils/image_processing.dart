import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'image_processor.dart';

export 'image_processor.dart';

/// Backward-compatibility wrapper delegating to ImageProcessor
class ImageProcessingService {
  static Future<img.Image?> loadAndNormalizeExif(File file) =>
      ImageProcessor.loadAndNormalizeExif(file);

  static img.Image cropNormalized(img.Image input, Rect normalizedRect) =>
      ImageProcessor.cropNormalized(input, normalizedRect);

  static img.Image rotateByDegrees(img.Image input, int degrees) =>
      ImageProcessor.rotateByDegrees(input, degrees);

  static Future<String> saveToTempPreviewFile(img.Image image, String prefix) =>
      ImageProcessor.saveToTempPreviewFile(image, prefix);

  static Uint8List compressForPdf(img.Image input, {required bool isHdQuality}) =>
      ImageProcessor.compressForPdf(
        input,
        profile: isHdQuality ? PdfCompressionProfile.hdOriginal : PdfCompressionProfile.standard,
      );
}
