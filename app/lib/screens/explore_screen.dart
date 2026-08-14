import 'package:flutter/material.dart';
import 'package:shitu_app/data/explore_mock.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/screens/detail_screen.dart';
import 'package:shitu_app/screens/more_list_screen.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/catalog_api.dart';
import 'package:shitu_app/theme/tokens.dart';

Future<void> openExploreMore(
  BuildContext context, {
  required String title,
  required RecognizeCategory category,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MoreListScreen(
        title: title,
        category: category,
      ),
    ),
  );
}

Future<void> openExploreDetail(BuildContext context, ExploreItem item) async {
  var resolved = item;
  final id = item.catalogId;
  final needsEnrich = id != null &&
      (item.description.trim().isEmpty ||
          item.description.contains('我们以后会讲更多') ||
          item.oneLiner.startsWith('认识一下「'));
  if (needsEnrich) {
    try {
      resolved = await CatalogApi().getById(id, enrich: true);
    } catch (_) {
      // 仍打开本地已有文案
    }
  }
  if (!context.mounted) return;
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DetailScreen.fromExplore(resolved),
    ),
  );
}

class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _api = CatalogApi();

  List<ExploreItem> _animals = exploreAnimals;
  List<ExploreItem> _plants = explorePlants;
  List<ExploreItem> _transport = exploreTransport;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.list(category: RecognizeCategory.animal, pageSize: 12),
        _api.list(category: RecognizeCategory.plant, pageSize: 12),
        _api.list(category: RecognizeCategory.transport, pageSize: 12),
      ]);
      if (!mounted) return;
      setState(() {
        if (results[0].items.isNotEmpty) _animals = results[0].items;
        if (results[1].items.isNotEmpty) _plants = results[1].items;
        if (results[2].items.isNotEmpty) _transport = results[2].items;
        _loading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '探索列表暂时打不开：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      appBar: AppBar(
        title: const Text('探索世界'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: '刷新',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
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
            if (_loading) ...[
              const SizedBox(height: 16),
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: AppTokens.primary),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                '$_error\n先用本地小卡片，连上后端后下拉刷新～',
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _CategorySection(
              title: '动物百科',
              tint: AppTokens.primarySoft,
              accent: AppTokens.categoryAnimal,
              category: RecognizeCategory.animal,
              items: _animals,
            ),
            const SizedBox(height: 16),
            _CategorySection(
              title: '植物百科',
              tint: const Color(0xFFE8F8F0),
              accent: AppTokens.categoryPlant,
              category: RecognizeCategory.plant,
              items: _plants,
            ),
            const SizedBox(height: 16),
            _CategorySection(
              title: '交通与建筑',
              tint: const Color(0xFFEBF2FF),
              accent: AppTokens.categoryTransport,
              category: RecognizeCategory.transport,
              items: _transport,
            ),
          ],
        ),
      ),
    );
  }
}

class _CategorySection extends StatefulWidget {
  const _CategorySection({
    required this.title,
    required this.tint,
    required this.accent,
    required this.category,
    required this.items,
  });

  final String title;
  final Color tint;
  final Color accent;
  final RecognizeCategory category;
  final List<ExploreItem> items;

  @override
  State<_CategorySection> createState() => _CategorySectionState();
}

class _CategorySectionState extends State<_CategorySection> {
  static const _cardHeight = 168.0;
  /// 滑过列表末端再拉出这么多，自动进二级页
  static const _openOverscroll = 48.0;

  final _scroll = ScrollController();
  bool _openingMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _openingMore || widget.items.isEmpty) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent + _openOverscroll) {
      _openMore();
    }
  }

  Future<void> _openMore() async {
    if (_openingMore || !mounted) return;
    setState(() => _openingMore = true);
    await openExploreMore(
      context,
      title: widget.title,
      category: widget.category,
    );
    if (!mounted) return;
    // 回到略靠前位置，避免返回后立刻再次触发
    if (_scroll.hasClients) {
      final back = (_scroll.position.maxScrollExtent - 96)
          .clamp(0.0, _scroll.position.maxScrollExtent);
      await _scroll.animateTo(
        back,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() => _openingMore = false);
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: widget.tint,
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
                    color: widget.accent.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: widget.accent,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _openingMore ? null : _openMore,
                  child: const Text('更多 ›'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _cardHeight + 14,
            child: items.isEmpty
                ? const Center(
                    child: Text(
                      '还没有内容哦',
                      style: TextStyle(color: AppTokens.textSecondary),
                    ),
                  )
                : ListView.separated(
                    controller: _scroll,
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 0, 8, 14),
                    // 末尾多一项：继续滑动提示
                    itemCount: items.length + 1,
                    separatorBuilder: (_, index) => const SizedBox(width: 10),
                    itemBuilder: (context, i) {
                      if (i >= items.length) {
                        return _ContinueSlideMoreCard(
                          height: _cardHeight,
                          accent: widget.accent,
                          busy: _openingMore,
                          onTap: _openMore,
                        );
                      }
                      final item = items[i];
                      return SizedBox(
                        height: _cardHeight,
                        child: _ExploreCard(
                          item: item,
                          onTap: () => openExploreDetail(context, item),
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

class _ContinueSlideMoreCard extends StatelessWidget {
  const _ContinueSlideMoreCard({
    required this.height,
    required this.accent,
    required this.busy,
    required this.onTap,
  });

  final double height;
  final Color accent;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: height,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: busy ? null : onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.swipe_left_alt_rounded,
                  color: accent,
                  size: 36,
                ),
                const SizedBox(height: 10),
                Text(
                  busy ? '正在打开…' : '继续滑动\n展示更多',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final hasImage = item.imageUrl.trim().isNotEmpty;
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
                  clipBehavior: Clip.antiAlias,
                  child: hasImage
                      ? Image.network(
                          item.imageUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (_, __, ___) => Text(
                            item.emoji,
                            style: const TextStyle(fontSize: 42),
                          ),
                        )
                      : Text(item.emoji, style: const TextStyle(fontSize: 42)),
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
