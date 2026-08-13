import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/auth_api.dart';
import 'package:shitu_app/utils/level_rules.dart';

class SessionState extends ChangeNotifier {
  static const _kToken = 'shitu_token';
  static const _kPhone = 'shitu_phone';
  static const _kNickname = 'shitu_nickname';
  static const _kAvatar = 'shitu_avatar';
  static const _kLearnCount = 'shitu_learn_count';

  bool loggedIn = false;
  String nickname = '小小探索家';
  String? phone;
  String? token;
  String avatarUrl = '';
  int learnCount = 0;
  bool ready = false;

  int get level => LevelRules.levelFromLearnCount(learnCount);

  String get levelHint => LevelRules.hint(learnCount);

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final t = prefs.getString(_kToken);
    if (t == null || t.isEmpty) {
      ready = true;
      notifyListeners();
      return;
    }
    token = t;
    phone = prefs.getString(_kPhone);
    nickname = prefs.getString(_kNickname) ?? '小小探索家';
    avatarUrl = prefs.getString(_kAvatar) ?? '';
    learnCount = prefs.getInt(_kLearnCount) ?? 0;
    loggedIn = true;
    ready = true;
    notifyListeners();

    try {
      final me = await AuthApi().fetchMe(t);
      await applyProfile(
        nickname: me.nickname,
        avatarUrl: me.avatarUrl,
        learnCount: me.learnCount,
        phone: me.phone,
      );
    } catch (e) {
      debugPrint('[SessionState] refresh me failed: $e');
      if (e is ApiException && e.message.contains('登录已失效')) {
        await logout(remote: false);
      }
    }
  }

  Future<void> login({
    required String token,
    required String phone,
    String? nickname,
    String avatarUrl = '',
    int learnCount = 0,
    int level = 1,
  }) async {
    loggedIn = true;
    this.token = token;
    this.phone = phone;
    final name = (nickname ?? '').trim();
    this.nickname = name.isNotEmpty ? name : '小小探索家';
    this.avatarUrl = avatarUrl;
    this.learnCount = learnCount;
    await _persist();
    notifyListeners();
  }

  Future<void> applyProfile({
    String? nickname,
    String? avatarUrl,
    int? learnCount,
    int? level,
    String? phone,
  }) async {
    if (nickname != null && nickname.trim().isNotEmpty) {
      this.nickname = nickname.trim();
    }
    if (avatarUrl != null) this.avatarUrl = avatarUrl;
    if (learnCount != null) this.learnCount = learnCount;
    if (phone != null) this.phone = phone;
    await _persist();
    notifyListeners();
  }

  Future<void> logout({bool remote = true}) async {
    final t = token;
    loggedIn = false;
    nickname = '小小探索家';
    phone = null;
    token = null;
    avatarUrl = '';
    learnCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
    await prefs.remove(_kPhone);
    await prefs.remove(_kNickname);
    await prefs.remove(_kAvatar);
    await prefs.remove(_kLearnCount);
    await prefs.remove('shitu_level');
    notifyListeners();
    if (remote && t != null && t.isNotEmpty) {
      try {
        await AuthApi().logout(t);
      } catch (_) {}
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null) return;
    await prefs.setString(_kToken, token!);
    await prefs.setString(_kPhone, phone ?? '');
    await prefs.setString(_kNickname, nickname);
    await prefs.setString(_kAvatar, avatarUrl);
    await prefs.setInt(_kLearnCount, learnCount);
  }
}
