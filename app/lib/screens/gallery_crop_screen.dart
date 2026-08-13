import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/utils/image_crop.dart';
import 'package:shitu_app/utils/viewfinder_geometry.dart';
import 'package:shitu_app/widgets/viewfinder_frame.dart';

/// 相册选图后：平移 / 捏合 / 拉杆缩放，使主体落入取景框，确定后裁切返回。
class GalleryCropScreen extends StatefulWidget {
  const GalleryCropScreen({super.key, required this.imageFile});

  final File imageFile;

  @override
  State<GalleryCropScreen> createState() => _GalleryCropScreenState();
}

class _GalleryCropScreenState extends State<GalleryCropScreen> {
  final _picker = ImagePicker();

  late File _file;
  Size? _imageSize;

  double _userScale = 1;
  Offset _offset = Offset.zero;

  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Offset? _focalViewport;

  bool _busy = false;
  Size? _viewportSize;

  static const _minScale = 1.0;
  static const _maxScale = 4.0;

  @override
  void initState() {
    super.initState();
    _file = widget.imageFile;
    _loadImage(_file);
  }

  Future<void> _loadImage(File file) async {
    final bytes = await file.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _file = file;
      _imageSize = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      _userScale = 1;
      _offset = Offset.zero;
    });
  }

  void _clampOffset(Size viewport, Size imageSize) {
    final base = math.max(
      viewport.width / imageSize.width,
      viewport.height / imageSize.height,
    );
    final scale = base * _userScale;
    final dispW = imageSize.width * scale;
    final dispH = imageSize.height * scale;
    // 保证取景框始终被图片覆盖：至少覆盖整个视口（cover）
    final maxDx = math.max(0.0, (dispW - viewport.width) / 2);
    final maxDy = math.max(0.0, (dispH - viewport.height) / 2);
    _offset = Offset(
      _offset.dx.clamp(-maxDx, maxDx),
      _offset.dy.clamp(-maxDy, maxDy),
    );
  }

  Future<void> _reselect() async {
    if (_busy) return;
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2048,
    );
    if (x == null || !mounted) return;
    await _loadImage(File(x.path));
  }

  Future<void> _confirm() async {
    final viewport = _viewportSize;
    final imageSize = _imageSize;
    if (_busy || viewport == null || imageSize == null) return;

    setState(() => _busy = true);
    try {
      final topInset = MediaQuery.paddingOf(context).top;
      final vf = ViewfinderGeometry.rectInPreview(viewport, topInset);
      final cropped = await cropImageToViewfinder(
        source: _file,
        viewportSize: viewport,
        viewfinderInViewport: vf,
        userScale: _userScale,
        offset: _offset,
        transformed: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop(cropped);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('裁剪失败：$e')),
      );
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                _viewportSize = viewport;
                final imageSize = _imageSize;
                final vf = ViewfinderGeometry.rectInPreview(viewport, topInset);

                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: const Color(0xFF262626),
                      child: imageSize == null
                          ? const Center(
                              child: CircularProgressIndicator(color: Colors.white70),
                            )
                          : GestureDetector(
                              onScaleStart: (d) {
                                _startScale = _userScale;
                                _startOffset = _offset;
                                _focalViewport = d.focalPoint;
                              },
                              onScaleUpdate: (d) {
                                setState(() {
                                  _userScale =
                                      (_startScale * d.scale).clamp(_minScale, _maxScale);
                                  final delta = d.focalPoint - (_focalViewport ?? d.focalPoint);
                                  _offset = _startOffset + delta;
                                  _clampOffset(viewport, imageSize);
                                });
                              },
                              child: _buildTransformedImage(viewport, imageSize),
                            ),
                    ),
                    // 取景框外压暗
                    IgnorePointer(
                      child: CustomPaint(
                        painter: _DimOutsidePainter(hole: vf),
                        size: viewport,
                      ),
                    ),
                    IgnorePointer(
                      child: Stack(
                        children: [
                          Positioned(
                            left: vf.left,
                            top: vf.top,
                            width: vf.width,
                            height: vf.height,
                            child: const ViewfinderCornerFrame(),
                          ),
                        ],
                      ),
                    ),
                    if (imageSize != null)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: SizedBox(
                            width: 40,
                            height: 208,
                            child: _CropZoomRail(
                              value: _userScale,
                              min: _minScale,
                              max: _maxScale,
                              onChanged: _busy
                                  ? null
                                  : (v) {
                                      setState(() {
                                        _userScale = v;
                                        _clampOffset(viewport, imageSize);
                                      });
                                    },
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      left: 24,
                      right: 56,
                      bottom: 16,
                      child: Text(
                        '拖动图片，把要认的小伙伴放进框里',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.95),
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(blurRadius: 8, color: Colors.black54),
                          ],
                        ),
                      ),
                    ),
                    if (_busy)
                      const ColoredBox(
                        color: Color(0x66000000),
                        child: Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SizedBox(
                    width: 96,
                    height: 54,
                    child: OutlinedButton(
                      onPressed: _busy ? null : _reselect,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTokens.primary,
                        side: const BorderSide(color: AppTokens.primary, width: 2),
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      child: const Text(
                        '重选',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                    ),
                  ),
                  Material(
                    color: AppTokens.primary,
                    shape: const CircleBorder(),
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _busy ? null : _confirm,
                      child: const SizedBox(
                        width: 64,
                        height: 64,
                        child: Icon(Icons.check_rounded, color: Colors.white, size: 34),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 96,
                    height: 54,
                    child: Center(
                      child: Material(
                        color: const Color(0xFFF3EEE9),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _busy ? null : () => Navigator.of(context).pop(),
                          child: const SizedBox(
                            width: 54,
                            height: 54,
                            child: Icon(
                              Icons.close_rounded,
                              color: AppTokens.textPrimary,
                              size: 28,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransformedImage(Size viewport, Size imageSize) {
    final base = math.max(
      viewport.width / imageSize.width,
      viewport.height / imageSize.height,
    );
    final scale = base * _userScale;
    final dispW = imageSize.width * scale;
    final dispH = imageSize.height * scale;
    final left = (viewport.width - dispW) / 2 + _offset.dx;
    final top = (viewport.height - dispH) / 2 + _offset.dy;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          left: left,
          top: top,
          width: dispW,
          height: dispH,
          child: Image.file(
            _file,
            fit: BoxFit.fill,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ],
    );
  }
}

class _DimOutsidePainter extends CustomPainter {
  const _DimOutsidePainter({required this.hole});

  final Rect hole;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final inner = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(12)));
    final path = Path.combine(PathOperation.difference, outer, inner);
    canvas.drawPath(path, Paint()..color = const Color(0x66000000));
  }

  @override
  bool shouldRepaint(covariant _DimOutsidePainter oldDelegate) {
    return oldDelegate.hole != hole;
  }
}

class _CropZoomRail extends StatelessWidget {
  const _CropZoomRail({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    final label = '${value.toStringAsFixed(1)}x';
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 6, color: Colors.black54)],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onVerticalDragUpdate: onChanged == null
                    ? null
                    : (d) {
                        final h = constraints.maxHeight;
                        if (h <= 0) return;
                        final t = (1 - (d.localPosition.dy / h)).clamp(0.0, 1.0);
                        onChanged!(min + (max - min) * t);
                      },
                onTapDown: onChanged == null
                    ? null
                    : (d) {
                        final h = constraints.maxHeight;
                        if (h <= 0) return;
                        final t = (1 - (d.localPosition.dy / h)).clamp(0.0, 1.0);
                        onChanged!(min + (max - min) * t);
                      },
                child: CustomPaint(
                  painter: _CropZoomRailPainter(
                    progress: ((value - min) / (max - min)).clamp(0.0, 1.0),
                  ),
                  child: const SizedBox.expand(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CropZoomRailPainter extends CustomPainter {
  const _CropZoomRailPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final track = Paint()
      ..color = Colors.white.withValues(alpha: 0.28)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final active = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    const pad = 10.0;
    final top = pad;
    final bottom = size.height - pad;
    canvas.drawLine(Offset(cx, top), Offset(cx, bottom), track);
    final thumbY = bottom - (bottom - top) * progress;
    canvas.drawLine(Offset(cx, thumbY), Offset(cx, bottom), active);
    canvas.drawCircle(Offset(cx, thumbY), 9, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(cx, thumbY),
      9,
      Paint()
        ..color = AppTokens.primary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _CropZoomRailPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
