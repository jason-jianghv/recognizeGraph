import 'package:flutter/material.dart';
import 'package:shitu_app/theme/tokens.dart';

class SoftBackButton extends StatelessWidget {
  const SoftBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Material(
        color: AppTokens.primarySoft,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed ?? () => Navigator.of(context).maybePop(),
          child: const Center(
            child: Icon(Icons.arrow_back, color: AppTokens.textPrimary, size: 22),
          ),
        ),
      ),
    );
  }
}

class PrimaryPillButton extends StatelessWidget {
  const PrimaryPillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.expand = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final child = ElevatedButton(
      onPressed: onPressed,
      child: Text(label),
    );
    if (!expand) return child;
    return SizedBox(width: double.infinity, height: 54, child: child);
  }
}
