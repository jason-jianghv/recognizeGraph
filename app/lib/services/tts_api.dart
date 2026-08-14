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

  /// 请求后端合成 MP3。
  /// - 默认：`name` + `oneLiner` 拼播报稿
  /// - 若传 [text]：优先作为完整播报稿（如「中文名。English。」）
  Future<File> synthesizeToFile({
    required String name,
    required String oneLiner,
    String voiceProfile = 'a',
    String? text,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/tts');
    final body = <String, dynamic>{
      'name': name,
      'one_liner': oneLiner,
      'voice_profile': voiceProfile,
    };
    final script = text?.trim() ?? '';
    if (script.isNotEmpty) {
      body['text'] = script;
    }
    final resp = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json; charset=utf-8'},
          body: jsonEncode(body),
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
