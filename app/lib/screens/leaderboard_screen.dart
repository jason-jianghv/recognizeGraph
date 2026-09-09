import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/screens/login_screen.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/leaderboard_api.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/theme/tokens.dart';

/// 对齐 Figma「学习阅读排行榜」(252:79)
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final _api = LeaderboardApi();

  LeaderboardScope _scope = LeaderboardScope.total;
  List<LeaderboardEntry> _items = [];
  LeaderboardMe? _me;
  bool _loading = true;
  String? _error;

  static const _avatarPalette = <Color>[
    Color(0xFFE0F0FF),
    Color(0xFFDBF5E0),
    Color(0xFFFFE8BD),
    Color(0xFFEDE0FF),
    Color(0xFFFFDBE8),
    Color(0xFFFFD9C8),
    Color(0xFFC7E8FF),
    Color(0xFFFFD1DE),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<SessionState>();
    try {
      final result = await _api.fetch(
        scope: _scope,
        token: session.loggedIn ? session.token : null,
      );
      if (!mounted) return;
      setState(() {
        _items = result.items;
        _me = result.me;
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
        _error = '排行榜暂时打不开：$e';
      });
    }
  }

  Future<void> _switchScope(LeaderboardScope scope) async {
    if (scope == _scope) return;
    setState(() => _scope = scope);
    await _load();
  }

  Future<void> _openLogin() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  Color _paletteFor(String key) {
    if (key.isEmpty) return _avatarPalette.first;
    return _avatarPalette[key.hashCode.abs() % _avatarPalette.length];
  }

  String _initial(String nickname) {
    final t = nickname.trim();
    if (t.isEmpty) return '🙂';
    return String.fromCharCodes(t.runes.take(1));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final top3 = _items.take(3).toList();
    final rest = _items.length > 3 ? _items.sublist(3) : <LeaderboardEntry>[];

    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      body: Column(
        children: [
          _TopBar(onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: RefreshIndicator(
              color: AppTokens.primary,
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Center(
                        child: _ScopeTabs(
                          scope: _scope,
                          onChanged: _loading ? null : _switchScope,
                        ),
                      ),
                    ),
                  ),
                  if (_loading && _items.isEmpty && _error == null)
                    const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: CircularProgressIndicator(color: AppTokens.primary),
                      ),
                    )
                  else if (_error != null && _items.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: AppTokens.textSecondary,
                                fontSize: 15,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(onPressed: _load, child: const Text('再试一次')),
                          ],
                        ),
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _PodiumSection(
                          entries: top3,
                          resolveAvatar: _api.resolveAvatarUrl,
                          paletteFor: _paletteFor,
                          initialOf: _initial,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: _RankListCard(
                          entries: rest,
                          resolveAvatar: _api.resolveAvatarUrl,
                          paletteFor: _paletteFor,
                          initialOf: _initial,
                          emptyHint: _scope == LeaderboardScope.week
                              ? '这周还没有人上榜哦\n去拍一拍、学一学吧～'
                              : '还没有人上榜哦\n去拍一拍、学一学吧～',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _MyRankFooter(
            loggedIn: session.loggedIn,
            loading: _loading,
            me: _me,
            sessionAvatarUrl: session.avatarUrl,
            resolveAvatar: _api.resolveAvatarUrl,
            bottomInset: bottomInset,
            onLogin: _openLogin,
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(top: top),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16),
                    child: Material(
                      color: Colors.white,
                      shape: const CircleBorder(
                        side: BorderSide(color: Color(0xFFE5E5E5)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: onBack,
                        child: const SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(
                            Icons.chevron_left_rounded,
                            color: AppTokens.textPrimary,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '学习阅读榜',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: AppTokens.primary,
                        height: 1.2,
                      ),
                    ),
                    SizedBox(width: 4),
                    Text('✨', style: TextStyle(fontSize: 18)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFE8E8E8)),
        ],
      ),
    );
  }
}

class _ScopeTabs extends StatelessWidget {
  const _ScopeTabs({
    required this.scope,
    required this.onChanged,
  });

