import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/services/api_client.dart';

class RecognizeApiException implements Exception {
  RecognizeApiException(this.message);
  final String message;

  @override
  String toString() => message;
}

class RecognizeApi {
  RecognizeApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  static const _localNetwork = MethodChannel('com.shitu/local_network');

  /// iOS：先走原生 URLSession（会弹「本地网络」并等待授权），再让 Dart HTTP 工作。
  Future<void> _ensureLocalNetworkAccess(Uri healthUri) async {
    if (kIsWeb || !Platform.isIOS) return;

    debugPrint('[RecognizeApi] native probe $healthUri');
    try {
      final raw = await _localNetwork.invokeMethod<dynamic>('probe', {
        'url': healthUri.toString(),
      });
      debugPrint('[RecognizeApi] native probe result=$raw');
      if (raw is Map) {
        final code = raw['statusCode'];
        if (code is int && code != 200) {
          throw RecognizeApiException('服务异常（$code）：${raw['body']}');
        }
      }
    } on PlatformException catch (e) {
      throw RecognizeApiException(
        '手机连不上 $baseUrl（原生探测失败）。'
        '请删掉 App 重装，首次弹出「本地网络」时点允许；'
        '或到 设置→识图→本地网络 关掉再打开。详情：${e.message} ${e.details}',
      );
    }
  }

  Future<void> ping() async {
    final uri = Uri.parse('$baseUrl/health');
    debugPrint('[RecognizeApi] GET $uri');

    // 真机 iOS：必须先原生探测，否则 Dart 常直接 errno=65 且不弹权限窗
    await _ensureLocalNetworkAccess(uri);

    try {
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      debugPrint('[RecognizeApi] health=${resp.statusCode} ${resp.body}');
      if (resp.statusCode != 200) {
        throw RecognizeApiException('服务异常（${resp.statusCode}）：${resp.body}');
      }
    } on SocketException catch (e) {
      throw RecognizeApiException(
        '手机连不上 $baseUrl（SocketException）。请检查：同一 Wi‑Fi、后端 --host 0.0.0.0、系统设置里允许「本地网络」。详情：$e',
      );
    } on HandshakeException catch (e) {
      throw RecognizeApiException('HTTPS/证书异常：$e');
    } catch (e) {
      if (e is RecognizeApiException) rethrow;
      throw RecognizeApiException('探测服务失败：$e');
    }
  }

  Future<RecognizeResult> recognize({
    required RecognizeCategory category,
    required File imageFile,
  }) async {
    final uri = Uri.parse('$baseUrl/v1/recognize');
    debugPrint('[RecognizeApi] POST $uri category=${category.apiValue} file=${imageFile.path}');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['category'] = category.apiValue
        ..files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );

      final streamed = await request.send().timeout(const Duration(seconds: 60));
      final body = await streamed.stream.bytesToString();
      debugPrint(
        '[RecognizeApi] status=${streamed.statusCode} body=${body.substring(0, body.length > 300 ? 300 : body.length)}',
      );

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        String detail = body;
        try {
          final map = jsonDecode(body) as Map<String, dynamic>;
          detail = map['detail']?.toString() ?? body;
        } catch (_) {}
        throw RecognizeApiException('识别失败（${streamed.statusCode}）：$detail');
      }

      final map = jsonDecode(body) as Map<String, dynamic>;
      final list = (map['candidates'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map(RecognizeCandidate.fromJson)
          .toList();

      return RecognizeResult(category: category, candidates: list);
    } on RecognizeApiException {
      rethrow;
    } on SocketException catch (e) {
      debugPrint('[RecognizeApi] SocketException: $e');
      throw RecognizeApiException(
        '连不上电脑服务（$baseUrl）。请确认同一 Wi‑Fi，且后端用 --host 0.0.0.0 启动。详情：$e',
      );
    } on HttpException catch (e) {
      debugPrint('[RecognizeApi] HttpException: $e');
      throw RecognizeApiException('网络异常：$e');
    } catch (e, st) {
      debugPrint('[RecognizeApi] error: $e\n$st');
      throw RecognizeApiException('识别请求异常：$e');
    }
  }

  /// 「以上都不是」等识别反馈上报
  Future<void> reportFeedback({
    required RecognizeCategory category,
    required List<RecognizeCandidate> shownCandidates,
    File? imageFile,
    String reason = 'none_of_above',
    String note = '',
  }) async {
    final uri = Uri.parse('$baseUrl/v1/feedback');
    debugPrint('[RecognizeApi] POST $uri reason=$reason');
    try {
      final request = http.MultipartRequest('POST', uri)
        ..fields['category'] = category.apiValue
        ..fields['reason'] = reason
        ..fields['note'] = note
        ..fields['candidate_names'] = jsonEncode(
          shownCandidates.map((c) => c.name).toList(),
        )
        ..fields['candidate_ids'] = jsonEncode(
          shownCandidates.map((c) => c.id).toList(),
        );

      if (imageFile != null) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'image',
            imageFile.path,
            contentType: MediaType('image', 'jpeg'),
          ),
        );
      }

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final body = await streamed.stream.bytesToString();
      debugPrint('[RecognizeApi] feedback status=${streamed.statusCode} $body');

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        String detail = body;
        try {
          final map = jsonDecode(body) as Map<String, dynamic>;
          detail = map['detail']?.toString() ?? body;
        } catch (_) {}
        throw RecognizeApiException('反馈失败（${streamed.statusCode}）：$detail');
      }
    } on RecognizeApiException {
      rethrow;
    } on SocketException catch (e) {
      throw RecognizeApiException('连不上电脑服务，反馈没发出去：$e');
    } catch (e) {
      if (e is RecognizeApiException) rethrow;
      throw RecognizeApiException('反馈请求异常：$e');
    }
  }
}
