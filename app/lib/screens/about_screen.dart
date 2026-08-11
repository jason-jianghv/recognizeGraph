import 'package:flutter/material.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

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
        title: const Text('关于我'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 88,
              height: 88,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTokens.primarySoft,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Text(
                '识',
                style: TextStyle(
                  color: AppTokens.primary,
                  fontSize: 36,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              '识图',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          const Center(
            child: Text(
              '版本 v1.0.0',
              style: TextStyle(color: AppTokens.textTertiary),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '识图是给小朋友用的拍照识物小助手。',
                  style: TextStyle(fontSize: 16, height: 1.5, color: AppTokens.textSecondary),
                ),
                SizedBox(height: 12),
                Text(
                  '举起镜头，认识身边的动物、植物和交通建筑，边拍边学，积累属于自己的小小百科。',
                  style: TextStyle(fontSize: 16, height: 1.5, color: AppTokens.textSecondary),
                ),
                SizedBox(height: 12),
                Text(
                  '内容适合学龄前到小学低年级，温和安全、鼓励探索。',
                  style: TextStyle(fontSize: 16, height: 1.5, color: AppTokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
