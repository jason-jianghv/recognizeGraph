import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/state/voice_preference_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

/// 语音偏好修改：A 儿童 / B 男老师 / C 女老师
class VoicePreferenceScreen extends StatelessWidget {
  const VoicePreferenceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final voice = context.watch<VoicePreferenceState>();
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leadingWidth: 64,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: SoftBackButton(),
        ),
        title: const Text('语音偏好修改'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          const Text(
            '选一个好听的声音，听介绍时会用它来播报哦',
            style: TextStyle(
              fontSize: 15,
              color: AppTokens.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          for (final meta in VoiceProfiles.all) ...[
            _ProfileCard(
              meta: meta,
              selected: voice.profile == meta.id,
              onTap: () => voice.setProfile(meta.id),
            ),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  final VoiceProfileMeta meta;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? AppTokens.primary : AppTokens.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppTokens.primarySoft : const Color(0xFFF5F0EC),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  meta.id == VoiceProfileId.a
                      ? Icons.child_care_rounded
                      : meta.id == VoiceProfileId.b
                          ? Icons.man_rounded
                          : Icons.woman_rounded,
                  color: selected ? AppTokens.primary : AppTokens.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      meta.subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTokens.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: selected ? AppTokens.primary : AppTokens.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
