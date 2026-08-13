import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shitu_app/services/api_client.dart';

class HistoryMonth {
  const HistoryMonth({required this.yearMonth, required this.count});
  final String yearMonth;
  final int count;

  factory HistoryMonth.fromJson(Map<String, dynamic> json) {
    return HistoryMonth(
      yearMonth: json['year_month'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }

  /// 2026-08 → 2026年08月
  String get label {
    final parts = yearMonth.split('-');
    if (parts.length != 2) return yearMonth;
    return '${parts[0]}年${parts[1]}月';
  }
}

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.name,
    required this.category,
    required this.thumbUrl,
    required this.imageUrl,
    required this.yearMonth,
    this.oneLiner = '',
    this.description = '',
    this.baikeUrl = '',
  });

  final int id;
  final String name;
  final String category;
  final String thumbUrl;
  final String imageUrl;
  final String yearMonth;
  final String oneLiner;
  final String description;
  final String baikeUrl;

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      thumbUrl: json['thumb_url'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      yearMonth: json['year_month'] as String? ?? '',
      oneLiner: json['one_liner'] as String? ?? '',
      description: json['description'] as String? ?? '',
      baikeUrl: json['baike_url'] as String? ?? '',
    );
  }
}

class HistoryPage {
  const HistoryPage({
    required this.yearMonth,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.items,
  });

  final String yearMonth;
  final int page;
  final int pageSize;
  final int total;
  final List<HistoryItem> items;

  bool get hasMore => page * pageSize < total;

  factory HistoryPage.fromJson(Map<String, dynamic> json) {
    final list = (json['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(HistoryItem.fromJson)
        .toList();
    return HistoryPage(
      yearMonth: json['year_month'] as String? ?? '',
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ?? 21,
      total: (json['total'] as num?)?.toInt() ?? 0,
      items: list,
    );
  }
}

class RecordLearnResult {
  const RecordLearnResult({
    required this.id,
    required this.learnCount,
    required this.level,
    required this.thumbUrl,
  });

  final int id;
  final int learnCount;
  final int level;
  final String thumbUrl;

  factory RecordLearnResult.fromJson(Map<String, dynamic> json) {
    return RecordLearnResult(
      id: (json['id'] as num?)?.toInt() ?? 0,
      learnCount: (json['learn_count'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
      thumbUrl: json['thumb_url'] as String? ?? '',
    );
  }
}

class HistoryApi {
  HistoryApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  Uri _abs(String pathOrUrl) {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      return Uri.parse(pathOrUrl);
    }
    if (pathOrUrl.startsWith('/')) {
      return Uri.parse('$baseUrl$pathOrUrl');
    }
    return Uri.parse('$baseUrl/$pathOrUrl');
  }

  String absoluteMediaUrl(String pathOrUrl) {
    if (pathOrUrl.isEmpty) return '';
    return _abs(pathOrUrl).toString();
  }

  Future<List<HistoryMonth>> fetchMonths(String token) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/history/months');
    final resp = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(ApiClient.detailFromBody(resp.body));
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    return (map['months'] as List? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(HistoryMonth.fromJson)
        .toList();
  }

  Future<HistoryPage> fetchMonthPage({
    required String token,
    required String month,
    int page = 1,
    int pageSize = 21,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/history').replace(
      queryParameters: {
        'month': month,
        'page': '$page',
        'page_size': '$pageSize',
      },
    );
    final resp = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(ApiClient.detailFromBody(resp.body));
    }
    return HistoryPage.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<RecordLearnResult> recordLearn({
    required String token,
    required String name,
    String category = '',
    String candidateId = '',
    String baikeUrl = '',
    String imageUrl = '',
    String description = '',
    double score = 0,
    String source = 'recognize',
    File? thumbFile,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/history');
    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..fields['name'] = name
      ..fields['category'] = category
      ..fields['candidate_id'] = candidateId
      ..fields['baike_url'] = baikeUrl
      ..fields['image_url'] = imageUrl
      ..fields['description'] = description
      ..fields['score'] = score.toString()
      ..fields['source'] = source;

    if (thumbFile != null) {
      req.files.add(
        await http.MultipartFile.fromPath(
          'thumb',
          thumbFile.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      );
    }

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final body = await streamed.stream.bytesToString();
    debugPrint('[HistoryApi] record ${streamed.statusCode} $body');
    if (streamed.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录');
    }
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw ApiException(ApiClient.detailFromBody(body));
    }
    return RecordLearnResult.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}
