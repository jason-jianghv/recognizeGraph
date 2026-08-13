import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shitu_app/services/api_client.dart';

class SmsCodeResult {
  const SmsCodeResult({
    required this.phone,
    required this.code,
    required this.expiresIn,
    required this.resendAfter,
  });

  final String phone;
  final String code;
  final int expiresIn;
  final int resendAfter;

  factory SmsCodeResult.fromJson(Map<String, dynamic> json) {
    return SmsCodeResult(
      phone: json['phone'] as String? ?? '',
      code: json['code'] as String? ?? '',
      expiresIn: (json['expires_in'] as num?)?.toInt() ?? 300,
      resendAfter: (json['resend_after'] as num?)?.toInt() ?? 60,
    );
  }
}

class LoginResult {
  const LoginResult({
    required this.token,
    required this.phone,
    required this.nickname,
    this.avatarUrl = '',
    this.learnCount = 0,
    this.level = 1,
  });

  final String token;
  final String phone;
  final String nickname;
  final String avatarUrl;
  final int learnCount;
  final int level;

  factory LoginResult.fromJson(Map<String, dynamic> json) {
    return LoginResult(
      token: json['token'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      learnCount: (json['learn_count'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
    );
  }
}

class MeResult {
  const MeResult({
    required this.phone,
    required this.nickname,
    required this.avatarUrl,
    required this.learnCount,
    required this.level,
  });

  final String phone;
  final String nickname;
  final String avatarUrl;
  final int learnCount;
  final int level;

  factory MeResult.fromJson(Map<String, dynamic> json) {
    return MeResult(
      phone: json['phone'] as String? ?? '',
      nickname: json['nickname'] as String? ?? '',
      avatarUrl: json['avatar_url'] as String? ?? '',
      learnCount: (json['learn_count'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 1,
    );
  }
}

class AuthApi {
  AuthApi({String? baseUrl}) : baseUrl = baseUrl ?? ApiClient.defaultBaseUrl();

  final String baseUrl;

  Future<SmsCodeResult> requestSmsCode(String phone) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/auth/sms-code');
    debugPrint('[AuthApi] POST $uri phone=$phone');
    try {
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone}),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[AuthApi] sms-code ${resp.statusCode} ${resp.body}');
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ApiException(ApiClient.detailFromBody(resp.body));
      }
      return SmsCodeResult.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>,
      );
    } on ApiException {
      rethrow;
    } on SocketException catch (e) {
      throw ApiException('连不上电脑服务（$baseUrl）：$e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('获取验证码失败：$e');
    }
  }

  Future<LoginResult> login({
    required String phone,
    required String code,
  }) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/auth/login');
    debugPrint('[AuthApi] POST $uri phone=$phone');
    try {
      final resp = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'phone': phone, 'code': code}),
          )
          .timeout(const Duration(seconds: 15));
      debugPrint('[AuthApi] login ${resp.statusCode} ${resp.body}');
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw ApiException(ApiClient.detailFromBody(resp.body));
      }
      return LoginResult.fromJson(
        jsonDecode(resp.body) as Map<String, dynamic>,
      );
    } on ApiException {
      rethrow;
    } on SocketException catch (e) {
      throw ApiException('连不上电脑服务（$baseUrl）：$e');
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('登录失败：$e');
    }
  }

  Future<MeResult> fetchMe(String token) async {
    await ApiClient.ensureLocalNetworkAccess(baseUrl);
    final uri = Uri.parse('$baseUrl/v1/me');
    final resp = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode == 401) {
      throw ApiException('登录已失效，请重新登录');
    }
    if (resp.statusCode < 200 || resp.statusCode >= 300) {
      throw ApiException(ApiClient.detailFromBody(resp.body));
    }
    return MeResult.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  Future<void> logout(String token) async {
    try {
      await ApiClient.ensureLocalNetworkAccess(baseUrl);
      final uri = Uri.parse('$baseUrl/v1/auth/logout');
      await http
          .post(uri, headers: {'Authorization': 'Bearer $token'})
          .timeout(const Duration(seconds: 8));
    } catch (_) {}
  }
}
