import 'dart:math';
import 'package:flutter/material.dart';

enum _HandleType {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  right,
  top,
  bottom,
}

class CropOverlayWidget extends StatefulWidget {
  final Rect normalizedRect; // [0.0, 1.0]
  final Size displaySize;
  final ValueChanged<Rect> onCropChanged;

  const CropOverlayWidget({
    super.key,
    required this.normalizedRect,
    required this.displaySize,
    required this.onCropChanged,
  });

  @override
  State<CropOverlayWidget> createState() => _CropOverlayWidgetState();
}

class _CropOverlayWidgetState extends State<CropOverlayWidget> {
  // Pre-instantiated Paints (Performance: zero-lag, no allocations inside paint())
  late final Paint _scrimPaint;
  late final Paint _borderPaint;
  late final Paint _gridPaint;
  late final Paint _handleOuterRingPaint;
  late final Paint _handleInnerFillPaint;
  late final Paint _activeHandleFillPaint;

  _HandleType _activeHandle = _HandleType.none;
  Offset _lastDisplacementOffset = Offset.zero;

  // Visual & Touch handles constants
  static const double _touchHitRadius = 54.0; // 48-60dp hit target
  static const double _defaultVisualRadius = 8.0; // 16dp diameter
  static const double _draggingVisualRadius = 12.0; // 24dp diameter
  static const double _minDisplacement = 2.0; // 2.0px displacement throttle

  @override
  void initState() {
    super.initState();
    _scrimPaint = Paint()
      ..color = const Color(0x90000000)
      ..style = PaintingStyle.fill;

    _borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    _gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    _handleOuterRingPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    _handleInnerFillPaint = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.fill;

    _activeHandleFillPaint = Paint()
      ..color = const Color(0xFFFBBF24) // Bright amber when dragging
      ..style = PaintingStyle.fill;
  }

  Rect _toPixelRect(Rect norm, Size size) {
    return Rect.fromLTRB(
      norm.left * size.width,
      norm.top * size.height,
      norm.right * size.width,
      norm.bottom * size.height,
    );
  }

  Rect _toNormalizedRect(Rect pixels, Size size) {
    return Rect.fromLTRB(
      (pixels.left / size.width).clamp(0.0, 1.0),
      (pixels.top / size.height).clamp(0.0, 1.0),
      (pixels.right / size.width).clamp(0.0, 1.0),
      (pixels.bottom / size.height).clamp(0.0, 1.0),
    );
  }

  _HandleType _detectHandle(Offset localPosition, Rect rect) {
    // Check 4 corners first with hit radius
    if ((localPosition - rect.topLeft).distance <= _touchHitRadius) return _HandleType.topLeft;
    if ((localPosition - rect.topRight).distance <= _touchHitRadius) return _HandleType.topRight;
    if ((localPosition - rect.bottomLeft).distance <= _touchHitRadius) return _HandleType.bottomLeft;
    if ((localPosition - rect.bottomRight).distance <= _touchHitRadius) return _HandleType.bottomRight;

    // Check 4 edges
    if ((localPosition.dx - rect.left).abs() <= _touchHitRadius &&
        localPosition.dy >= rect.top && localPosition.dy <= rect.bottom) {
      return _HandleType.left;
    }
    if ((localPosition.dx - rect.right).abs() <= _touchHitRadius &&
        localPosition.dy >= rect.top && localPosition.dy <= rect.bottom) {
      return _HandleType.right;
    }
    if ((localPosition.dy - rect.top).abs() <= _touchHitRadius &&
        localPosition.dx >= rect.left && localPosition.dx <= rect.right) {
      return _HandleType.top;
    }
    if ((localPosition.dy - rect.bottom).abs() <= _touchHitRadius &&
        localPosition.dx >= rect.left && localPosition.dx <= rect.right) {
      return _HandleType.bottom;
    }

    return _HandleType.none;
  }

