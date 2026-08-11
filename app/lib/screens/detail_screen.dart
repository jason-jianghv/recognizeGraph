import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class DetailScreen extends StatelessWidget {
  const DetailScreen({
    super.key,
    required this.name,
    required this.oneLiner,
    required this.description,
    this.emoji,
    this.networkImage,
    this.localImage,
    this.showPlayer = false,
  });

  final String name;
  final String oneLiner;
  final String description;
  final String? emoji;
  final String? networkImage;
  final File? localImage;
  final bool showPlayer;

  factory DetailScreen.fromExplore(ExploreItem item) {
    return DetailScreen(
      name: item.name,
      oneLiner: item.oneLiner,
      description: item.description,
      emoji: item.emoji,
    );
  }

  factory DetailScreen.fromCandidate(
    RecognizeCandidate c, {
    File? localImage,
  }) {
    final desc = c.description.trim();
    // 名字下：完整百科描述（非截断 one_liner）
    // 「你可能听过」：暂无口语素材，先占位
    return DetailScreen(
      name: c.name,
      oneLiner: desc.isEmpty
          ? (c.oneLiner.trim().isEmpty ? '可能是「${c.name}」' : c.oneLiner)
          : desc,
      description: '关于「${c.name}」，我们以后会讲更多……',
      networkImage: c.imageUrl.isEmpty ? null : c.imageUrl,
      localImage: localImage,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  backgroundColor: Colors.white,
                  leadingWidth: 64,
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SoftBackButton(),
                    ),
                  ),
                  expandedHeight: 280,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _Hero(
                      emoji: emoji,
                      networkImage: networkImage,
                      localImage: localImage,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 120),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          oneLiner,
                          style: const TextStyle(
                            fontSize: 17,
                            color: AppTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '你可能听过',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: const TextStyle(
                            fontSize: 16,
                            height: 1.55,
                            color: AppTokens.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppTokens.borderSubtle)),
              ),
              child: showPlayer
                  ? const _PlayerBar()
                  : PrimaryPillButton(
                      label: '听一听介绍',
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('语音播报下一期再接，先看看文字介绍吧～')),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({this.emoji, this.networkImage, this.localImage});

  final String? emoji;
  final String? networkImage;
  final File? localImage;

  @override
  Widget build(BuildContext context) {
    if (localImage != null) {
      return Image.file(localImage!, fit: BoxFit.cover);
    }
    if (networkImage != null && networkImage!.isNotEmpty) {
      return Image.network(
        networkImage!,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) => _emojiFallback(),
      );
    }
    return _emojiFallback();
  }

  Widget _emojiFallback() {
    return ColoredBox(
      color: AppTokens.primarySoft,
      child: Center(
        child: Text(emoji ?? '🔍', style: const TextStyle(fontSize: 72)),
      ),
    );
  }
}

class _PlayerBar extends StatelessWidget {
  const _PlayerBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filled(
          onPressed: () {},
          style: IconButton.styleFrom(backgroundColor: AppTokens.primary),
          icon: const Icon(Icons.play_arrow_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: const LinearProgressIndicator(
              value: 0.35,
              minHeight: 8,
              color: AppTokens.primary,
              backgroundColor: AppTokens.primarySoft,
            ),
          ),
        ),
      ],
    );
  }
}
