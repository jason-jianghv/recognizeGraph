import 'package:flutter/material.dart';
import 'package:shitu_app/models/models.dart';
import 'package:shitu_app/screens/detail_screen.dart';
import 'package:shitu_app/theme/tokens.dart';
import 'package:shitu_app/widgets/common.dart';

class MoreListScreen extends StatelessWidget {
  const MoreListScreen({
    super.key,
    required this.title,
    required this.items,
  });

  final String title;
  final List<ExploreItem> items;

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
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: items.length,
        separatorBuilder: (_, index) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final item = items[i];
          return ListTile(
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen.fromExplore(item),
                ),
              );
            },
            tileColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: AppTokens.borderSubtle),
            ),
            leading: CircleAvatar(
              backgroundColor: AppTokens.primarySoft,
              child: Text(item.emoji, style: const TextStyle(fontSize: 22)),
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(item.oneLiner),
            trailing: const Icon(Icons.chevron_right_rounded),
          );
        },
      ),
    );
  }
}
