import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/pdf_page_item.dart';

enum _HandleType {
  none,
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
}

class CropOverlayWidget extends StatefulWidget {
  final CropQuad cropQuad;
  final Rect imageDisplayRect; // The exact pixel bounds where the image is displayed
  final Uint8List? previewImageBytes; // Source preview image bytes for genuine loupe zoom
  final ValueChanged<CropQuad> onQuadChanged;

  const CropOverlayWidget({
    super.key,
    required this.cropQuad,
    required this.imageDisplayRect,
    this.previewImageBytes,
    required this.onQuadChanged,
  });

  @override
  State<CropOverlayWidget> createState() => _CropOverlayWidgetState();
}

class _CropOverlayWidgetState extends State<CropOverlayWidget> {
  // Pre-instantiated Paints for zero-allocation performance & zero shader jank (FIX 2)
  late final Paint _scrimPaint;
  late final Paint _borderPaint;
  late final Paint _gridPaint;
  late final Paint _handleShadowLayer1Paint;
  late final Paint _handleShadowLayer2Paint;
  late final Paint _handleOuterRingPaint;
  late final Paint _handleInnerFillPaint;
  late final Paint _activeHandleFillPaint;
  late final Paint _centerDotInactivePaint;
  late final Paint _centerDotActivePaint;

  // Reusable paths (zero allocation in paint loop)
  final Path _scrimPath = Path();
  final Path _borderPath = Path();

  _HandleType _activeHandle = _HandleType.none;
  Offset _currentTouchPosition = Offset.zero;
  late CropQuad _currentQuad;

  // Touch and visual handle constants
  static const double _touchHitRadius = 56.0; // 56dp touch hit area
  static const double _defaultVisualRadius = 10.0; // 20dp diameter
  static const double _draggingVisualRadius = 15.0; // 30dp diameter

  // Magnifying Loupe constants (FIX 1)
  static const double _loupeSize = 112.0; // 112dp circular loupe
  static const double _loupeRadius = _loupeSize / 2.0;
  static const double _zoomFactor = 2.4; // 2.4x genuine zoom magnification

  @override
  void initState() {
    super.initState();
    _currentQuad = widget.cropQuad;

    _scrimPaint = Paint()
      ..color = const Color(0x99000000)
      ..style = PaintingStyle.fill;

    _borderPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    _gridPaint = Paint()
      ..color = Colors.white.withOpacity(0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Dual-layer drop shadow without MaskFilter.blur to avoid shader compilation jank on first handle scale
    _handleShadowLayer1Paint = Paint()
      ..color = const Color(0x18000000)
      ..style = PaintingStyle.fill;

    _handleShadowLayer2Paint = Paint()
      ..color = const Color(0x35000000)
      ..style = PaintingStyle.fill;

    _handleOuterRingPaint = Paint()
      ..color = const Color(0xFF1E1E1E)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    _handleInnerFillPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    _activeHandleFillPaint = Paint()
      ..color = const Color(0xFFFBBF24) // Amber glow when actively dragging
      ..style = PaintingStyle.fill;

    _centerDotInactivePaint = Paint()
      ..color = const Color(0xFF4F46E5)
      ..style = PaintingStyle.fill;

    _centerDotActivePaint = Paint()
      ..color = Colors.black87
      ..style = PaintingStyle.fill;
  }

  @override
  void didUpdateWidget(CropOverlayWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_activeHandle == _HandleType.none && widget.cropQuad != oldWidget.cropQuad) {
      _currentQuad = widget.cropQuad;
    }
  }

  Offset _toPixel(Offset norm) {
    final r = widget.imageDisplayRect;
    return Offset(
      r.left + norm.dx * r.width,
      r.top + norm.dy * r.height,
    );
  }

  Offset _toNorm(Offset pixel) {
    final r = widget.imageDisplayRect;
    if (r.width <= 0 || r.height <= 0) return Offset.zero;
    return Offset(
      ((pixel.dx - r.left) / r.width).clamp(0.0, 1.0),
      ((pixel.dy - r.top) / r.height).clamp(0.0, 1.0),
    );
  }