  final LeaderboardScope scope;
  final ValueChanged<LeaderboardScope>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEADF),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TabChip(
              label: '总榜',
              selected: scope == LeaderboardScope.total,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(LeaderboardScope.total),
            ),
          ),
          Expanded(
            child: _TabChip(
              label: '周榜',
              selected: scope == LeaderboardScope.week,
              onTap: onChanged == null
                  ? null
                  : () => onChanged!(LeaderboardScope.week),
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFFFF8A4C) : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: SizedBox(
          height: 30,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFFA76B50),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PodiumSection extends StatelessWidget {
  const _PodiumSection({
    required this.entries,
    required this.resolveAvatar,
    required this.paletteFor,
    required this.initialOf,
  });

  final List<LeaderboardEntry> entries;
  final String Function(String) resolveAvatar;
  final Color Function(String) paletteFor;
  final String Function(String) initialOf;

  LeaderboardEntry? _at(int i) => i < entries.length ? entries[i] : null;

  @override
  Widget build(BuildContext context) {
    final first = _at(0);
    final second = _at(1);
    final third = _at(2);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFE3C7), Color(0xFFFFF7E5)],
        ),
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '学习之星',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '坚持阅读，点亮每一份好奇心',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF737373),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 170,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: _PodiumCard(
                    place: 2,
                    entry: second,
                    height: 142,
                    resolveAvatar: resolveAvatar,
                    paletteFor: paletteFor,
                    initialOf: initialOf,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PodiumCard(
                    place: 1,
                    entry: first,
                    height: 164,
                    resolveAvatar: resolveAvatar,
                    paletteFor: paletteFor,
                    initialOf: initialOf,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PodiumCard(
                    place: 3,
                    entry: third,
                    height: 132,
                    resolveAvatar: resolveAvatar,
                    paletteFor: paletteFor,
                    initialOf: initialOf,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PodiumCard extends StatelessWidget {
  const _PodiumCard({
    required this.place,
    required this.entry,
    required this.height,
    required this.resolveAvatar,
    required this.paletteFor,
    required this.initialOf,
  });

  final int place;
  final LeaderboardEntry? entry;
  final double height;
  final String Function(String) resolveAvatar;
  final Color Function(String) paletteFor;
  final String Function(String) initialOf;

  @override
  Widget build(BuildContext context) {
    final empty = entry == null;
    final name = empty
        ? '虚位以待'
        : (entry!.nickname.isEmpty ? '小小探索家' : entry!.nickname);
    final count = empty ? 0 : entry!.learnCount;
    final avatarUrl = empty ? '' : resolveAvatar(entry!.avatarUrl);
    final avatarSize = place == 1 ? 54.0 : (place == 2 ? 46.0 : 44.0);

    return Container(
      height: height,
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          if (place == 1)
            const Text('👑', style: TextStyle(fontSize: 22))
          else
            _MedalDot(place: place),
          const SizedBox(height: 4),
          _AvatarBubble(
            url: avatarUrl,
            size: avatarSize,
            bg: empty
                ? const Color(0xFFFFEDE5)
                : (place == 1 ? const Color(0xFFFFD15E) : paletteFor(name)),
            label: place == 1 && avatarUrl.isEmpty
                ? '🦁'
                : initialOf(name),
            labelColor: place == 1
                ? null
                : (place == 2
                    ? const Color(0xFF337DBA)
                    : const Color(0xFFC74770)),
            fontSize: place == 1 ? 28 : 18,
          ),
          const Spacer(),
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: place == 1 ? 14 : 13,
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            empty ? '—' : '学习 $count 次',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: place == 1 ? 12 : 11,
              fontWeight: place == 1 ? FontWeight.w600 : FontWeight.w500,
              color: place == 1
                  ? AppTokens.primary
                  : (place == 2
                      ? const Color(0xFF616B7A)
                      : const Color(0xFF7D5E52)),
            ),
          ),
          if (place == 1) ...[
            const SizedBox(height: 2),
            const Text(
              'NO.1',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Color(0xFFD18705),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MedalDot extends StatelessWidget {
  const _MedalDot({required this.place});

  final int place;

  @override
  Widget build(BuildContext context) {
    final bg = place == 2 ? const Color(0xFFD1D9E3) : const Color(0xFFE5A66E);
    final fg = place == 2 ? const Color(0xFF576373) : const Color(0xFF7D451F);
    return Container(
      width: 26,
      height: 26,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Text(
        '$place',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _RankListCard extends StatelessWidget {
  const _RankListCard({
    required this.entries,
    required this.resolveAvatar,
    required this.paletteFor,
    required this.initialOf,
    required this.emptyHint,
  });

  final List<LeaderboardEntry> entries;
  final String Function(String) resolveAvatar;
  final Color Function(String) paletteFor;
  final String Function(String) initialOf;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEDE5E0)),
      ),
      child: Column(
        children: [
          const Row(
            children: [
              Text(
                '第 4–20 名',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.textPrimary,
                ),
              ),
              Spacer(),
              Text(
                '向上滑动查看完整榜单',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF8C8C8C),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, thickness: 1, color: Color(0xFFF0EBE5)),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Text(
                emptyHint,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: AppTokens.textSecondary,
                ),
              ),
            )
          else
            ...entries.map((e) {
              final name = e.nickname.isEmpty ? '小小探索家' : e.nickname;
              return _RankRow(
                rank: e.rank,
                nickname: name,
                learnCount: e.learnCount,
                avatarUrl: resolveAvatar(e.avatarUrl),
                bg: paletteFor(name),
                initial: initialOf(name),
              );
            }),
        ],
      ),
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.nickname,
    required this.learnCount,
    required this.avatarUrl,
    required this.bg,
    required this.initial,
  });

  final int rank;
  final String nickname;
  final int learnCount;
  final String avatarUrl;
  final Color bg;
  final String initial;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF737373),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _AvatarBubble(
            url: avatarUrl,
            size: 36,
            bg: bg,
            label: initial,
            labelColor: const Color(0xFF4778AD),
            fontSize: 16,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              nickname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTokens.textPrimary,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF0E5),
              borderRadius: BorderRadius.circular(AppTokens.radiusPill),
            ),
            child: Text(
              '学习 $learnCount 次',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFFB84500),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarBubble extends StatelessWidget {
  const _AvatarBubble({
    required this.url,
    required this.size,
    required this.bg,
    required this.label,
    required this.fontSize,
    this.labelColor,
  });

  final String url;
  final double size;
  final Color bg;
  final String label;
  final double fontSize;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: bg,
        alignment: Alignment.center,
        child: url.isEmpty
            ? Text(
                label,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  color: labelColor ?? AppTokens.textPrimary,
                ),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                width: size,
                height: size,
                errorBuilder: (context, error, stackTrace) => Text(
                  label,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: FontWeight.w700,
                    color: labelColor ?? AppTokens.textPrimary,
                  ),
                ),
              ),
      ),
    );
  }
}

