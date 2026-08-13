import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/navigation/app_routes.dart';
import 'package:shitu_app/screens/camera_screen.dart';
import 'package:shitu_app/screens/detail_screen.dart';
import 'package:shitu_app/services/recognize_api.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class ResultScreen extends StatefulWidget {
  const ResultScreen({
    super.key,
    required this.imageFile,
    required this.result,
  });

  final File imageFile;
  final RecognizeResult result;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  late final PageController _controller;
  final _api = RecognizeApi();
  int _index = 0;
  bool _feedbackSending = false;
  bool _feedbackSent = false;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.82);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<RecognizeCandidate> get _candidates => widget.result.candidates;

  /// 最后一页是「以上都不是」
  int get _pageCount => _candidates.length + 1;

  bool get _isNoneOfAbove => _index >= _candidates.length;

  /// 列表最高可信度仍 < 15%：展示「被难住了」文案
  bool get _isLowConfidence {
    if (_candidates.isEmpty) return true;
    var maxScore = 0.0;
    for (final c in _candidates) {
      if (c.score > maxScore) maxScore = c.score;
    }
    return maxScore < 0.15;
  }

  String get _headerTitle {
    if (_isNoneOfAbove) return '以上都不是';
    if (_isLowConfidence) return '我居然被难住了';
    return _candidates[_index].name;
  }

  String get _headerSubtitle {
    if (_isNoneOfAbove) return '点卡片告诉我们，帮识图认得更准～';
    if (_isLowConfidence) {
      return '它可能是「${_candidates[_index].name}」';
    }
    return _candidates[_index].oneLiner;
  }

  Future<void> _submitNoneOfAbove() async {
    if (_feedbackSending) return;
    if (_feedbackSent) {
      await _showThanksDialog(already: true);
      return;
    }

    setState(() => _feedbackSending = true);
    try {
      await _api.reportFeedback(
        category: widget.result.category,
        shownCandidates: _candidates,
        imageFile: widget.imageFile,
      );
      if (!mounted) return;
      setState(() {
        _feedbackSending = false;
        _feedbackSent = true;
      });
      await _showThanksDialog();
    } on RecognizeApiException catch (e) {
      if (!mounted) return;
      setState(() => _feedbackSending = false);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('反馈没发出去'),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _feedbackSending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('反馈失败：$e')),
      );
    }
  }

  Future<void> _showThanksDialog({bool already = false}) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(already ? '已经收到啦' : '谢谢你告诉我'),
        content: Text(
          already
              ? '这条「以上都不是」已经记下来了。可以再拍一张试试～'
              : '已经记下这次识别不准的情况，我们会让识图变得更准。要不要再拍一张？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('先这样'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pushReplacement(
                slideUpRoute(const CameraScreen()),
              );
            },
            child: const Text('再拍一张'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  SoftBackButton(
                    onPressed: () {
                      Navigator.of(context).popUntil((r) => r.isFirst);
                    },
                  ),
                  const Spacer(),
                  Material(
                    color: AppTokens.primarySoft,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () {
                        Navigator.of(context).pushReplacement(
                          slideUpRoute(const CameraScreen()),
                        );
                      },
                      child: const SizedBox(
                        width: 44,
                        height: 44,
                        child: Icon(Icons.photo_camera_outlined),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: AspectRatio(
                  aspectRatio: 4 / 3,
                  child: Image.file(widget.imageFile, fit: BoxFit.cover),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _headerTitle,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: AppTokens.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                _headerSubtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppTokens.textSecondary,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageCount,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) {
                  if (i >= _candidates.length) {
                    return _NoneOfAboveCard(
                      selected: i == _index,
                      sending: _feedbackSending,
                      sent: _feedbackSent,
                      imageFile: widget.imageFile,
                      onTap: _submitNoneOfAbove,
                    );
                  }
                  final c = _candidates[i];
                  final selected = i == _index;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: InkWell(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DetailScreen.fromCandidate(
                              c,
                              category: widget.result.category,
                              localImage: widget.imageFile,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? AppTokens.primary : AppTokens.borderSubtle,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              _CandidateImage(imageUrl: c.imageUrl),
                              Positioned(
                                left: 8,
                                right: 8,
                                bottom: 8,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0x99000000),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Text(
                                      '可信度 ${(c.score * 100).clamp(0, 100).toStringAsFixed(0)}%',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _isNoneOfAbove
                    ? '点卡片上报「认错了」，帮我们改进识别'
                    : '左右滑动看看其他可能，点卡片了解更多',
                style: const TextStyle(color: AppTokens.textTertiary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoneOfAboveCard extends StatelessWidget {
  const _NoneOfAboveCard({
    required this.selected,
    required this.sending,
    required this.sent,
    required this.imageFile,
    required this.onTap,
  });

  final bool selected;
  final bool sending;
  final bool sent;
  final File imageFile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: InkWell(
        onTap: sending ? null : onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppTokens.primary : AppTokens.borderSubtle,
              width: selected ? 2 : 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  imageFile,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  alignment: Alignment.center,
                ),
                // 轻微压暗，保证问号/文案可读
                const ColoredBox(color: Color(0x33000000)),
                Center(
                  child: sending
                      ? const SizedBox(
                          width: 32,
                          height: 32,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              sent
                                  ? Icons.check_circle_rounded
                                  : Icons.help_outline_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              sent ? '已收到反馈' : '以上都不是',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                shadows: [
                                  Shadow(blurRadius: 6, color: Colors.black54),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              sent ? '谢谢你告诉我' : '点一下告诉我们',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13,
                                shadows: const [
                                  Shadow(blurRadius: 6, color: Colors.black54),
                                ],
                              ),
                            ),
                          ],
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

/// 鉴定卡配图：仅接口返回图；无效/失败时用 App logo（不用用户拍摄图）
class _CandidateImage extends StatelessWidget {
  const _CandidateImage({required this.imageUrl});

  final String imageUrl;

  static const _appLogo = 'assets/images/app-logo.png';

  static String _normalizeUrl(String raw) {
    final url = raw.trim();
    if (url.startsWith('http://')) {
      return 'https://${url.substring(7)}';
    }
    return url;
  }

  /// 接口有时会返回百度品牌/占位图，当作无效处理
  static bool isUsableImageUrl(String raw) {
    final url = _normalizeUrl(raw);
    if (url.isEmpty) return false;
    final lower = url.toLowerCase();
    const junk = [
      'bd_logo',
      'baidu_logo',
      'baidu-logo',
      'logo-baidu',
      'passport.baidu.com',
      'bdstatic.com/static/common',
      'bdstatic.com/img/logo',
      'ss0.bdstatic.com/5ac',
    ];
    if (junk.any(lower.contains)) return false;
    final path = lower.split('?').first;
    if (path.endsWith('/logo') ||
        path.endsWith('/logo/') ||
        path.endsWith('/logo.png') ||
        path.endsWith('/logo.jpg') ||
        path.endsWith('favicon.ico')) {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final url = _normalizeUrl(imageUrl);
    if (isUsableImageUrl(url)) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return ColoredBox(
            color: AppTokens.primarySoft,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: AppTokens.primary.withValues(alpha: 0.7),
                  value: progress.expectedTotalBytes != null
                      ? progress.cumulativeBytesLoaded /
                          progress.expectedTotalBytes!
                      : null,
                ),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _logoFallback(),
      );
    }
    return _logoFallback();
  }

  Widget _logoFallback() {
    return ColoredBox(
      color: AppTokens.primarySoft,
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.7,
          heightFactor: 0.7,
          child: Image.asset(
            _appLogo,
            fit: BoxFit.contain,
            alignment: Alignment.center,
          ),
        ),
      ),
    );
  }
}
