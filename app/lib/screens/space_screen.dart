import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/screens/detail_screen.dart';
import 'package:shitu_app/screens/login_screen.dart';
import 'package:shitu_app/screens/settings_screen.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/history_api.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class SpaceScreen extends StatelessWidget {
  const SpaceScreen({super.key, this.isActive = true});

  /// 当前是否选中「空间」Tab（IndexedStack 保活时用于切回自动刷新）
  final bool isActive;

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
      body: session.loggedIn
          ? _LoggedInBody(isActive: isActive)
          : const _LoggedOutBody(),
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

class _LoggedInBody extends StatefulWidget {
  const _LoggedInBody({required this.isActive});

  final bool isActive;

  @override
  State<_LoggedInBody> createState() => _LoggedInBodyState();
}

class _LoggedInBodyState extends State<_LoggedInBody> {
  final _api = HistoryApi();
  final _scroll = ScrollController();

  List<HistoryMonth> _months = [];
  final Map<String, List<HistoryItem>> _items = {};
  final Map<String, int> _page = {};
  final Map<String, bool> _hasMore = {};
  int _visibleMonthCount = 0;

  bool _loading = true;
  bool _loadingMore = false;
  bool _bootstrapping = false;
  String? _error;

  /// 用于在「已学次数」变化时自动刷新（详情记学习后仍停在空间 Tab）
  int? _seenLearnCount;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void didUpdateWidget(covariant _LoggedInBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 从探索等切回空间：重新拉月份与列表
    if (widget.isActive && !oldWidget.isActive) {
      _bootstrap(showFullLoading: false);
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loadingMore || _loading) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 80) {
      _loadMore();
    }
  }

  Future<void> _bootstrap({bool showFullLoading = true}) async {
    if (_bootstrapping) return;
    final session = context.read<SessionState>();
    final token = session.token;
    if (token == null) return;
    _bootstrapping = true;
    _seenLearnCount = session.learnCount;
    if (showFullLoading || _months.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _error = null);
    }
    try {
      final months = await _api.fetchMonths(token);
      if (!mounted) return;
      _months = months;
      _visibleMonthCount = months.isEmpty ? 0 : 1;
      _items.clear();
      _page.clear();
      _hasMore.clear();
      if (months.isNotEmpty) {
        await _ensureMonthPage(token, months.first.yearMonth, page: 1);
      }
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '$e';
    } finally {
      _bootstrapping = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ensureMonthPage(
    String token,
    String month, {
    required int page,
  }) async {
    final data = await _api.fetchMonthPage(
      token: token,
      month: month,
      page: page,
      pageSize: 21,
    );
    final list = _items.putIfAbsent(month, () => []);
    if (page == 1) {
      list
        ..clear()
        ..addAll(data.items);
    } else {
      list.addAll(data.items);
    }
    _page[month] = data.page;
    _hasMore[month] = data.hasMore;
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _months.isEmpty) return;
    final token = context.read<SessionState>().token;
    if (token == null) return;

    final lastIdx = _visibleMonthCount - 1;
    if (lastIdx < 0) return;
    final month = _months[lastIdx].yearMonth;

    setState(() => _loadingMore = true);
    try {
      if (_hasMore[month] == true) {
        final next = (_page[month] ?? 1) + 1;
        await _ensureMonthPage(token, month, page: next);
      } else if (_visibleMonthCount < _months.length) {
        _visibleMonthCount += 1;
        final nextMonth = _months[_visibleMonthCount - 1].yearMonth;
        await _ensureMonthPage(token, nextMonth, page: 1);
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    // 详情页记学习后 learnCount 会变；若仍停在空间 Tab，切 Tab 不会触发，这里补刷
    final learnCount = session.learnCount;
    if (_seenLearnCount != null &&
        _seenLearnCount != learnCount &&
        !_bootstrapping) {
      _seenLearnCount = learnCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _bootstrap(showFullLoading: false);
      });
    }

    return RefreshIndicator(
      onRefresh: () => _bootstrap(showFullLoading: true),
      color: AppTokens.primary,
      child: ListView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _ProfileCard(session: session),
          const SizedBox(height: 20),
          const Text(
            '我的本领宝藏箱',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Column(
                children: [
                  Text(_error!, style: const TextStyle(color: AppTokens.textSecondary)),
                  TextButton(
                    onPressed: () => _bootstrap(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            )
          else if (_months.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                '还没有学习记录～去拍一张或逛逛探索吧',
                style: TextStyle(color: AppTokens.textSecondary, fontSize: 15),
              ),
            )
          else ...[
            for (var i = 0; i < _visibleMonthCount; i++) ...[
              Text(
                _months[i].label,
                style: const TextStyle(color: AppTokens.textSecondary),
              ),
              const SizedBox(height: 10),
              _MonthGrid(
                items: _items[_months[i].yearMonth] ?? const [],
                mediaBase: _api.baseUrl,
                onOpen: (item) {
                  // 详情顶图用接口百科图；用户拍摄缩略图留给列表卡
                  final apiImage = item.imageUrl.trim();
                  final intro = item.description.trim().isNotEmpty
                      ? item.description.trim()
                      : (item.oneLiner.trim().isNotEmpty
                          ? item.oneLiner.trim()
                          : '你认识过的小伙伴');
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => DetailScreen(
                        name: item.name,
                        oneLiner: intro,
                        description: '关于「${item.name}」，我们以后会讲更多……',
                        networkImage: apiImage.isEmpty ? null : apiImage,
                        category: item.category,
                        candidateId: '${item.id}',
                        baikeUrl: item.baikeUrl,
                        source: 'history',
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
            if (_loadingMore)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return Container(
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
            clipBehavior: Clip.antiAlias,
            child: session.avatarUrl.isNotEmpty
                ? Image.network(session.avatarUrl, fit: BoxFit.cover)
                : const Text('🧒', style: TextStyle(fontSize: 32)),
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
                Text(
                  '已学习 ${session.learnCount} 次',
                  style: const TextStyle(color: AppTokens.textSecondary),
                ),
                const SizedBox(height: 2),
                Text(
                  session.levelHint,
                  style: const TextStyle(
                    color: AppTokens.textTertiary,
                    fontSize: 13,
                  ),
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
            child: Text(
              'Lv ${session.level}',
              style: const TextStyle(
                color: AppTokens.level,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.items,
    required this.mediaBase,
    required this.onOpen,
  });

  final List<HistoryItem> items;
  final String mediaBase;
  final void Function(HistoryItem item) onOpen;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemBuilder: (context, i) {
        final item = items[i];
        // 本领宝藏箱卡片：只用用户拍摄缩略图（不用接口百科图）
        final thumb = item.thumbUrl.isNotEmpty
            ? (item.thumbUrl.startsWith('http')
                ? item.thumbUrl
                : '$mediaBase${item.thumbUrl}')
            : '';
        return _HistoryTile(
          name: item.name,
          imageUrl: thumb,
          onTap: () => onOpen(item),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.name,
    required this.imageUrl,
    required this.onTap,
  });

  final String name;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imageUrl.isNotEmpty)
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, error, stackTrace) => const ColoredBox(
                  color: AppTokens.primarySoft,
                  child: Center(child: Text('📷', style: TextStyle(fontSize: 28))),
                ),
              )
            else
              const ColoredBox(
                color: AppTokens.primarySoft,
                child: Center(child: Text('📷', style: TextStyle(fontSize: 28))),
              ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                width: double.infinity,
                color: const Color(0x99000000),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
