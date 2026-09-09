import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shitu_app/services/api_client.dart';

enum LeaderboardScope {
  total,
  week;

  String get apiValue => name;
}

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.rank,
    required this.userId,
    required this.nickname,
    required this.avatarUrl,
    required this.learnCount,
    required this.level,
  });

  final int rank;
  final int userId;
  final String nickname;
  final String avatarUrl;
  final int learnCount;
  final int level;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) {
    return LeaderboardEntry(
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      userId: (json['user_id'] as num?)?.toInt() ?? 0,
      nickname: (json['nickname'] as String? ?? '').trim(),
      avatarUrl: json['avatar_url'] as String? ?? '',
      learnCount: (json['learn_count'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
    );
  }
}

class LeaderboardMe {
  const LeaderboardMe({
    required this.rank,
    required this.learnCount,
    required this.nickname,
    required this.avatarUrl,
    required this.level,
    required this.inTop,
  });

  final int? rank;
  final int learnCount;
  final String nickname;
  final String avatarUrl;
  final int level;
  final bool inTop;

  factory LeaderboardMe.fromJson(Map<String, dynamic> json) {
    return LeaderboardMe(
      rank: (json['rank'] as num?)?.toInt(),
      learnCount: (json['learn_count'] as num?)?.toInt() ?? 0,
      nickname: (json['nickname'] as String? ?? '').trim(),
      avatarUrl: json['avatar_url'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 1,
      inTop: json['in_top'] as bool? ?? false,
    );
  }
}

class LeaderboardResult {
  const LeaderboardResult({
    required this.scope,
    required this.limit,
    required this.items,
    this.me,
    this.weekStart,
    this.weekEnd,
  });

  final LeaderboardScope scope;
  final int limit;
  final List<LeaderboardEntry> items;
  final LeaderboardMe? me;
  final String? weekStart;
  final String? weekEnd;
}

class LeaderboardApi {
  LeaderboardApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  /// 相对路径头像补全为可请求 URL。
  String resolveAvatarUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('/')) return '$baseUrl$u';
    return u;
  }

  Future<LeaderboardResult> fetch({
    required LeaderboardScope scope,
    String? token,
    int limit = 20,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/leaderboard').replace(
      queryParameters: {
        'scope': scope.apiValue,
        'limit': '$limit',
      },
    );
    debugPrint('[LeaderboardApi] GET $uri');
    final headers = <String, String>{};
    final t = (token ?? '').trim();
    if (t.isNotEmpty) {
      headers['Authorization'] = 'Bearer $t';
    }
    final resp = await http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(
        '排行榜加载失败（${resp.statusCode}）：${ApiClient.detailFromBody(resp.body)}',
      );
    }
    final map = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawItems = map['items'] as List<dynamic>? ?? const [];
    final items = <LeaderboardEntry>[];
    for (final raw in rawItems) {
      if (raw is Map<String, dynamic>) {
        items.add(LeaderboardEntry.fromJson(raw));
      }
    }
    LeaderboardMe? me;
    final rawMe = map['me'];
    if (rawMe is Map<String, dynamic>) {
      me = LeaderboardMe.fromJson(rawMe);
    }
    final scopeStr = map['scope'] as String? ?? scope.apiValue;
    return LeaderboardResult(
      scope: scopeStr == 'week' ? LeaderboardScope.week : LeaderboardScope.total,
      limit: (map['limit'] as num?)?.toInt() ?? limit,
      items: items,
      me: me,
      weekStart: map['week_start'] as String?,
      weekEnd: map['week_end'] as String?,
    );
  }
}
