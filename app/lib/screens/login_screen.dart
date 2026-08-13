import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/legal/legal_texts.dart';
import 'package:shitu_app/screens/legal_doc_screen.dart';
import 'package:shitu_app/services/api_client.dart';
import 'package:shitu_app/services/auth_api.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

/// 对齐 Figma「登录」帧；对接 `/v1/auth/sms-code` 与 `/v1/auth/login`。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();
  final _authApi = AuthApi();

  static const _fieldRadius = 16.0;
  static const _hPad = 24.0;
  static const _resendSeconds = 60;

  Timer? _countdownTimer;
  int _secondsLeft = 0;
  bool _sendingCode = false;
  bool _loggingIn = false;
  bool _agreed = false;

  late final TapGestureRecognizer _userAgreementTap;
  late final TapGestureRecognizer _privacyTap;

  bool get _canSendCode => !_sendingCode && _secondsLeft == 0;

  @override
  void initState() {
    super.initState();
    _userAgreementTap = TapGestureRecognizer()
      ..onTap = () => _openLegal(
            LegalTexts.userAgreementTitle,
            LegalTexts.userAgreementBody,
          );
    _privacyTap = TapGestureRecognizer()
      ..onTap = () => _openLegal(
            LegalTexts.privacyPolicyTitle,
            LegalTexts.privacyPolicyBody,
          );
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _userAgreementTap.dispose();
    _privacyTap.dispose();
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openLegal(String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LegalDocScreen(title: title, body: body),
      ),
    );
  }

  void _startCountdown([int seconds = _resendSeconds]) {
    _countdownTimer?.cancel();
    setState(() => _secondsLeft = seconds);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _onSendCode() async {
    if (!_canSendCode) return;
    final phone = _phone.text.trim();
    setState(() => _sendingCode = true);
    try {
      final result = await _authApi.requestSmsCode(phone);
      if (!mounted) return;
      _startCountdown(result.resendAfter > 0 ? result.resendAfter : _resendSeconds);
      _toast('验证码：${result.code}（演示用，正式版将发短信）');
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('获取验证码失败：$e');
    } finally {
      if (mounted) setState(() => _sendingCode = false);
    }
  }

  Future<void> _onLoginPressed() async {
    if (_loggingIn) return;
    if (!_agreed) {
      await _showAgreeDialog();
      return;
    }
    await _performLogin();
  }

  Future<void> _showAgreeDialog() async {
    final action = await showDialog<_AgreeDialogAction>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('请先同意协议'),
        content: const Text(
          '登录前需要勾选同意《用户协议》和《隐私政策》哦～',
          style: TextStyle(height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _AgreeDialogAction.cancel),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, _AgreeDialogAction.agreeAndLogin),
            child: const Text(
              '同意并登录',
              style: TextStyle(
                color: AppTokens.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted || action != _AgreeDialogAction.agreeAndLogin) return;

    setState(() => _agreed = true);
    final code = _code.text.trim();
    if (code.isEmpty) {
      _toast('还没有填入验证码');
      return;
    }
    await _performLogin();
  }

  Future<void> _performLogin() async {
    if (_loggingIn) return;
    final phone = _phone.text.trim();
    final code = _code.text.trim();
    if (code.isEmpty) {
      _toast('请输入验证码');
      return;
    }
    setState(() => _loggingIn = true);
    try {
      final result = await _authApi.login(phone: phone, code: code);
      if (!mounted) return;
      await context.read<SessionState>().login(
            token: result.token,
            phone: result.phone,
            nickname: result.nickname,
            avatarUrl: result.avatarUrl,
            learnCount: result.learnCount,
            level: result.level,
          );
      _toast('登录成功，欢迎${result.nickname}');
      Navigator.of(context).pop();
    } on ApiException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('登录失败：$e');
    } finally {
      if (mounted) setState(() => _loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(_hPad, 10, _hPad, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CloseButton(onPressed: () => Navigator.of(context).pop()),
                    const SizedBox(height: 28),
                    const Text(
                      '登录识图',
                      style: TextStyle(
                        color: AppTokens.primary,
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '手机号验证一下，就能保存你的小天地啦',
                      style: TextStyle(
                        color: AppTokens.textSecondary,
                        fontSize: 16,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 46),
                    const _FieldLabel('手机号'),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      enabled: !_loggingIn,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppTokens.textPrimary,
                      ),
                      decoration: _inputDeco('请输入手机号'),
                    ),
                    const SizedBox(height: 24),
                    const _FieldLabel('验证码'),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _code,
                            keyboardType: TextInputType.number,
                            enabled: !_loggingIn,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(6),
                            ],
                            style: const TextStyle(
                              fontSize: 17,
                              color: AppTokens.textPrimary,
                            ),
                            decoration: _inputDeco('请输入验证码'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _SmsCodeButton(
                          canTap: _canSendCode && !_loggingIn,
                          sending: _sendingCode,
                          secondsLeft: _secondsLeft,
                          onPressed: _onSendCode,
                        ),
                      ],
                    ),
                    const SizedBox(height: 42),
                    PrimaryPillButton(
                      label: _loggingIn ? '登录中…' : '登录',
                      onPressed: _loggingIn ? null : _onLoginPressed,
                    ),
                    const SizedBox(height: 16),
                    _AgreementRow(
                      agreed: _agreed,
                      enabled: !_loggingIn,
                      onChanged: (v) => setState(() => _agreed = v),
                      userAgreementTap: _userAgreementTap,
                      privacyTap: _privacyTap,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String hint) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(_fieldRadius),
      borderSide: const BorderSide(color: AppTokens.borderSubtle),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppTokens.textTertiary, fontSize: 17),
      filled: true,
      fillColor: AppTokens.bgSurface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(_fieldRadius),
        borderSide: const BorderSide(color: AppTokens.primary, width: 1.5),
      ),
    );
  }
}

