import 'package:flutter/material.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

/// 应用内协议/政策全文页。
class LegalDocScreen extends StatelessWidget {
  const LegalDocScreen({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

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
        title: Text(title),
      ),
      body: SelectionArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
          children: [
            Text(
              body.trim(),
              style: const TextStyle(
                fontSize: 15,
                height: 1.65,
                color: AppTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
