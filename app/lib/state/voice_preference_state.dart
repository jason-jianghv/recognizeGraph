import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 语音偏好：A 儿童活泼 / B 男老师 / C 女老师
enum VoiceProfileId {
  a,
  b,
  c;

  String get apiValue {
    switch (this) {
      case VoiceProfileId.a:
        return 'a';
      case VoiceProfileId.b:
        return 'b';
      case VoiceProfileId.c:
        return 'c';
    }
  }

  static VoiceProfileId fromApi(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'b':
        return VoiceProfileId.b;
      case 'c':
        return VoiceProfileId.c;
      case 'a':
      default:
        return VoiceProfileId.a;
    }
  }
}

class VoiceProfileMeta {
  const VoiceProfileMeta({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final VoiceProfileId id;
  final String title;
  final String subtitle;
}

abstract final class VoiceProfiles {
  static const all = <VoiceProfileMeta>[
    VoiceProfileMeta(
      id: VoiceProfileId.a,
      title: '小朋友（约3岁）',
      subtitle: '偏慢语速 · 情绪活泼 · 音量/音调中等',
    ),
    VoiceProfileMeta(
      id: VoiceProfileId.b,
      title: '男老师',
      subtitle: '中等语速 · 音量/音调中等',
    ),
    VoiceProfileMeta(
      id: VoiceProfileId.c,
      title: '女老师',
      subtitle: '中等语速 · 音量/音调中等',
    ),
  ];

  static VoiceProfileMeta metaOf(VoiceProfileId id) {
    return all.firstWhere((e) => e.id == id, orElse: () => all.first);
  }
}

class VoicePreferenceState extends ChangeNotifier {
  static const _kProfile = 'shitu_voice_profile';

  VoiceProfileId profile = VoiceProfileId.a;
  bool ready = false;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    profile = VoiceProfileId.fromApi(prefs.getString(_kProfile));
    ready = true;
    notifyListeners();
  }

  Future<void> setProfile(VoiceProfileId id) async {
    if (profile == id) return;
    profile = id;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kProfile, id.apiValue);
  }
}
