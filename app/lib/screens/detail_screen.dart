import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/screens/voice_preference_screen.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/history_api.dart';
import 'package:shitu_app/services/tts_api.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/state/voice_preference_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';
import 'package:url_launcher/url_launcher.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({
    super.key,
    required this.name,
    required this.oneLiner,
    required this.description,
    this.emoji,
    this.networkImage,
    this.localImage,
    this.showPlayer = false,
    this.category = '',
    this.candidateId = '',
    this.baikeUrl = '',
    this.score = 0,
    this.source = 'explore',
  });

  final String name;
  final String oneLiner;
  final String description;
  final String? emoji;
  final String? networkImage;
  final File? localImage;
  final bool showPlayer;
  final String category;
  final String candidateId;
  final String baikeUrl;
  final double score;
  final String source;

  factory DetailScreen.fromExplore(ExploreItem item) {
    return DetailScreen(
      name: item.name,
      oneLiner: item.oneLiner,
      description: item.description,
      emoji: item.emoji,
      category: item.category.apiValue,
      candidateId: item.id,
      source: 'explore',
    );
  }

  factory DetailScreen.fromCandidate(
    RecognizeCandidate c, {
    required RecognizeCategory category,
    File? localImage,
  }) {
    final desc = c.description.trim();
    return DetailScreen(
      name: c.name,
      oneLiner: desc.isEmpty
          ? (c.oneLiner.trim().isEmpty ? '可能是「${c.name}」' : c.oneLiner)
          : desc,
      description: '关于「${c.name}」，我们以后会讲更多……',
      networkImage: c.imageUrl.isEmpty ? null : c.imageUrl,
      localImage: localImage,
      category: category.apiValue,
      candidateId: c.id,
      baikeUrl: c.baikeUrl,
      score: c.score,
      source: 'recognize',
    );
  }

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final _scroll = ScrollController();
  final _player = AudioPlayer();
  final _ttsApi = TtsApi();

  Timer? _dwellTimer;
  StreamSubscription<void>? _completeSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  bool _recorded = false;
  bool _recording = false;

  bool _ttsLoading = false;
  bool _playerVisible = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  File? _audioFile;
  String? _audioProfile;

  /// 停留满此时长，或点「听一听」，先到先记（同页一次）
  static const _dwellSeconds = 5;

  @override
  void initState() {
    super.initState();
    _playerVisible = widget.showPlayer;
    // 播完保留音源，便于直接重播本地缓存（默认 release 会导致再次播放无效）
    _player.setReleaseMode(ReleaseMode.stop);
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      // 进度条停在末尾；再次点击播放时再从 0 开始
      setState(() {
        _playing = false;
        if (_duration > Duration.zero) {
          _position = _duration;
        }
      });
    });
    _positionSub = _player.onPositionChanged.listen((d) {
      if (!mounted) return;
      setState(() => _position = d);
    });
    _durationSub = _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      if (d > Duration.zero) {
        setState(() => _duration = d);
      }
    });
    _stateSub = _player.onPlayerStateChanged.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s == PlayerState.playing);
    });

    if (widget.source == 'history') {
      _recorded = true;
    } else {
      _dwellTimer = Timer(const Duration(seconds: _dwellSeconds), () {
        if (mounted) _tryRecordLearn(trigger: 'dwell_${_dwellSeconds}s');
      });
    }
  }

  @override
  void dispose() {
    _dwellTimer?.cancel();
    _completeSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _tryRecordLearn({required String trigger}) async {
    if (_recorded || _recording) return;
    if (widget.source == 'history') {
      _recorded = true;
      return;
    }
    final session = context.read<SessionState>();
    final token = session.token;
    if (!session.loggedIn || token == null || token.isEmpty) {
      return;
    }

    setState(() => _recording = true);
    try {
      final api = HistoryApi();
      final result = await api.recordLearn(
        token: token,
        name: widget.name,
        category: widget.category,
        candidateId: widget.candidateId,
        baikeUrl: widget.baikeUrl,
        imageUrl: widget.networkImage ?? '',
        description: widget.oneLiner,
        score: widget.score,
        source: widget.source,
        thumbFile: widget.localImage,
      );
      _recorded = true;
      _dwellTimer?.cancel();
      await session.applyProfile(
        learnCount: result.learnCount,
        level: result.level,
      );
      debugPrint('[Detail] learn recorded via $trigger id=${result.id}');
    } on ApiException catch (e) {
      debugPrint('[Detail] learn failed: $e');
    } catch (e) {
      debugPrint('[Detail] learn error: $e');
    } finally {
      if (mounted) setState(() => _recording = false);
    }
  }

  Future<void> _onListen() async {
    _tryRecordLearn(trigger: 'listen');
    if (_ttsLoading) return;

    final profile = context.read<VoicePreferenceState>().profile.apiValue;
    // 已有音频且偏好未变：直接播缓存，不再请求合成
    if (_audioFile != null &&
        _audioProfile == profile &&
        await _audioFile!.exists()) {
      setState(() => _playerVisible = true);
      await _playCached();
      return;
    }

    setState(() {
      _ttsLoading = true;
      _playerVisible = true;
    });
    try {
      await _player.stop();
      final file = await _ttsApi.synthesizeToFile(
        name: widget.name,
        oneLiner: widget.oneLiner,
        voiceProfile: profile,
      );
      if (!mounted) return;
      _audioFile = file;
      _audioProfile = profile;
      await _player.play(DeviceFileSource(file.path));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _playerVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _playerVisible = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('播报失败：$e')),
      );
    } finally {
      if (mounted) setState(() => _ttsLoading = false);
    }
  }

  /// 用本页已合成的临时 MP3 播放（暂停续播 / 播完重听）。
  Future<void> _playCached() async {
    final file = _audioFile;
    if (file == null) return;

    if (_playing) {
      await _player.pause();
      return;
    }

    // 中途暂停：续播
    if (_player.state == PlayerState.paused &&
        _position > Duration.zero &&
        !(_duration > Duration.zero && _position >= _duration)) {
      await _player.resume();
      if (_player.state == PlayerState.playing) return;
    }

    // 播完或音源已释放：从头播同一份文件，不重新合成
    setState(() => _position = Duration.zero);
    await _player.stop();
    await _player.seek(Duration.zero);
    await _player.play(DeviceFileSource(file.path));
  }

  Future<void> _openVoicePreference() async {
    final before = context.read<VoicePreferenceState>().profile;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const VoicePreferenceScreen(),
      ),
    );
    if (!mounted) return;
    final after = context.read<VoicePreferenceState>().profile;
    if (before != after) {
      await _player.stop();
      setState(() {
        _audioFile = null;
        _audioProfile = null;
        _playerVisible = false;
        _playing = false;
        _position = Duration.zero;
        _duration = Duration.zero;
      });
    }
  }

  Future<void> _togglePlay() async {
    if (_audioFile == null || !(await _audioFile!.exists())) {
      await _onListen();
      return;
    }
    await _playCached();
  }

  Future<void> _seek(double value) async {
    if (_duration <= Duration.zero) return;
    final target = Duration(
      milliseconds: (value * _duration.inMilliseconds).round(),
    );
    await _player.seek(target);
  }

  Future<void> _openBaike() async {
    final raw = widget.baikeUrl.trim();
    if (raw.isEmpty) return;
    var url = raw;
    if (url.startsWith('http://')) {
      url = 'https://${url.substring(7)}';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('百科链接打不开，稍后再试～')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('百科链接打不开，稍后再试～')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBaike = widget.baikeUrl.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              controller: _scroll,
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
                  actions: [
                    IconButton(
                      tooltip: '语音偏好修改',
                      onPressed: _openVoicePreference,
                      icon: const Icon(
                        Icons.record_voice_over_rounded,
                        color: AppTokens.primary,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  expandedHeight: 280,
                  flexibleSpace: FlexibleSpaceBar(
                    background: _Hero(
                      emoji: widget.emoji,
                      networkImage: widget.networkImage,
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
                          widget.name,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.oneLiner,
                          style: const TextStyle(
                            fontSize: 17,
                            color: AppTokens.textSecondary,
                            height: 1.4,
                          ),
                        ),
                        if (hasBaike) ...[
                          const SizedBox(height: 14),
                          Material(
                            color: AppTokens.primarySoft,
                            borderRadius: BorderRadius.circular(999),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: _openBaike,
                              child: const Padding(
                                padding: EdgeInsets.fromLTRB(12, 10, 16, 10),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.auto_stories_rounded,
                                      size: 22,
                                      color: AppTokens.primary,
                                    ),
                                    SizedBox(width: 8),
                                    Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.3,
                                          color: AppTokens.textPrimary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        children: [
                                          TextSpan(text: '了解更多 '),
                                          TextSpan(
                                            text: '点击我吧',
                                            style: TextStyle(
                                              color: AppTokens.primary,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          TextSpan(text: ' '),
                                        ],
                                      ),
                                    ),
                                    Icon(
                                      Icons.north_east_rounded,
                                      size: 16,
                                      color: AppTokens.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
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
                          widget.description,
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
              child: _playerVisible
                  ? _PlayerBar(
                      loading: _ttsLoading,
                      playing: _playing,
                      progress: _duration.inMilliseconds <= 0
                          ? 0
                          : (_position.inMilliseconds / _duration.inMilliseconds)
                              .clamp(0.0, 1.0),
                      onToggle: _ttsLoading ? null : _togglePlay,
                      onSeek: _ttsLoading ? null : _seek,
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        PrimaryPillButton(
                          label: _ttsLoading ? '准备中…' : '听一听介绍',
                          onPressed: _ttsLoading ? null : _onListen,
                        ),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _openVoicePreference,
                          behavior: HitTestBehavior.opaque,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTokens.textTertiary,
                                  height: 1.3,
                                ),
                                children: [
                                  TextSpan(text: '可在设置里改语音类型 · '),
                                  TextSpan(
                                    text: '去修改',
                                    style: TextStyle(
                                      color: AppTokens.primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({this.emoji, this.networkImage});

  final String? emoji;
  final String? networkImage;

  @override
  Widget build(BuildContext context) {
    final url = networkImage?.trim() ?? '';
    if (url.isNotEmpty) {
      return Image.network(
        url,
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
  const _PlayerBar({
    required this.loading,
    required this.playing,
    required this.progress,
    required this.onToggle,
    required this.onSeek,
  });

  final bool loading;
  final bool playing;
  final double progress;
  final VoidCallback? onToggle;
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filled(
          onPressed: onToggle,
          style: IconButton.styleFrom(backgroundColor: AppTokens.primary),
          icon: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 8,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: AppTokens.primary,
              inactiveTrackColor: AppTokens.primarySoft,
              thumbColor: AppTokens.primary,
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: onSeek,
            ),
          ),
        ),
      ],
    );
  }
}
