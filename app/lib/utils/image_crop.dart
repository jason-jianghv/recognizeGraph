import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shitu_app/utils/viewfinder_geometry.dart';

/// 将 [source] 按视口取景框裁成 JPEG（识别 / 历史统一用裁后图）。
Future<File> cropImageToViewfinder({
  required File source,
  required Size viewportSize,
  required Rect viewfinderInViewport,
  double userScale = 1,
  Offset offset = Offset.zero,
  bool transformed = false,
}) async {
  final bytes = await source.readAsBytes();
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('无法解码图片');
  }
  final image = img.bakeOrientation(decoded);
  final imageSize = Size(image.width.toDouble(), image.height.toDouble());

  final mapped = transformed
      ? ViewfinderGeometry.mapTransformedRectToImage(
          viewport: viewportSize,
          imageSize: imageSize,
          viewportRect: viewfinderInViewport,
          userScale: userScale,
          offset: offset,
        )
      : ViewfinderGeometry.mapCoverRectToImage(
          viewport: viewportSize,
          imageSize: imageSize,
          viewportRect: viewfinderInViewport,
        );

  final crop = ViewfinderGeometry.clampToImage(mapped, imageSize);
  final x = crop.left.round().clamp(0, image.width - 1);
  final y = crop.top.round().clamp(0, image.height - 1);
  var w = crop.width.round();
  var h = crop.height.round();
  if (x + w > image.width) w = image.width - x;
  if (y + h > image.height) h = image.height - y;
  if (w < 8 || h < 8) {
    debugPrint('[crop] rect too small, fallback full image');
    return source;
  }

  final cropped = img.copyCrop(image, x: x, y: y, width: w, height: h);
  final dir = await getTemporaryDirectory();
  final out = File(
    p.join(dir.path, 'shitu_crop_${DateTime.now().millisecondsSinceEpoch}.jpg'),
  );
  await out.writeAsBytes(img.encodeJpg(cropped, quality: 90), flush: true);
  debugPrint('[crop] ${image.width}x${image.height} → ${w}x$h → ${out.path}');
  return out;
}