enum _AgreeDialogAction { cancel, agreeAndLogin }

class _AgreementRow extends StatelessWidget {
  const _AgreementRow({
    required this.agreed,
    required this.enabled,
    required this.onChanged,
    required this.userAgreementTap,
    required this.privacyTap,
  });

  final bool agreed;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final TapGestureRecognizer userAgreementTap;
  final TapGestureRecognizer privacyTap;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(
      color: AppTokens.textTertiary,
      fontSize: 13,
      height: 1.35,
    );
    const linkStyle = TextStyle(
      color: AppTokens.primary,
      fontSize: 13,
      height: 1.35,
      fontWeight: FontWeight.w600,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: Checkbox(
            value: agreed,
            onChanged: enabled
                ? (v) => onChanged(v ?? false)
                : null,
            activeColor: AppTokens.primary,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            side: const BorderSide(color: AppTokens.textTertiary, width: 1.4),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text.rich(
              TextSpan(
                style: baseStyle,
                children: [
                  const TextSpan(text: '登录即表示同意'),
                  TextSpan(
                    text: '《用户协议》',
                    style: linkStyle,
                    recognizer: userAgreementTap,
                  ),
                  const TextSpan(text: '和'),
                  TextSpan(
                    text: '《隐私政策》',
                    style: linkStyle,
                    recognizer: privacyTap,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SmsCodeButton extends StatelessWidget {
  const _SmsCodeButton({
    required this.canTap,
    required this.sending,
    required this.secondsLeft,
    required this.onPressed,
  });

  final bool canTap;
  final bool sending;
  final int secondsLeft;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cooling = secondsLeft > 0;
    final label = sending
        ? '发送中…'
        : cooling
            ? '${secondsLeft}s'
            : '获取验证码';
    final enabled = canTap && !sending;

    return SizedBox(
      width: 122,
      height: 54,
      child: Material(
        color: enabled ? AppTokens.primarySoft : const Color(0xFFEFE8E3),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: enabled ? onPressed : null,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: enabled ? AppTokens.primary : AppTokens.textTertiary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: AppTokens.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        height: 1.2,
      ),
    );
  }
}

/// Figma：40 圆底、黑 8% 透明 + ✕
class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x14000000),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onPressed,
        child: const SizedBox(
          width: 40,
          height: 40,
          child: Icon(Icons.close_rounded, size: 22, color: AppTokens.textPrimary),
        ),
      ),
    );
  }
}
