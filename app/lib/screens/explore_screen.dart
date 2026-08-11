import 'package:flutter/material.dart';
import 'package:shitu_app/data/explore_mock.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/screens/detail_screen.dart';
import 'package:shitu_app/screens/more_list_screen.dart';
import 'package:shitu_app/theme/tokens.dart';

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      appBar: AppBar(
        title: const Text('探索世界'),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // 对齐 Figma「主题」：主色引导两行 + 灰色副文案
          const Text(
            '举起小小的镜头，框住大大的好奇……',
            style: TextStyle(
              color: AppTokens.primary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            '每按一次快门，世界就多开一扇窗。',
            style: TextStyle(
              color: AppTokens.primary,
              fontSize: 13,
              fontWeight: FontWeight.w400,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            '今天想认识谁？点开小卡片学一学～',
            style: TextStyle(color: AppTokens.textSecondary, fontSize: 15),
          ),
          const SizedBox(height: 20),
          _CategorySection(
            title: '动物百科',
            tint: AppTokens.primarySoft,
            accent: AppTokens.categoryAnimal,
            items: exploreAnimals,
          ),
          const SizedBox(height: 16),
          _CategorySection(
            title: '植物百科',
            tint: const Color(0xFFE8F8F0),
            accent: AppTokens.categoryPlant,
            items: explorePlants,
          ),
          const SizedBox(height: 16),
          _CategorySection(
            title: '交通与建筑',
            tint: const Color(0xFFEBF2FF),
            accent: AppTokens.categoryTransport,
            items: exploreTransport,
          ),
        ],
      ),
    );
  }
}

class _CategorySection extends StatelessWidget {
  const _CategorySection({
    required this.title,
    required this.tint,
    required this.accent,
    required this.items,
  });

  final String title;
  final Color tint;
  final Color accent;
  final List<ExploreItem> items;

  static const _cardHeight = 168.0;

  @override
  Widget build(BuildContext context) {
    // 分区底色与横滑列表分层：标题区自带 padding；
    // 列表用自身 padding，避免卡片圆角被分区底色/圆角裁切挡住。
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 6, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    title,
                    style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MoreListScreen(
                          title: title,
                          items: items,
                        ),
                      ),
                    );
                  },
                  child: const Text('更多 ›'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _cardHeight + 14,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              itemCount: items.length,
              separatorBuilder: (_, index) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final item = items[i];
                return SizedBox(
                  height: _cardHeight,
                  child: _ExploreCard(
                    item: item,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DetailScreen.fromExplore(item),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ExploreCard extends StatelessWidget {
  const _ExploreCard({required this.item, required this.onTap});

  final ExploreItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 136,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTokens.primarySoft,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(item.emoji, style: const TextStyle(fontSize: 42)),
                ),
              ),
              Text(
                item.name,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppTokens.textPrimary,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Text(
                  item.oneLiner,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    color: AppTokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
