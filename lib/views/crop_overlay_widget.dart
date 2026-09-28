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

class _CropDragState {
  final CropQuad quad;
  final _HandleType activeHandle;
  final Offset touchPosition;

  const _CropDragState({
    required this.quad,
    this.activeHandle = _HandleType.none,
    this.touchPosition = Offset.zero,
  });

  _CropDragState copyWith({
    CropQuad? quad,
    _HandleType? activeHandle,
    Offset? touchPosition,
  }) {
    return _CropDragState(
      quad: quad ?? this.quad,
      activeHandle: activeHandle ?? this.activeHandle,
      touchPosition: touchPosition ?? this.touchPosition,
    );
  }
}

class CropOverlayWidget extends StatefulWidget {
  final CropQuad cropQuad;
  final Rect imageDisplayRect; // Exact pixel bounds where the image is displayed
  final Uint8List? previewImageBytes; // Downsampled preview image bytes for loupe zoom
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
  // Pre-instantiated Paints for zero-allocation performance & zero shader jank
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

  // ValueNotifier drives CustomPainter repaint and Loupe position without rebuilding parent widgets (FIX 3)
  late final ValueNotifier<_CropDragState> _dragStateNotifier;
  MemoryImage? _cachedPreviewImage;

  // Touch and visual handle constants
  static const double _touchHitRadius = 56.0; // 56dp touch hit area
  static const double _defaultVisualRadius = 10.0; // 20dp diameter
  static const double _draggingVisualRadius = 15.0; // 30dp diameter

  // Magnifying Loupe constants
  static const double _loupeSize = 112.0; // 112dp circular loupe
  static const double _loupeRadius = _loupeSize / 2.0;
  static const double _zoomFactor = 2.4; // 2.4x genuine zoom magnification

  @override
  void initState() {
    super.initState();
    _dragStateNotifier = ValueNotifier<_CropDragState>(
      _CropDragState(quad: widget.cropQuad),
    );
    if (widget.previewImageBytes != null) {
      _cachedPreviewImage = MemoryImage(widget.previewImageBytes!);
    }

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
      ..color = const Color(0xFFFBBF24)
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
    if (widget.previewImageBytes != oldWidget.previewImageBytes) {
      _cachedPreviewImage = widget.previewImageBytes != null
          ? MemoryImage(widget.previewImageBytes!)
          : null;
    }
    final current = _dragStateNotifier.value;
    if (current.activeHandle == _HandleType.none && widget.cropQuad != current.quad) {
      _dragStateNotifier.value = current.copyWith(quad: widget.cropQuad);
    }
  }

