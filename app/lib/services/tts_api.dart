import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shitu_app/services/api_client.dart';

class TtsApi {
  TtsApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  /// 请求后端合成「名字 + 简介」MP3（超长已在服务端分段拼接）。
  Future<File> synthesizeToFile({
    required String name,
    required String oneLiner,
    String voiceProfile = 'a',
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/tts');
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode({
            'name': name,
            'one_liner': oneLiner,
            'voice_profile': voiceProfile,
          }),
        )
        .timeout(const Duration(seconds: 45));

    debugPrint('[TtsApi] ${resp.statusCode} bytes=${resp.bodyBytes.length}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(ApiClient.detailFromBody(resp.body));
    }
    final ctype = resp.headers['content-type'] ?? '';
    if (!ctype.contains('audio') && resp.bodyBytes.length < 64) {
      throw ApiException(ApiClient.detailFromBody(resp.body));
    }
    return _writeTempMp3(resp.bodyBytes);
  }

  Future<File> _writeTempMp3(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      p.join(dir.path, 'shitu_tts_${DateTime.now().millisecondsSinceEpoch}.mp3'),
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }
}
