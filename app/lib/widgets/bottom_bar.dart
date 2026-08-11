import 'package:flutter/material.dart';
import 'package:shitu_app/theme/tokens.dart';

class ShituBottomBar extends StatelessWidget {
  const ShituBottomBar({
    super.key,
    required this.index,
    required this.onSelect,
    required this.onCamera,
  });

  final int index; // 0 explore, 1 space
  final ValueChanged<int> onSelect;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: Container(
                height: 64,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.78),
                  borderRadius: BorderRadius.circular(AppTokens.radiusPill),
                  border: Border.all(color: AppTokens.borderSubtle),
                ),
                child: Row(
                  children: [
                    _TabItem(
                      selected: index == 0,
                      icon: Icons.home_rounded,
                      label: '探索',
                      onTap: () => onSelect(0),
                    ),
                    _TabItem(
                      selected: index == 1,
                      icon: Icons.sentiment_satisfied_alt_rounded,
                      label: '空间',
                      onTap: () => onSelect(1),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Material(
              color: AppTokens.primary,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onCamera,
                child: const SizedBox(
                  width: 64,
                  height: 64,
                  child: Icon(Icons.photo_camera_rounded, color: Colors.white, size: 30),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTokens.primary : AppTokens.textSecondary;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTokens.radiusPill),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
