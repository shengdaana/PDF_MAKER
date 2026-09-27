import 'dart:io';
import 'package:flutter/material.dart';

/// Enhance filter modes per REDESIGN 6
enum EnhanceMode {
  none,
  originalColor, // Default: sharpness and contrast boost only, colors preserved as-is
  grayscale, // Desaturated but retains tonal shading
  bwHighContrast, // Pure high-contrast black/white scan mode
}

/// 4-point quadrilateral for manual perspective crop & deskew (FIX 1)
class CropQuad {
  final Offset topLeft; // Normalized coordinates in range [0.0 .. 1.0]
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const CropQuad({
    this.topLeft = const Offset(0.05, 0.05),
    this.topRight = const Offset(0.95, 0.05),
    this.bottomRight = const Offset(0.95, 0.95),
    this.bottomLeft = const Offset(0.05, 0.95),
  });

  static const CropQuad full = CropQuad(
    topLeft: Offset(0.0, 0.0),
    topRight: Offset(1.0, 0.0),
    bottomRight: Offset(1.0, 1.0),
    bottomLeft: Offset(0.0, 1.0),
  );

  bool get isFullFrame =>
      (topLeft.dx <= 0.01 && topLeft.dy <= 0.01) &&
      (topRight.dx >= 0.99 && topRight.dy <= 0.01) &&
      (bottomRight.dx >= 0.99 && bottomRight.dy >= 0.99) &&
      (bottomLeft.dx <= 0.01 && bottomLeft.dy >= 0.99);

  CropQuad copyWith({
    Offset? topLeft,
    Offset? topRight,
    Offset? bottomRight,
    Offset? bottomLeft,
  }) {
    return CropQuad(
      topLeft: topLeft ?? this.topLeft,
      topRight: topRight ?? this.topRight,
      bottomRight: bottomRight ?? this.bottomRight,
      bottomLeft: bottomLeft ?? this.bottomLeft,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is CropQuad &&
        other.topLeft == topLeft &&
        other.topRight == topRight &&
        other.bottomRight == bottomRight &&
        other.bottomLeft == bottomLeft;
  }

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);
}

class PdfPageItem {
  final String id;
  final String sourcePath;
  String currentPreviewPath;
  int rotationDegrees;
  EnhanceMode enhanceMode;
  CropQuad? cropQuad;
  Rect? normalizedCropRect; // In range [0.0, 1.0] for legacy compatibility
  bool mergedWithNext;

  PdfPageItem({
    required this.id,
    required this.sourcePath,
    required this.currentPreviewPath,
    this.rotationDegrees = 0,
    this.enhanceMode = EnhanceMode.none,
    bool isEnhanced = false,
    this.cropQuad,
    this.normalizedCropRect,
    this.mergedWithNext = false,
  }) {
    if (isEnhanced && enhanceMode == EnhanceMode.none) {
      enhanceMode = EnhanceMode.originalColor;
    }
  }

  bool get isEnhanced => enhanceMode != EnhanceMode.none;
  set isEnhanced(bool val) {
    enhanceMode = val ? EnhanceMode.originalColor : EnhanceMode.none;
  }

  File get previewFile => File(currentPreviewPath);

  PdfPageItem cloneWith({
    String? currentPreviewPath,
    int? rotationDegrees,
    EnhanceMode? enhanceMode,
    bool? isEnhanced,
    CropQuad? cropQuad,
    Rect? normalizedCropRect,
    bool? mergedWithNext,
  }) {
    EnhanceMode resolvedEnhance = enhanceMode ?? this.enhanceMode;
    if (isEnhanced != null) {
      resolvedEnhance = isEnhanced ? EnhanceMode.originalColor : EnhanceMode.none;
    }

    return PdfPageItem(
      id: id,
      sourcePath: sourcePath,
      currentPreviewPath: currentPreviewPath ?? this.currentPreviewPath,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      enhanceMode: resolvedEnhance,
      cropQuad: cropQuad ?? this.cropQuad,
      normalizedCropRect: normalizedCropRect ?? this.normalizedCropRect,
      mergedWithNext: mergedWithNext ?? this.mergedWithNext,
    );
  }
}
