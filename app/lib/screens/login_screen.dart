import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phone = TextEditingController();
  final _code = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTokens.bgPage,
      appBar: AppBar(
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('登录识图'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '登录后，学习足迹会记在你的小空间里',
              style: TextStyle(color: AppTokens.textSecondary, fontSize: 15),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: _deco('手机号'),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _code,
                    keyboardType: TextInputType.number,
                    decoration: _deco('验证码'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('MVP 演示：验证码已假装发送～')),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(120, 52),
                    foregroundColor: AppTokens.primary,
                    side: const BorderSide(color: AppTokens.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  child: const Text('获取验证码'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            PrimaryPillButton(
              label: '登录',
              onPressed: () {
                context.read<SessionState>().login('小小探索家');
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
            const Text(
              '登录即表示同意用户协议与隐私政策',
              style: TextStyle(color: AppTokens.textTertiary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _deco(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTokens.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTokens.borderSubtle),
      ),
    );
  }
}
