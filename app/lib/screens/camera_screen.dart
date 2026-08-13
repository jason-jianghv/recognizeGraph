import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/screens/gallery_crop_screen.dart';
import 'package:shitu_app/screens/result_screen.dart';
import 'package:shitu_app/services/recognize_api.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/utils/image_crop.dart';
import 'package:shitu_app/utils/viewfinder_geometry.dart';
import 'package:shitu_app/widgets/common.dart';
import 'package:shitu_app/widgets/viewfinder_frame.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  final _picker = ImagePicker();
  final _api = RecognizeApi();

  CameraController? _controller;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  FlashMode _flashMode = FlashMode.off;
  Key _previewKey = UniqueKey();

  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;
  Offset? _focusIndicator; // 预览区内坐标，用于点按对焦动画
  Timer? _focusIndicatorTimer;
  File? _capturedStill; // 拍完/选图后冻结画面，避免识别时摄像头预览卡顿
  Size? _previewSize; // 取景区尺寸，用于拍后按框裁切

  RecognizeCategory _category = RecognizeCategory.animal;
  bool _busy = false;
  bool _starting = true;
  bool _switching = false;
  String? _startError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 进页即开摄像头；无权限时系统会弹窗，拒绝后展示引导
    _openCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _focusIndicatorTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null) {
        _openCamera();
      }
    }
  }

  Future<void> _disposeController() async {
    final previous = _controller;
    if (previous == null) return;
    _controller = null;
    if (mounted) setState(() {});
    // 等 CameraPreview 从树上拆掉，再 dispose，避免纹理卡死
    await Future<void>.delayed(Duration.zero);
    final frame = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => frame.complete());
    await frame.future;
    await previous.dispose();
  }

  Future<void> _openCamera() async {
    if (_switching) return;
    setState(() {
      _starting = true;
      _startError = null;
    });

    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _cameras = const [];
          _starting = false;
          _startError = '这个设备没有可用摄像头，可以从相册选一张图～';
        });
        return;
      }

      _cameras = cameras;
      var index = cameras.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
      if (index < 0) index = 0;
      _cameraIndex = index;
      await _bindCamera(cameras[index]);
    } on CameraException catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = _friendlyCameraError(e);
      });
      if (_isPermissionDenied(e)) {
        await _showPermissionDialog();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _starting = false;
        _startError = '打不开摄像头：$e';
      });
    }
  }

  Future<void> _bindCamera(CameraDescription description) async {
    // 必须先释放旧会话，再开新摄像头；否则 iOS 常卡在最后一帧
    await _disposeController();
    if (!mounted) return;

    setState(() {
      _starting = true;
      _startError = null;
    });

    final controller = CameraController(
      description,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.jpeg,
    );

    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }

      // 前置摄像头常不支持闪光灯，失败时不要整次切换失败
      try {
        await controller.setFlashMode(_flashMode);
      } catch (_) {
        _flashMode = FlashMode.off;
        try {
          await controller.setFlashMode(FlashMode.off);
        } catch (_) {}
      }

      try {
        await controller.setFocusMode(FocusMode.auto);
      } catch (_) {}

      var minZoom = 1.0;
      var maxZoom = 1.0;
      try {
        minZoom = await controller.getMinZoomLevel();
        final deviceMax = await controller.getMaxZoomLevel();
        // 产品限制：最大 3.5 倍，避免拉杆行程过大、画面糊
        maxZoom = deviceMax.clamp(minZoom, 3.5);
        if (maxZoom < minZoom) maxZoom = minZoom;
        await controller.setZoomLevel(minZoom);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _previewKey = UniqueKey();
        _minZoom = minZoom;
        _maxZoom = maxZoom;
        _zoom = minZoom;
        _focusIndicator = null;
        _starting = false;
        _startError = null;
      });
    } on CameraException catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _starting = false;
        _startError = _friendlyCameraError(e);
      });
      if (_isPermissionDenied(e)) {
        await _showPermissionDialog();
      }
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _controller = null;
        _starting = false;
        _startError = '打不开摄像头：$e';
      });
    }
  }

  bool _isPermissionDenied(CameraException e) {
    final code = e.code.toLowerCase();
    return code.contains('access') ||
        code.contains('permission') ||
        code.contains('denied') ||
        code.contains('unauthorized');
  }

  String _friendlyCameraError(CameraException e) {
    if (_isPermissionDenied(e)) {
      return '需要相机权限，才能看到实时画面并拍照哦';
    }
    return e.description?.isNotEmpty == true
        ? e.description!
        : '摄像头暂时不可用（${e.code}）';
  }

  Future<void> _showPermissionDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('需要相机权限'),
        content: const Text('请在系统设置里允许「识图」使用相机，回来后就能看到实时画面啦。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openCamera();
            },
            child: const Text('再试一次'),
          ),
        ],
      ),
    );
  }

  Future<void> _onTapToFocus(TapUpDetails details, Size previewSize) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy || _starting) {
      return;
    }

    final local = details.localPosition;
    final nx = (local.dx / previewSize.width).clamp(0.0, 1.0);
    final ny = (local.dy / previewSize.height).clamp(0.0, 1.0);
    // 前置预览是镜像的，对焦点 x 需要翻转
    final focus = Offset(
      controller.description.lensDirection == CameraLensDirection.front ? 1 - nx : nx,
      ny,
    );

    setState(() => _focusIndicator = local);
    _focusIndicatorTimer?.cancel();
    _focusIndicatorTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _focusIndicator = null);
    });

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setFocusPoint(focus);
      await controller.setExposurePoint(focus);
    } catch (_) {
      // 部分机型/前置不支持点对焦，忽略即可
    }
  }

  Future<void> _onZoomChanged(double value) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    final zoom = value.clamp(_minZoom, _maxZoom);
    setState(() => _zoom = zoom);
    try {
      await controller.setZoomLevel(zoom);
    } catch (_) {}
  }

  Future<void> _toggleFlash() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _busy) return;
    final next = _flashMode == FlashMode.off ? FlashMode.torch : FlashMode.off;
    try {
      await controller.setFlashMode(next);
      if (!mounted) return;
      setState(() => _flashMode = next);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('这台设备不支持闪光灯～')),
      );
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2 || _busy || _starting || _switching) return;
    _switching = true;
    try {
      final next = (_cameraIndex + 1) % _cameras.length;
      _cameraIndex = next;
      await _bindCamera(_cameras[next]);
    } finally {
      _switching = false;
    }
  }

  Future<void> _takePicture() async {
    final controller = _controller;
    if (_busy) return;
    if (controller == null || !controller.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_startError ?? '摄像头还没准备好，稍等一下～')),
      );
      return;
    }
    if (controller.value.isTakingPicture) return;

    try {
      final shot = await controller.takePicture();
      final raw = File(shot.path);
      if (!mounted) return;

      final preview = _previewSize ?? MediaQuery.sizeOf(context);
      final topInset = MediaQuery.paddingOf(context).top;
      final vf = ViewfinderGeometry.rectInPreview(preview, topInset);
      final cropped = await cropImageToViewfinder(
        source: raw,
        viewportSize: preview,
        viewfinderInViewport: vf,
      );

      if (!mounted) return;

      // 先定格裁后图并关掉实时预览，识别过程不再刷摄像头
      setState(() {
        _busy = true;
        _capturedStill = cropped;
        _focusIndicator = null;
      });
      await _disposeController();

      await _recognizeFile(cropped);
    } on CameraException catch (e) {
      if (!mounted) return;
      await _recoverPreviewAfterFailure();
      await _showErrorDialog('拍照失败', _friendlyCameraError(e));
    } on RecognizeApiException catch (e) {
      if (!mounted) return;
      await _recoverPreviewAfterFailure();
      await _showErrorDialog('识别失败', e.message);
    } catch (e) {
      if (!mounted) return;
      await _recoverPreviewAfterFailure();
      await _showErrorDialog('识别出了点小状况', '$e');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_busy) return;
    final x = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
      maxWidth: 2048,
    );
    if (x == null || !mounted) return;

    final picked = File(x.path);
    final cropped = await Navigator.of(context).push<File>(
      MaterialPageRoute<File>(
        builder: (_) => GalleryCropScreen(imageFile: picked),
      ),
    );
    if (cropped == null || !mounted) return;

    setState(() {
      _busy = true;
      _capturedStill = cropped;
      _focusIndicator = null;
    });
    await _disposeController();

    try {
      await _recognizeFile(cropped);
    } on RecognizeApiException catch (e) {
      if (!mounted) return;
      await _recoverPreviewAfterFailure();
      await _showErrorDialog('识别失败', e.message);
    } catch (e) {
      if (!mounted) return;
      await _recoverPreviewAfterFailure();
      await _showErrorDialog('识别出了点小状况', '$e');
    }
  }

  /// 识别失败：清掉定格图，重新打开摄像头
  Future<void> _recoverPreviewAfterFailure() async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _capturedStill = null;
    });
    await _openCamera();
  }

  Future<void> _recognizeFile(File file) async {
    await _api.ping();
    final result = await _api.recognize(category: _category, imageFile: file);
    if (!mounted) return;
    if (result.candidates.isEmpty) {
      await _recoverPreviewAfterFailure();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没看清哦，再拍一张试试～')),
      );
      return;
    }
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ResultScreen(
          imageFile: file,
          result: result,
        ),
      ),
    );
  }

  Future<void> _showErrorDialog(String title, String message) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // 上半：取景区（对齐 Figma「取景区」）
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final previewSize = Size(constraints.maxWidth, constraints.maxHeight);
                _previewSize = previewSize;
                final topInset = MediaQuery.paddingOf(context).top;
                final vf = ViewfinderGeometry.rectInPreview(previewSize, topInset);
                final canZoom = _maxZoom - _minZoom > 0.05;
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: _busy || _capturedStill != null
                          ? null
                          : (d) => _onTapToFocus(d, previewSize),
                      child: _buildPreview(),
                    ),
                    if (_focusIndicator != null)
                      Positioned(
                        left: _focusIndicator!.dx - 28,
                        top: _focusIndicator!.dy - 28,
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(begin: 1.15, end: 1),
                            duration: const Duration(milliseconds: 280),
                            builder: (context, scale, child) {
                              return Transform.scale(scale: scale, child: child);
                            },
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.8),
                              ),
                            ),
                          ),
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
                    SafeArea(
                      bottom: false,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                              child: Row(
                                children: [
                                  SoftBackButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                  ),
                                  const Spacer(),
                                  Material(
                                    color: Colors.black.withValues(alpha: 0.35),
                                    shape: const CircleBorder(),
                                    child: InkWell(
                                      customBorder: const CircleBorder(),
                                      onTap: _busy ? null : _toggleFlash,
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Icon(
                                          _flashMode == FlashMode.off
                                              ? Icons.flash_off_rounded
                                              : Icons.flash_on_rounded,
                                          color: Colors.white,
                                          size: 22,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            left: 24,
                            right: 56,
                            bottom: 16,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  '把小伙伴放进框里再拍哦',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    shadows: [
                                      Shadow(blurRadius: 8, color: Colors.black54),
                                    ],
                                  ),
                                ),
                                if (_startError != null &&
                                    (_controller == null ||
                                        !(_controller!.value.isInitialized)))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      _startError!,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          if (canZoom && _capturedStill == null)
                            Align(
                              alignment: Alignment.centerRight,
                              child: Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: SizedBox(
                                  width: 40,
                                  height: 208,
                                  child: _ZoomRail(
                                    value: _zoom,
                                    min: _minZoom,
                                    max: _maxZoom,
                                    onChanged: _busy ? null : _onZoomChanged,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_busy)
                      ColoredBox(
                        color: const Color(0x66000000),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CircularProgressIndicator(color: Colors.white),
                              const SizedBox(height: 16),
                              Text(
                                _capturedStill != null ? '正在认出是谁…' : '请稍等…',
                                style: const TextStyle(color: Colors.white, fontSize: 18),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          // 下半：白底操作区（对齐 Figma「操作区」）
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 胶囊分类切换（白底操作区上的浅底胶囊）
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3EEE9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final c in RecognizeCategory.values)
                          _CategoryChip(
                            label: c.label,
                            selected: _category == c,
                            onTap: () => setState(() => _category = c),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SideAction(
                        icon: Icons.photo_library_outlined,
                        label: '相册',
                        outlined: true,
                        onTap: _busy ? null : _pickFromGallery,
                      ),
                      GestureDetector(
                        onTap: _busy ? null : _takePicture,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTokens.primary,
                          ),
                          child: _busy
                              ? const Padding(
                                  padding: EdgeInsets.all(20),
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 3,
                                  ),
                                )
                              : const Icon(
                                  Icons.circle,
                                  color: Colors.white,
                                  size: 28,
                                ),
                        ),
                      ),
                      _SideAction(
                        icon: Icons.cameraswitch_outlined,
                        label: '翻转',
                        outlined: false,
                        onTap: (_busy || _cameras.length < 2) ? null : _flipCamera,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final still = _capturedStill;
    if (still != null) {
      return ColoredBox(
        color: const Color(0xFF262626),
        child: Image.file(
          still,
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    final controller = _controller;
    if (_starting) {
      return const ColoredBox(
        color: Color(0xFF262626),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Colors.white70),
              SizedBox(height: 16),
              Text('正在打开摄像头…', style: TextStyle(color: Colors.white70)),
            ],
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return const ColoredBox(
        color: Color(0xFF262626),
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              '对准小伙伴，保持主体清晰\n也可以从相册选一张图',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
            ),
          ),
        ),
      );
    }

    return ClipRect(
      key: _previewKey,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? MediaQuery.sizeOf(context).width,
            height: controller.value.previewSize?.width ?? MediaQuery.sizeOf(context).height,
            child: CameraPreview(controller),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppTokens.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppTokens.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomRail extends StatelessWidget {
  const _ZoomRail({
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
    final label = value < 10 ? value.toStringAsFixed(1) : value.toStringAsFixed(0);
    return Column(
      children: [
        Text(
          '${label}x',
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
              // 竖向拉杆：上大下小（往上拖放大）
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
                  painter: _ZoomRailPainter(
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

class _ZoomRailPainter extends CustomPainter {
  const _ZoomRailPainter({required this.progress});

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

    final thumb = Paint()..color = Colors.white;
    canvas.drawCircle(Offset(cx, thumbY), 9, thumb);
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
  bool shouldRepaint(covariant _ZoomRailPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _SideAction extends StatelessWidget {
  const _SideAction({
    required this.icon,
    required this.label,
    required this.outlined,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool outlined;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: outlined ? Colors.white : AppTokens.primarySoft,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: outlined ? 72 : 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: outlined
                    ? Border.all(color: AppTokens.primary, width: 2)
                    : null,
              ),
              child: Icon(icon, color: AppTokens.primary, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: const TextStyle(
            color: AppTokens.primary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
