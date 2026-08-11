import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/screens/detail_screen.dart';
import 'package:shitu_app/screens/login_screen.dart';
import 'package:shitu_app/screens/settings_screen.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class SpaceScreen extends StatelessWidget {
  const SpaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      appBar: AppBar(
        title: const Text('空间'),
        backgroundColor: Colors.white,
        actions: [
          if (session.loggedIn)
            IconButton(
              tooltip: '设置',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                );
              },
              icon: const Icon(Icons.tune_rounded),
            ),
        ],
      ),
      body: session.loggedIn ? const _LoggedInBody() : const _LoggedOutBody(),
    );
  }
}

class _LoggedOutBody extends StatelessWidget {
  const _LoggedOutBody();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 120),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 112,
            height: 112,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppTokens.primarySoft,
              shape: BoxShape.circle,
            ),
            child: const Text('🙂', style: TextStyle(fontSize: 52)),
          ),
          const SizedBox(height: 20),
          const Text(
            '登录后，这里会记下你认识的小伙伴',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            '也可以先去探索逛逛～',
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 28),
          PrimaryPillButton(
            label: '去登录',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
              );
            },
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}

class _LoggedInBody extends StatelessWidget {
  const _LoggedInBody();

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppTokens.primarySoft,
                  shape: BoxShape.circle,
                ),
                child: const Text('🧒', style: TextStyle(fontSize: 32)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.nickname,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '小宝贝，大世界',
                      style: TextStyle(color: AppTokens.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTokens.level.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'Lv 5',
                  style: TextStyle(
                    color: AppTokens.level,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          '拍照历史',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          '2026年08月',
          style: TextStyle(color: AppTokens.textSecondary),
        ),
        const SizedBox(height: 10),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: [
            for (final item in const [
              ('🐰', '小兔子'),
              ('🌻', '向日葵'),
              ('🚌', '校车'),
            ])
              _HistoryTile(
                emoji: item.$1,
                name: item.$2,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DetailScreen(
                        name: item.$2,
                        oneLiner: '你认识过的小伙伴',
                        description: '这是你拍照认识过的「${item.$2}」。可以再去拍一张，认识更多新朋友～',
                        emoji: item.$1,
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _HistoryTile extends StatefulWidget {
  const _HistoryTile({
    required this.emoji,
    required this.name,
    required this.onTap,
  });

  final String emoji;
  final String name;
  final VoidCallback onTap;

  @override
  State<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends State<_HistoryTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onLongPressStart: (_) => setState(() => _pressed = true),
      onLongPressEnd: (_) => setState(() => _pressed = false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(
              color: AppTokens.primarySoft,
              child: Center(
                child: Text(widget.emoji, style: const TextStyle(fontSize: 36)),
              ),
            ),
            if (_pressed)
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: double.infinity,
                  color: Colors.black54,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    widget.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