  void _onPanStart(DragStartDetails details) {
    final currentRect = _toPixelRect(widget.normalizedRect, widget.displaySize);
    final handle = _detectHandle(details.localPosition, currentRect);
    if (handle != _HandleType.none) {
      setState(() {
        _activeHandle = handle;
        _lastDisplacementOffset = details.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == _HandleType.none) return;

    final displacement = (details.localPosition - _lastDisplacementOffset).distance;
    // Throttle: only fire when drag displacement exceeds 2.0px
    if (displacement < _minDisplacement) return;
    _lastDisplacementOffset = details.localPosition;

    final pixelRect = _toPixelRect(widget.normalizedRect, widget.displaySize);
    final double minDim = 40.0; // Minimum crop size

    double left = pixelRect.left;
    double top = pixelRect.top;
    double right = pixelRect.right;
    double bottom = pixelRect.bottom;

    final double x = details.localPosition.dx.clamp(0.0, widget.displaySize.width);
    final double y = details.localPosition.dy.clamp(0.0, widget.displaySize.height);

    switch (_activeHandle) {
      case _HandleType.topLeft:
        left = min(x, right - minDim);
        top = min(y, bottom - minDim);
        break;
      case _HandleType.topRight:
        right = max(x, left + minDim);
        top = min(y, bottom - minDim);
        break;
      case _HandleType.bottomLeft:
        left = min(x, right - minDim);
        bottom = max(y, top + minDim);
        break;
      case _HandleType.bottomRight:
        right = max(x, left + minDim);
        bottom = max(y, top + minDim);
        break;
      case _HandleType.left:
        left = min(x, right - minDim);
        break;
      case _HandleType.right:
        right = max(x, left + minDim);
        break;
      case _HandleType.top:
        top = min(y, bottom - minDim);
        break;
      case _HandleType.bottom:
        bottom = max(y, top + minDim);
        break;
      case _HandleType.none:
        break;
    }

    final newNormalized = _toNormalizedRect(
      Rect.fromLTRB(left, top, right, bottom),
      widget.displaySize,
    );

    widget.onCropChanged(newNormalized);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activeHandle != _HandleType.none) {
      setState(() {
        _activeHandle = _HandleType.none;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pixelRect = _toPixelRect(widget.normalizedRect, widget.displaySize);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: _onPanStart,
      onPanUpdate: _onPanUpdate,
      onPanEnd: _onPanEnd,
      child: CustomPaint(
        size: widget.displaySize,
        painter: _CropPainter(
          cropRect: pixelRect,
          activeHandle: _activeHandle,
          scrimPaint: _scrimPaint,
          borderPaint: _borderPaint,
          gridPaint: _gridPaint,
          outerRingPaint: _handleOuterRingPaint,
          innerFillPaint: _handleInnerFillPaint,
          activeFillPaint: _activeHandleFillPaint,
          defaultRadius: _defaultVisualRadius,
          draggingRadius: _draggingVisualRadius,
        ),
      ),
    );
  }
}

class _CropPainter extends CustomPainter {
  final Rect cropRect;
  final _HandleType activeHandle;
  final Paint scrimPaint;
  final Paint borderPaint;
  final Paint gridPaint;
  final Paint outerRingPaint;
  final Paint innerFillPaint;
  final Paint activeFillPaint;
  final double defaultRadius;
  final double draggingRadius;

  _CropPainter({
    required this.cropRect,
    required this.activeHandle,
    required this.scrimPaint,
    required this.borderPaint,
    required this.gridPaint,
    required this.outerRingPaint,
    required this.innerFillPaint,
    required this.activeFillPaint,
    required this.defaultRadius,
    required this.draggingRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw Scrim outside crop area using Path combine
    final fullPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cropPath = Path()..addRect(cropRect);
    final scrimPath = Path.combine(PathOperation.difference, fullPath, cropPath);
    canvas.drawPath(scrimPath, scrimPaint);

    // 2. Draw Crop border
    canvas.drawRect(cropRect, borderPaint);

    // 3. Draw Rule of Thirds 3x3 Grid
    final double colStep = cropRect.width / 3.0;
    final double rowStep = cropRect.height / 3.0;
    canvas.drawLine(Offset(cropRect.left + colStep, cropRect.top), Offset(cropRect.left + colStep, cropRect.bottom), gridPaint);
    canvas.drawLine(Offset(cropRect.left + 2 * colStep, cropRect.top), Offset(cropRect.left + 2 * colStep, cropRect.bottom), gridPaint);
    canvas.drawLine(Offset(cropRect.left, cropRect.top + rowStep), Offset(cropRect.right, cropRect.top + rowStep), gridPaint);
    canvas.drawLine(Offset(cropRect.left, cropRect.top + 2 * rowStep), Offset(cropRect.right, cropRect.top + 2 * rowStep), gridPaint);

    // 4. Draw 4 Visual Handles
    _drawHandle(canvas, cropRect.topLeft, _HandleType.topLeft);
    _drawHandle(canvas, cropRect.topRight, _HandleType.topRight);
    _drawHandle(canvas, cropRect.bottomLeft, _HandleType.bottomLeft);
    _drawHandle(canvas, cropRect.bottomRight, _HandleType.bottomRight);
  }

  void _drawHandle(Canvas canvas, Offset center, _HandleType type) {
    final bool isDragging = activeHandle == type;
    final double radius = isDragging ? draggingRadius : defaultRadius;
    final fillPaint = isDragging ? activeFillPaint : innerFillPaint;

    // Dual-layer paint: white center + dark 3dp outer ring
    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, outerRingPaint);
  }

  @override
  bool shouldRepaint(covariant _CropPainter oldDelegate) {
    return oldDelegate.cropRect != cropRect || oldDelegate.activeHandle != activeHandle;
  }
}