  _HandleType _detectHandle(Offset localPosition) {
    final tl = _toPixel(_currentQuad.topLeft);
    final tr = _toPixel(_currentQuad.topRight);
    final bl = _toPixel(_currentQuad.bottomLeft);
    final br = _toPixel(_currentQuad.bottomRight);

    // Check corners with generous 56dp hit radius
    final dTL = (localPosition - tl).distance;
    final dTR = (localPosition - tr).distance;
    final dBL = (localPosition - bl).distance;
    final dBR = (localPosition - br).distance;

    double minDist = _touchHitRadius;
    _HandleType closest = _HandleType.none;

    if (dTL <= minDist) {
      minDist = dTL;
      closest = _HandleType.topLeft;
    }
    if (dTR <= minDist) {
      minDist = dTR;
      closest = _HandleType.topRight;
    }
    if (dBL <= minDist) {
      minDist = dBL;
      closest = _HandleType.bottomLeft;
    }
    if (dBR <= minDist) {
      minDist = dBR;
      closest = _HandleType.bottomRight;
    }

    return closest;
  }

  void _onPanStart(DragStartDetails details) {
    final handle = _detectHandle(details.localPosition);
    if (handle != _HandleType.none) {
      setState(() {
        _activeHandle = handle;
        _currentTouchPosition = details.localPosition;
      });
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    if (_activeHandle == _HandleType.none) return;

    final newNorm = _toNorm(details.localPosition);
    CropQuad updated = _currentQuad;

    switch (_activeHandle) {
      case _HandleType.topLeft:
        updated = updated.copyWith(topLeft: newNorm);
        break;
      case _HandleType.topRight:
        updated = updated.copyWith(topRight: newNorm);
        break;
      case _HandleType.bottomLeft:
        updated = updated.copyWith(bottomLeft: newNorm);
        break;
      case _HandleType.bottomRight:
        updated = updated.copyWith(bottomRight: newNorm);
        break;
      case _HandleType.none:
        break;
    }

    setState(() {
      _currentQuad = updated;
      _currentTouchPosition = details.localPosition;
    });

    widget.onQuadChanged(updated);
  }

  void _onPanEnd(DragEndDetails details) {
    if (_activeHandle != _HandleType.none) {
      setState(() {
        _activeHandle = _HandleType.none;
      });
    }
  }

  void _onPanCancel() {
    if (_activeHandle != _HandleType.none) {
      setState(() {
        _activeHandle = _HandleType.none;
      });
    }
  }

  Offset? get _activeCornerNorm {
    switch (_activeHandle) {
      case _HandleType.topLeft:
        return _currentQuad.topLeft;
      case _HandleType.topRight:
        return _currentQuad.topRight;
      case _HandleType.bottomLeft:
        return _currentQuad.bottomLeft;
      case _HandleType.bottomRight:
        return _currentQuad.bottomRight;
      case _HandleType.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double viewW = constraints.maxWidth;
        final double viewH = constraints.maxHeight;

        // Calculate Loupe Position & Sampling (FIX 1)
        Widget? loupeWidget;
        final cornerNorm = _activeCornerNorm;

        if (_activeHandle != _HandleType.none &&
            cornerNorm != null &&
            widget.previewImageBytes != null &&
            widget.imageDisplayRect.width > 0 &&
            widget.imageDisplayRect.height > 0) {
          // 1. Position loupe slightly above the touch point (default: -85dp)
          double loupeCenterX = _currentTouchPosition.dx;
          double loupeCenterY = _currentTouchPosition.dy - 85.0;

          // Flip below finger if too close to the top screen edge
          if (loupeCenterY - _loupeRadius < 8.0) {
            loupeCenterY = _currentTouchPosition.dy + 85.0;
          }

          // Clamp so the loupe is completely within the viewport
          loupeCenterX = loupeCenterX.clamp(_loupeRadius + 6.0, viewW - _loupeRadius - 6.0);
          loupeCenterY = loupeCenterY.clamp(_loupeRadius + 6.0, viewH - _loupeRadius - 6.0);

          final double loupeLeft = loupeCenterX - _loupeRadius;
          final double loupeTop = loupeCenterY - _loupeRadius;

          // 2. Calculate pixel coordinates inside source image
          final double cornerImgX = cornerNorm.dx * widget.imageDisplayRect.width;
          final double cornerImgY = cornerNorm.dy * widget.imageDisplayRect.height;

          // 3. Magnified image dimensions & offset inside loupe circle
          final double scaledImgW = widget.imageDisplayRect.width * _zoomFactor;
          final double scaledImgH = widget.imageDisplayRect.height * _zoomFactor;

          final double imgLeftInLoupe = _loupeRadius - (cornerImgX * _zoomFactor);
          final double imgTopInLoupe = _loupeRadius - (cornerImgY * _zoomFactor);

          loupeWidget = Positioned(
            left: loupeLeft,
            top: loupeTop,
            width: _loupeSize,
            height: _loupeSize,
            child: IgnorePointer(
              child: Container(
                width: _loupeSize,
                height: _loupeSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 3.0),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x77000000),
                      blurRadius: 10,
                      spreadRadius: 2,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // Neutral dark background for areas outside document bounds
                      Positioned.fill(
                        child: Container(color: const Color(0xFF141414)),
                      ),

                      // Genuine zoomed preview image (zero re-decoding, GPU-cached)
                      Positioned(
                        left: imgLeftInLoupe,
                        top: imgTopInLoupe,
                        width: scaledImgW,
                        height: scaledImgH,
                        child: Image.memory(
                          widget.previewImageBytes!,
                          fit: BoxFit.fill,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),

                      // Circular inner border shadow
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0x33000000), width: 1.0),
                          ),
                        ),
                      ),

                      // Crosshair Reticle centered on exact corner landing spot
                      const Positioned.fill(
                        child: _LoupeReticle(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return RepaintBoundary(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: _onPanStart,
            onPanUpdate: _onPanUpdate,
            onPanEnd: _onPanEnd,
            onPanCancel: _onPanCancel,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // Crop Quad, Scrim, and Handles Canvas
                Positioned.fill(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _QuadCropPainter(
                      cropQuad: _currentQuad,
                      imageDisplayRect: widget.imageDisplayRect,
                      activeHandle: _activeHandle,
                      scrimPaint: _scrimPaint,
                      borderPaint: _borderPaint,
                      gridPaint: _gridPaint,
                      handleShadowLayer1Paint: _handleShadowLayer1Paint,
                      handleShadowLayer2Paint: _handleShadowLayer2Paint,
                      outerRingPaint: _handleOuterRingPaint,
                      innerFillPaint: _handleInnerFillPaint,
                      activeFillPaint: _activeHandleFillPaint,
                      centerDotInactivePaint: _centerDotInactivePaint,
                      centerDotActivePaint: _centerDotActivePaint,
                      scrimPath: _scrimPath,
                      borderPath: _borderPath,
                      defaultRadius: _defaultVisualRadius,
                      draggingRadius: _draggingVisualRadius,
                    ),
                  ),
                ),

                // Magnifying Loupe Overlay (FIX 1: appears only while dragging)
                if (loupeWidget != null) loupeWidget,
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuadCropPainter extends CustomPainter {
  final CropQuad cropQuad;
  final Rect imageDisplayRect;
  final _HandleType activeHandle;
  final Paint scrimPaint;
  final Paint borderPaint;
  final Paint gridPaint;
  final Paint handleShadowLayer1Paint;
  final Paint handleShadowLayer2Paint;
  final Paint outerRingPaint;
  final Paint innerFillPaint;
  final Paint activeFillPaint;
  final Paint centerDotInactivePaint;
  final Paint centerDotActivePaint;
  final Path scrimPath;
  final Path borderPath;
  final double defaultRadius;
  final double draggingRadius;

  _QuadCropPainter({
    required this.cropQuad,
    required this.imageDisplayRect,
    required this.activeHandle,
    required this.scrimPaint,
    required this.borderPaint,
    required this.gridPaint,
    required this.handleShadowLayer1Paint,
    required this.handleShadowLayer2Paint,
    required this.outerRingPaint,
    required this.innerFillPaint,
    required this.activeFillPaint,
    required this.centerDotInactivePaint,
    required this.centerDotActivePaint,
    required this.scrimPath,
    required this.borderPath,
    required this.defaultRadius,
    required this.draggingRadius,
  });

  Offset _toPixel(Offset norm) {
    final r = imageDisplayRect;
    return Offset(
      r.left + norm.dx * r.width,
      r.top + norm.dy * r.height,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (imageDisplayRect.isEmpty) return;

    final tl = _toPixel(cropQuad.topLeft);
    final tr = _toPixel(cropQuad.topRight);
    final br = _toPixel(cropQuad.bottomRight);
    final bl = _toPixel(cropQuad.bottomLeft);

    // 1. Scrim overlay outside document crop quad (Zero allocation via evenOdd Path)
    scrimPath.reset();
    scrimPath.fillType = PathFillType.evenOdd;
    scrimPath.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    scrimPath.moveTo(tl.dx, tl.dy);
    scrimPath.lineTo(tr.dx, tr.dy);
    scrimPath.lineTo(br.dx, br.dy);
    scrimPath.lineTo(bl.dx, bl.dy);
    scrimPath.close();
    canvas.drawPath(scrimPath, scrimPaint);

    // 2. Interior 3x3 rule-of-thirds grid
    for (double f = 0.333; f < 0.9; f += 0.333) {
      final leftH = Offset.lerp(tl, bl, f)!;
      final rightH = Offset.lerp(tr, br, f)!;
      canvas.drawLine(leftH, rightH, gridPaint);

      final topV = Offset.lerp(tl, tr, f)!;
      final botV = Offset.lerp(bl, br, f)!;
      canvas.drawLine(topV, botV, gridPaint);
    }

    // 3. Document Quad Border (Zero allocation)
    borderPath.reset();
    borderPath.moveTo(tl.dx, tl.dy);
    borderPath.lineTo(tr.dx, tr.dy);
    borderPath.lineTo(br.dx, br.dy);
    borderPath.lineTo(bl.dx, bl.dy);
    borderPath.close();
    canvas.drawPath(borderPath, borderPaint);

    // 4. Corner Handles (Zero Paint allocations in paint loop)
    _drawHandle(canvas, tl, _HandleType.topLeft);
    _drawHandle(canvas, tr, _HandleType.topRight);
    _drawHandle(canvas, bl, _HandleType.bottomLeft);
    _drawHandle(canvas, br, _HandleType.bottomRight);
  }

  void _drawHandle(Canvas canvas, Offset pos, _HandleType type) {
    final bool isActive = activeHandle == type;
    final double radius = isActive ? draggingRadius : defaultRadius;

    // Dual-layer solid shadow (eliminates MaskFilter.blur shader compilation jank)
    canvas.drawCircle(pos.translate(0, 2), radius + 3.0, handleShadowLayer1Paint);
    canvas.drawCircle(pos.translate(0, 1.5), radius + 1.5, handleShadowLayer2Paint);

    // Inner fill (amber when dragging, white otherwise)
    canvas.drawCircle(pos, radius, isActive ? activeFillPaint : innerFillPaint);

    // Dark contrasting outer ring
    canvas.drawCircle(pos, radius, outerRingPaint);

    // Accent center dot for precision targeting (pre-instantiated paints)
    canvas.drawCircle(
      pos,
      isActive ? 4.0 : 3.0,
      isActive ? centerDotActivePaint : centerDotInactivePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _QuadCropPainter oldDelegate) {
    return oldDelegate.cropQuad != cropQuad ||
        oldDelegate.imageDisplayRect != imageDisplayRect ||
        oldDelegate.activeHandle != activeHandle;
  }
}

class _LoupeReticle extends StatelessWidget {
  const _LoupeReticle();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _LoupeReticlePainter(),
    );
  }
}

class _LoupeReticlePainter extends CustomPainter {
  final Paint _reticlePaint = Paint()
    ..color = const Color(0xFFFBBF24) // High-visibility amber
    ..strokeWidth = 1.4
    ..style = PaintingStyle.stroke;

  final Paint _reticleDarkBorderPaint = Paint()
    ..color = const Color(0xCC000000)
    ..strokeWidth = 2.8
    ..style = PaintingStyle.stroke;

  final Paint _centerDotPaint = Paint()
    ..color = const Color(0xFFFBBF24)
    ..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const double gap = 6.0;

    // 1. Draw dark backing lines for contrast on bright documents
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, center.dy - gap), _reticleDarkBorderPaint);
    canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, size.height), _reticleDarkBorderPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(center.dx - gap, center.dy), _reticleDarkBorderPaint);
    canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(size.width, center.dy), _reticleDarkBorderPaint);

    // 2. Draw amber precision crosshair lines
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, center.dy - gap), _reticlePaint);
    canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, size.height), _reticlePaint);
    canvas.drawLine(Offset(0, center.dy), Offset(center.dx - gap, center.dy), _reticlePaint);
    canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(size.width, center.dy), _reticlePaint);

    // 3. Center precision targeting ring & pin dot
    canvas.drawCircle(center, gap, _reticleDarkBorderPaint);
    canvas.drawCircle(center, gap, _reticlePaint);
    canvas.drawCircle(center, 1.6, _centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
