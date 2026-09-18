import 'dart:io';
import 'package:flutter/material.dart';

class PdfPageItem {
  final String id;
  final String sourcePath;
  String currentPreviewPath;
  int rotationDegrees;
  bool isEnhanced;
  bool isFlattened;
  Rect? normalizedCropRect; // In range [0.0, 1.0]
  bool mergedWithNext;

  PdfPageItem({
    required this.id,
    required this.sourcePath,
    required this.currentPreviewPath,
    this.rotationDegrees = 0,
    this.isEnhanced = false,
    this.isFlattened = false,
    this.normalizedCropRect,
    this.mergedWithNext = false,
  });

  File get previewFile => File(currentPreviewPath);

  PdfPageItem cloneWith({
    String? currentPreviewPath,
    int? rotationDegrees,
    bool? isEnhanced,
    bool? isFlattened,
    Rect? normalizedCropRect,
    bool? mergedWithNext,
  }) {
    return PdfPageItem(
      id: id,
      sourcePath: sourcePath,
      currentPreviewPath: currentPreviewPath ?? this.currentPreviewPath,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      isEnhanced: isEnhanced ?? this.isEnhanced,
      isFlattened: isFlattened ?? this.isFlattened,
      normalizedCropRect: normalizedCropRect ?? this.normalizedCropRect,
      mergedWithNext: mergedWithNext ?? this.mergedWithNext,
    );
  }
}
