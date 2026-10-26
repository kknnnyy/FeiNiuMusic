import 'package:flutter/material.dart';

import '../../../app/state/settings_state.dart';
import '../../../components/common/glass_gate.dart';
import '../../../components/common/native_liquid_glass.dart';

/// 首页功能入口卡片数据
class HomeQuickAction {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// 卡片上的「直接播放」按钮回调。为 null 时不显示按钮。
  final VoidCallback? onPlay;

  /// 卡片强调色：渐变背景 + 图标 + 播放按钮的主色调。
  /// 不同入口用不同色相，避免千篇一律。
  final Color accent;

  const HomeQuickAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onPlay,
    this.accent = const Color(0xFF3B82F6),
  });
}

/// 首页功能入口 — 收藏 / 最近播放，2×1 一行两列。
///
/// 每张卡片用专属强调色的渐变背景 + 大号水印图标（右侧背景），
/// 文字在左上，右下白色播放按钮，形成简洁的视觉焦点。
class HomeQuickActions extends StatelessWidget {
  final List<HomeQuickAction> actions;

  const HomeQuickActions({super.key, required this.actions});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < actions.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(child: _QuickActionCard(action: actions[i])),
        ],
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  final HomeQuickAction action;

  const _QuickActionCard({required this.action});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = action.accent;
    final onPlay = action.onPlay;
    final isTv = AppLayoutSettings.tvMode.value;
    final cardContent = Stack(
      children: [
        // 大号水印图标（右下背景）
        Positioned(
          right: -6,
          bottom: -14,
          child: Icon(
            action.icon,
            size: 92,
            color: accent.withValues(alpha: 0.12),
          ),
        ),
        // 文字：垂直居中（右侧留出播放按钮的空间）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 60, 0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                action.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                action.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        // 直接播放按钮 — 右下角绝对定位（白色圆底 + 强调色三角）
        if (onPlay != null)
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              width: isTv ? 48 : 38,
              height: isTv ? 48 : 38,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: onPlay,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: isTv ? 28 : 24,
                    color: accent,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    return GlassGate(
      original: Container(
        height: isTv ? 104 : 80,
        decoration: BoxDecoration(
          // 强调色渐变背景，让卡片有立体感
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.20),
              accent.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Material(
            color: Colors.transparent,
            child: InkWell(onTap: action.onTap, child: cardContent),
          ),
        ),
      ),
      // 玻璃变体：原生玻璃背景 + 内容层（水印/文字/播放按钮保持不变），
      // 实色渐变底与描边由玻璃自身高光替代。内容层 SizedBox 撑满宽度：
      // Stack 给非 positioned 子项的是宽松约束，不撑满会让内层 Stack
      // 收缩到文字宽度，右下水印/播放按钮的定位基准随之内移（原分支
      // Container 把宽高紧约束传进内容层）。
      glass: SizedBox(
        height: isTv ? 104 : 80,
        child: Stack(
          children: [
            const Positioned.fill(child: NativeGlassSurface(borderRadius: 20)),
            SizedBox(
              width: double.infinity,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(onTap: action.onTap, child: cardContent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