  @override
  void dispose() {
    _dragStateNotifier.dispose();
    super.dispose();
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

  _HandleType _detectHandle(Offset localPosition, CropQuad quad) {
    final tl = _toPixel(quad.topLeft);
    final tr = _toPixel(quad.topRight);
    final bl = _toPixel(quad.bottomLeft);
    final br = _toPixel(quad.bottomRight);

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
    final current = _dragStateNotifier.value;
    final handle = _detectHandle(details.localPosition, current.quad);
    if (handle != _HandleType.none) {
      _dragStateNotifier.value = current.copyWith(
        activeHandle: handle,
        touchPosition: details.localPosition,
      );
    }
  }

  void _onPanUpdate(DragUpdateDetails details) {
    final current = _dragStateNotifier.value;
    if (current.activeHandle == _HandleType.none) return;

    final newNorm = _toNorm(details.localPosition);
    CropQuad updated = current.quad;

    switch (current.activeHandle) {
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

    _dragStateNotifier.value = current.copyWith(
      quad: updated,
      touchPosition: details.localPosition,
    );

    widget.onQuadChanged(updated);
  }

  void _onPanEnd(DragEndDetails details) {
    final current = _dragStateNotifier.value;
    if (current.activeHandle != _HandleType.none) {
      _dragStateNotifier.value = current.copyWith(activeHandle: _HandleType.none);
    }
  }

  void _onPanCancel() {
    final current = _dragStateNotifier.value;
    if (current.activeHandle != _HandleType.none) {
      _dragStateNotifier.value = current.copyWith(activeHandle: _HandleType.none);
    }
  }

  Offset? _activeCornerNorm(_CropDragState state) {
    switch (state.activeHandle) {
      case _HandleType.topLeft:
        return state.quad.topLeft;
      case _HandleType.topRight:
        return state.quad.topRight;
      case _HandleType.bottomLeft:
        return state.quad.bottomLeft;
      case _HandleType.bottomRight:
        return state.quad.bottomRight;
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
                // 1. Crop Quad, Scrim, and Handles Canvas — repaints directly via _dragStateNotifier (zero widget rebuilds)
                Positioned.fill(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _QuadCropPainter(
                      stateListenable: _dragStateNotifier,
                      imageDisplayRect: widget.imageDisplayRect,
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

                // 2. Magnifying Loupe Overlay — scoped to ValueListenableBuilder
                ValueListenableBuilder<_CropDragState>(
                  valueListenable: _dragStateNotifier,
                  builder: (context, dragState, _) {
                    final cornerNorm = _activeCornerNorm(dragState);
                    if (dragState.activeHandle == _HandleType.none ||
                        cornerNorm == null ||
                        widget.previewImageBytes == null ||
                        widget.imageDisplayRect.width <= 0 ||
                        widget.imageDisplayRect.height <= 0) {
                      return const SizedBox.shrink();
                    }

                    double loupeCenterX = dragState.touchPosition.dx;
                    double loupeCenterY = dragState.touchPosition.dy - 85.0;

                    if (loupeCenterY - _loupeRadius < 8.0) {
                      loupeCenterY = dragState.touchPosition.dy + 85.0;
                    }

                    loupeCenterX = loupeCenterX.clamp(_loupeRadius + 6.0, viewW - _loupeRadius - 6.0);
                    loupeCenterY = loupeCenterY.clamp(_loupeRadius + 6.0, viewH - _loupeRadius - 6.0);

                    final double loupeLeft = loupeCenterX - _loupeRadius;
                    final double loupeTop = loupeCenterY - _loupeRadius;

                    final double cornerImgX = cornerNorm.dx * widget.imageDisplayRect.width;
                    final double cornerImgY = cornerNorm.dy * widget.imageDisplayRect.height;

                    final double scaledImgW = widget.imageDisplayRect.width * _zoomFactor;
                    final double scaledImgH = widget.imageDisplayRect.height * _zoomFactor;

                    final double imgLeftInLoupe = _loupeRadius - (cornerImgX * _zoomFactor);
                    final double imgTopInLoupe = _loupeRadius - (cornerImgY * _zoomFactor);

                    return Positioned(
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
                                const Positioned.fill(
                                  child: ColoredBox(color: Color(0xFF141414)),
                                ),
                                Positioned(
                                  left: imgLeftInLoupe,
                                  top: imgTopInLoupe,
                                  width: scaledImgW,
                                  height: scaledImgH,
                                  child: Image(
                                    image: _cachedPreviewImage ?? MemoryImage(widget.previewImageBytes!),
                                    fit: BoxFit.fill,
                                    gaplessPlayback: true,
                                    filterQuality: FilterQuality.low,
                                  ),
                                ),
                                const Positioned.fill(
                                  child: _LoupeReticle(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _QuadCropPainter extends CustomPainter {
  final ValueNotifier<_CropDragState> stateListenable;
  final Rect imageDisplayRect;
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
    required this.stateListenable,
    required this.imageDisplayRect,
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
  }) : super(repaint: stateListenable);

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

    final state = stateListenable.value;
    final cropQuad = state.quad;
    final activeHandle = state.activeHandle;

    final tl = _toPixel(cropQuad.topLeft);
    final tr = _toPixel(cropQuad.topRight);
    final br = _toPixel(cropQuad.bottomRight);
    final bl = _toPixel(cropQuad.bottomLeft);

    // 1. Scrim overlay outside document crop quad
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

    // 3. Document Quad Border
    borderPath.reset();
    borderPath.moveTo(tl.dx, tl.dy);
    borderPath.lineTo(tr.dx, tr.dy);
    borderPath.lineTo(br.dx, br.dy);
    borderPath.lineTo(bl.dx, bl.dy);
    borderPath.close();
    canvas.drawPath(borderPath, borderPaint);

    // 4. Corner Handles
    _drawHandle(canvas, tl, _HandleType.topLeft, activeHandle);
    _drawHandle(canvas, tr, _HandleType.topRight, activeHandle);
    _drawHandle(canvas, bl, _HandleType.bottomLeft, activeHandle);
    _drawHandle(canvas, br, _HandleType.bottomRight, activeHandle);
  }

  void _drawHandle(Canvas canvas, Offset pos, _HandleType type, _HandleType activeHandle) {
    final bool isActive = activeHandle == type;
    final double radius = isActive ? draggingRadius : defaultRadius;

    canvas.drawCircle(pos.translate(0, 2), radius + 3.0, handleShadowLayer1Paint);
    canvas.drawCircle(pos.translate(0, 1.5), radius + 1.5, handleShadowLayer2Paint);
    canvas.drawCircle(pos, radius, isActive ? activeFillPaint : innerFillPaint);
    canvas.drawCircle(pos, radius, outerRingPaint);
    canvas.drawCircle(
      pos,
      isActive ? 4.0 : 3.0,
      isActive ? centerDotActivePaint : centerDotInactivePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _QuadCropPainter oldDelegate) {
    return oldDelegate.imageDisplayRect != imageDisplayRect ||
        oldDelegate.stateListenable != stateListenable;
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
    ..color = const Color(0xFFFBBF24)
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

    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, center.dy - gap), _reticleDarkBorderPaint);
    canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, size.height), _reticleDarkBorderPaint);
    canvas.drawLine(Offset(0, center.dy), Offset(center.dx - gap, center.dy), _reticleDarkBorderPaint);
    canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(size.width, center.dy), _reticleDarkBorderPaint);

    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, center.dy - gap), _reticlePaint);
    canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, size.height), _reticlePaint);
    canvas.drawLine(Offset(0, center.dy), Offset(center.dx - gap, center.dy), _reticlePaint);
    canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(size.width, center.dy), _reticlePaint);

    canvas.drawCircle(center, gap, _reticleDarkBorderPaint);
    canvas.drawCircle(center, gap, _reticlePaint);
    canvas.drawCircle(center, 1.6, _centerDotPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