class _MyRankFooter extends StatelessWidget {
  const _MyRankFooter({
    required this.loggedIn,
    required this.loading,
    required this.me,
    required this.sessionAvatarUrl,
    required this.resolveAvatar,
    required this.bottomInset,
    required this.onLogin,
  });

  final bool loggedIn;
  final bool loading;
  final LeaderboardMe? me;
  final String sessionAvatarUrl;
  final String Function(String) resolveAvatar;
  final double bottomInset;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTokens.bgPage,
      padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + bottomInset),
      child: loggedIn ? _buildLoggedIn() : _buildLoggedOut(),
    );
  }

  Widget _buildLoggedOut() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onLogin,
        borderRadius: BorderRadius.circular(12),
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Text(
              '未登录时：登录后查看本人名次  →',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFFA76B50),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoggedIn() {
    if (loading && me == null) {
      return const SizedBox(
        height: 62,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppTokens.primary,
            ),
          ),
        ),
      );
    }

    final avatar = resolveAvatar(
      (me?.avatarUrl.isNotEmpty == true) ? me!.avatarUrl : sessionAvatarUrl,
    );
    final rankText = me?.rank != null ? '第 ${me!.rank} 名' : '暂无名次';
    final count = me?.learnCount ?? 0;
    final inTop = me?.inTop == true;

    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFD6BF)),
      ),
      child: Row(
        children: [
          _AvatarBubble(
            url: avatar,
            size: 40,
            bg: const Color(0xFFFFD9C8),
            label: '我',
            labelColor: const Color(0xFFB35D38),
            fontSize: 14,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '我的名次',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4D3429),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$rankText · 学习 $count 次',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF7E5C4C),
                  ),
                ),
              ],
            ),
          ),
          if (!inTop)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0E5),
                borderRadius: BorderRadius.circular(AppTokens.radiusPill),
              ),
              child: const Text(
                '未进前 20',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE56E33),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
