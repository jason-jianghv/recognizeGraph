import 'package:flutter/material.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/screens/explore_screen.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/catalog_api.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class MoreListScreen extends StatefulWidget {
  const MoreListScreen({
    super.key,
    required this.title,
    required this.category,
  });

  final String title;
  final RecognizeCategory category;

  @override
  State<MoreListScreen> createState() => _MoreListScreenState();
}

class _MoreListScreenState extends State<MoreListScreen> {
  final _api = CatalogApi();
  final _scroll = ScrollController();

  final List<ExploreItem> _items = [];
  int _page = 0;
  int _total = 0;
  bool _loading = false;
  bool _loadingMore = false;
  String? _error;

  static const _pageSize = 40;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_loadingMore || _loading) return;
    if (_items.length >= _total && _total > 0) return;
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 240) {
      _load(reset: false);
    }
  }

  Future<void> _load({required bool reset}) async {
    if (reset) {
      if (_loading) return;
      setState(() {
        _loading = true;
        _error = null;
        _page = 0;
      });
    } else {
      if (_loadingMore) return;
      if (_items.length >= _total && _total > 0) return;
      setState(() => _loadingMore = true);
    }

    final nextPage = reset ? 1 : _page + 1;
    try {
      final page = await _api.list(
        category: widget.category,
        page: nextPage,
        pageSize: _pageSize,
      );
      if (!mounted) return;
      setState(() {
        if (reset) _items.clear();
        _items.addAll(page.items);
        _page = page.page;
        _total = page.total;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = '加载失败：$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leadingWidth: 64,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: SoftBackButton(),
        ),
        title: Text(widget.title),
      ),
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(color: AppTokens.primary)),
        ],
      );
    }
    if (_error != null && _items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          Text(_error!, style: const TextStyle(color: AppTokens.textSecondary)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () => _load(reset: true),
            child: const Text('再试一次'),
          ),
        ],
      );
    }

    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, index) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (i >= _items.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTokens.primary,
                ),
              ),
            ),
          );
        }
        final item = _items[i];
        final hasImage = item.imageUrl.trim().isNotEmpty;
        return ListTile(
          onTap: () => openExploreDetail(context, item),
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: AppTokens.borderSubtle),
          ),
          leading: CircleAvatar(
            backgroundColor: AppTokens.primarySoft,
            backgroundImage: hasImage ? NetworkImage(item.imageUrl) : null,
            onBackgroundImageError: hasImage ? (_, __) {} : null,
            child: hasImage
                ? null
                : Text(item.emoji, style: const TextStyle(fontSize: 22)),
          ),
          title: Text(
            item.name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(item.oneLiner),
          trailing: const Icon(Icons.chevron_right_rounded),
        );
      },
    );
  }
}
