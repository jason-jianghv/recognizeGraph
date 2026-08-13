import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 共享后端地址与 iOS 本地网络探测。
abstract final class ApiClient {
  static const _localNetwork = MethodChannel('com.shitu/local_network');

  /// 真机调试：改成你电脑的局域网地址（必须带 http:// 和端口）
  static const deviceLanBaseUrl = 'http://10.10.211.141:8000';

  static bool get _isIosSimulator {
    if (kIsWeb || !Platform.isIOS) return false;
    return Platform.environment.containsKey('SIMULATOR_DEVICE_NAME') ||
        Platform.environment.containsKey('SIMULATOR_HOST_HOME');
  }

  static String defaultBaseUrl() {
    if (_isIosSimulator) {
      return 'http://127.0.0.1:8000';
    }
    if (!kIsWeb && Platform.isAndroid) {
      return deviceLanBaseUrl;
    }
    return deviceLanBaseUrl;
  }

  static Future<void> ensureLocalNetworkAccess(String baseUrl) async {
    if (kIsWeb || !Platform.isIOS) return;

    final healthUri = Uri.parse('$baseUrl/health');
    debugPrint('[ApiClient] native probe $healthUri');
    try {
      final raw = await _localNetwork.invokeMethod<dynamic>('probe', {
        'url': healthUri.toString(),
      });
      debugPrint('[ApiClient] native probe result=$raw');
      if (raw is Map) {
        final code = raw['statusCode'];
        if (code is int && code != 200) {
          throw ApiException('服务异常（$code）：${raw['body']}');
        }
      }
    } on PlatformException catch (e) {
      throw ApiException(
        '手机连不上 $baseUrl（原生探测失败）。'
        '请删掉 App 重装，首次弹出「本地网络」时点允许；'
        '或到 设置→识图→本地网络 关掉再打开。详情：${e.message} ${e.details}',
      );
    }
  }

  static String detailFromBody(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      final detail = map['detail'];
      if (detail is String) return detail;
      if (detail != null) return detail.toString();
    } catch (_) {}
    return body;
  }
}

class ApiException implements Exception {
  ApiException(this.message);
  final String message;

  @override
  String toString() => message;
}
