import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/services/api_client.dart';

class CatalogPage {
  const CatalogPage({
    required this.category,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.items,
  });

  final RecognizeCategory category;
  final int page;
  final int pageSize;
  final int total;
  final List<ExploreItem> items;

  bool get hasMore => page * pageSize < total;
}

class CatalogApi {
  CatalogApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  static String emojiFor(RecognizeCategory category) {
    switch (category) {
      case RecognizeCategory.animal:
        return '🐾';
      case RecognizeCategory.plant:
        return '🌿';
      case RecognizeCategory.transport:
        return '🚌';
    }
  }

  Future<CatalogPage> list({
    required RecognizeCategory category,
    int page = 1,
    int pageSize = 30,
    String? q,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final params = <String, String>{
      'category': category.apiValue,
      'page': '$page',
      'page_size': '$pageSize',
    };
    final query = (q ?? '').trim();
    if (query.isNotEmpty) params['q'] = query;

    final uri = Uri.parse('$baseUrl/v1/catalog').replace(queryParameters: params);
    debugPrint('[CatalogApi] GET $uri');
    final resp = await http.get(uri).timeout(const Duration(seconds: 20));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        '目录加载失败（${resp.statusCode}）：${ApiClient.detailFromBody(resp.body)}',
      );
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawItems = (map['items'] as List<dynamic>? ?? const []);
    final items = <ExploreItem>[];
    for (final raw in rawItems) {
      if (raw is! Map<String, dynamic>) continue;
      final item = _toExploreItem(raw, category);
      if (item != null) items.add(item);
    }
    return CatalogPage(
      category: category,
      page: (map['page'] as num?)?.toInt() ?? page,
      pageSize: (map['page_size'] as num?)?.toInt() ?? pageSize,
      total: (map['total'] as num?)?.toInt() ?? items.length,
      items: items,
    );
  }

  Future<ExploreItem> getById(int catalogId, {bool enrich = true}) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/catalog/$catalogId').replace(
      queryParameters: {'enrich': enrich ? 'true' : 'false'},
    );
    debugPrint('[CatalogApi] GET $uri');
    final resp = await http.get(uri).timeout(const Duration(seconds: 25));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        '目录详情失败（${resp.statusCode}）：${ApiClient.detailFromBody(resp.body)}',
      );
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final item = _toExploreItem(map, RecognizeCategory.animal);
    if (item == null) {
      throw ApiException('目录详情为空');
    }
    return item;
  }

  ExploreItem? _toExploreItem(Map<String, dynamic> json, RecognizeCategory fallback) {
    final name = (json['name'] as String? ?? '').trim();
    if (name.isEmpty) return null;
    final catRaw = (json['category'] as String? ?? '').trim();
    final category = RecognizeCategory.values.firstWhere(
      (c) => c.apiValue == catRaw,
      orElse: () => fallback,
    );
    final id = (json['candidate_id'] as String? ?? '').trim();
    final one = (json['one_liner'] as String? ?? '').trim();
    final desc = (json['description'] as String? ?? '').trim();
    final imageUrl = (json['image_url'] as String? ?? '').trim();
    final baikeUrl = (json['baike_url'] as String? ?? '').trim();
    final catalogId = (json['id'] as num?)?.toInt();
    return ExploreItem(
      id: id.isEmpty ? 'catalog:$catalogId' : id,
      name: name,
      oneLiner: one.isEmpty ? '点进去了解一下～' : one,
      emoji: emojiFor(category),
      category: category,
      description: desc.isEmpty ? '关于「$name」，我们以后会讲更多……' : desc,
      imageUrl: imageUrl,
      baikeUrl: baikeUrl,
      catalogId: catalogId,
    );
  }
}
