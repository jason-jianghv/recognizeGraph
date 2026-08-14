import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shitu_app/services/api_client.dart';

class NameEnResult {
  const NameEnResult({
    required this.nameZh,
    required this.nameEn,
    required this.source,
    required this.speak,
  });

  final String nameZh;
  final String nameEn;
  final String source;
  final String speak;

  bool get hasEnglish => nameEn.trim().isNotEmpty;

  factory NameEnResult.fromJson(Map<String, dynamic> json) {
    return NameEnResult(
      nameZh: json['name_zh'] as String? ?? '',
      nameEn: json['name_en'] as String? ?? '',
      source: json['source'] as String? ?? '',
      speak: json['speak'] as String? ?? '',
    );
  }
}

class NameEnApi {
  NameEnApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  Future<NameEnResult> resolve(
    String name, {
    bool allowTranslate = true,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/name-en').replace(
      queryParameters: {
        'name': name,
        'allow_translate': allowTranslate ? 'true' : 'false',
      },
    );
    final resp = await http.get(uri).timeout(const Duration(seconds: 20));
    debugPrint('[NameEnApi] ${resp.statusCode} ${resp.body}');
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(ApiClient.detailFromBody(resp.body));
    }
    final map = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return NameEnResult.fromJson(map);
  }
}
