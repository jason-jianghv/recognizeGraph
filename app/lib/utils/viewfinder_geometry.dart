import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

/// 拍照 / 相册对准页共用的取景框几何（相对预览区）。
abstract final class ViewfinderGeometry {
  /// 左右边距
  static const double sideInset = 60;

  /// SafeArea 顶栏（返回/闪光）下方到「可用取景区」顶
  static const double topBelowChrome = 80;

  /// 预览区底边到「可用取景区」底
  static const double bottomInset = 56;

  /// 高宽比（按宽度定尺寸，避免拍照/相册底栏高度不同导致框大小不一致）
  static const double heightOverWidth = 1.15;

  /// 取景框在「整块预览区」中的矩形（含状态栏占位，与 Camera 预览 Stack 对齐）
  /// 宽度 = 屏宽 - 2×sideInset；高度 = 宽度 × [heightOverWidth]，在可用区内垂直居中。
  static Rect rectInPreview(Size previewSize, double topSafeInset) {
    final left = sideInset;
    final width = math.max(48.0, previewSize.width - 2 * sideInset);
    final right = left + width;

    var height = width * heightOverWidth;
    final availTop = topSafeInset + topBelowChrome;
    final availBottom = math.max(availTop + 48, previewSize.height - bottomInset);
    final availHeight = availBottom - availTop;
    if (height > availHeight) {
      height = availHeight;
    }

    final top = availTop + (availHeight - height) / 2;
    final bottom = top + height;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  /// BoxFit.cover：把视口上的矩形映射到图片像素坐标（未 clamp）
  static Rect mapCoverRectToImage({
    required Size viewport,
    required Size imageSize,
    required Rect viewportRect,
  }) {
    final scale = math.max(
      viewport.width / imageSize.width,
      viewport.height / imageSize.height,
    );
    final dispW = imageSize.width * scale;
    final dispH = imageSize.height * scale;
    final dx = (viewport.width - dispW) / 2;
    final dy = (viewport.height - dispH) / 2;

    double toImgX(double x) => (x - dx) / scale;
    double toImgY(double y) => (y - dy) / scale;

    return Rect.fromLTRB(
      toImgX(viewportRect.left),
      toImgY(viewportRect.top),
      toImgX(viewportRect.right),
      toImgY(viewportRect.bottom),
    );
  }

  /// 交互平移缩放后：视口矩形 → 图片像素
  static Rect mapTransformedRectToImage({
    required Size viewport,
    required Size imageSize,
    required Rect viewportRect,
    required double userScale,
    required Offset offset,
  }) {
    final base = math.max(
      viewport.width / imageSize.width,
      viewport.height / imageSize.height,
    );
    final scale = base * userScale.clamp(1.0, 8.0);
    final dispW = imageSize.width * scale;
    final dispH = imageSize.height * scale;
    final left = (viewport.width - dispW) / 2 + offset.dx;
    final top = (viewport.height - dispH) / 2 + offset.dy;

    double toImgX(double x) => (x - left) / scale;
    double toImgY(double y) => (y - top) / scale;

    return Rect.fromLTRB(
      toImgX(viewportRect.left),
      toImgY(viewportRect.top),
      toImgX(viewportRect.right),
      toImgY(viewportRect.bottom),
    );
  }

  static Rect clampToImage(Rect r, Size imageSize) {
    final w = imageSize.width;
    final h = imageSize.height;
    var left = r.left.clamp(0, w);
    var top = r.top.clamp(0, h);
    var right = r.right.clamp(0, w);
    var bottom = r.bottom.clamp(0, h);
    if (right <= left) {
      left = 0;
      right = w;
    }
    if (bottom <= top) {
      top = 0;
      bottom = h;
    }
    return Rect.fromLTRB(
      left.toDouble(),
      top.toDouble(),
      right.toDouble(),
      bottom.toDouble(),
    );
  }
}
