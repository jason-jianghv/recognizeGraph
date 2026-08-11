import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shitu_app/screens/about_screen.dart';
import 'package:shitu_app/state/session_state.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
        title: const Text('设置'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _tile(
              context,
              title: '关于我',
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                );
              },
            ),
            const SizedBox(height: 10),
            _tile(
              context,
              title: '版本号',
              trailing: const Text(
                'v1.0.0',
                style: TextStyle(color: AppTokens.textTertiary),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: OutlinedButton(
                onPressed: () {
                  context.read<SessionState>().logout();
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTokens.danger,
                  side: const BorderSide(color: AppTokens.danger),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                child: const Text('退出登录'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required String title,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      tileColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: trailing,
    );
  }
}
