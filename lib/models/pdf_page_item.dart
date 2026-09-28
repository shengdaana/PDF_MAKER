import 'dart:io';
import 'package:flutter/material.dart';

/// 4-point quadrilateral for manual perspective crop & deskew.
/// Defaults to full-frame [0.0 .. 1.0] so untouched pages are never cropped (FIX 2).
class CropQuad {
  final Offset topLeft; // Normalized coordinates in range [0.0 .. 1.0]
  final Offset topRight;
  final Offset bottomRight;
  final Offset bottomLeft;

  const CropQuad({
    this.topLeft = const Offset(0.0, 0.0),
    this.topRight = const Offset(1.0, 0.0),
    this.bottomRight = const Offset(1.0, 1.0),
    this.bottomLeft = const Offset(0.0, 1.0),
  });

  static const CropQuad full = CropQuad(
    topLeft: Offset(0.0, 0.0),
    topRight: Offset(1.0, 0.0),
    bottomRight: Offset(1.0, 1.0),
    bottomLeft: Offset(0.0, 1.0),
  );

  bool get isFullFrame =>
      (topLeft.dx <= 0.005 && topLeft.dy <= 0.005) &&
      (topRight.dx >= 0.995 && topRight.dy <= 0.005) &&
      (bottomRight.dx >= 0.995 && bottomRight.dy >= 0.995) &&
      (bottomLeft.dx <= 0.005 && bottomLeft.dy >= 0.995);

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
  String basePreviewPath;
  String currentPreviewPath;
  int rotationDegrees;
  CropQuad? cropQuad;
  Rect? normalizedCropRect; // In range [0.0, 1.0] for legacy compatibility
  bool mergedWithNext;

  PdfPageItem({
    required this.id,
    required this.sourcePath,
    required this.currentPreviewPath,
    String? basePreviewPath,
    this.rotationDegrees = 0,
    this.cropQuad,
    this.normalizedCropRect,
    this.mergedWithNext = false,
  }) : basePreviewPath = basePreviewPath ?? currentPreviewPath;

  bool get hasCustomCrop =>
      (cropQuad != null && !cropQuad!.isFullFrame) ||
      (normalizedCropRect != null &&
          normalizedCropRect != const Rect.fromLTWH(0.0, 0.0, 1.0, 1.0));

  bool get hasEdits => (rotationDegrees % 360 != 0) || hasCustomCrop;

  File get previewFile => File(currentPreviewPath);

  PdfPageItem cloneWith({
    String? basePreviewPath,
    String? currentPreviewPath,
    int? rotationDegrees,
    CropQuad? cropQuad,
    bool clearCropQuad = false,
    Rect? normalizedCropRect,
    bool? mergedWithNext,
  }) {
    return PdfPageItem(
      id: id,
      sourcePath: sourcePath,
      basePreviewPath: basePreviewPath ?? this.basePreviewPath,
      currentPreviewPath: currentPreviewPath ?? this.currentPreviewPath,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      cropQuad: clearCropQuad ? null : (cropQuad ?? this.cropQuad),
      normalizedCropRect: clearCropQuad ? null : (normalizedCropRect ?? this.normalizedCropRect),
      mergedWithNext: mergedWithNext ?? this.mergedWithNext,
    );
  }
}
