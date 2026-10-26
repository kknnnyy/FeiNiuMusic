import 'package:flutter/material.dart';

import '../../../app/state/settings_layout_state.dart';
import '../../../app/tv/tv_layout.dart';
import '../../../components/common/glass_gate.dart';
import '../../../components/common/native_liquid_glass.dart';

/// 首页功能入口卡片数据
class HomeShortcutItem {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  /// 快捷菜单的强调色，用于图标与选中态。
  final Color accent;

  const HomeShortcutItem({
    required this.icon,
    required this.label,
    this.onTap,
    this.accent = const Color(0xFF3B82F6),
  });
}

/// 首页快捷菜单 — 歌曲 / 歌手 / 专辑 / 风格。
///
/// 默认 4×1 一行排列（手机端）；`grid2x2` 时改为 2×2 四宫格（大屏顶部右侧），
/// 每个条目是圆形图标 + 文字标签，点击跳对应库页面。
class HomeShortcutMenu extends StatelessWidget {
  final List<HomeShortcutItem> items;

  /// 是否用 2×2 四宫格布局（大屏首页顶部右侧）。
  final bool grid2x2;

  const HomeShortcutMenu({
    super.key,
    required this.items,
    this.grid2x2 = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    if (grid2x2) {
      return Column(
        children: [
          for (var r = 0; r < 2; r++) ...[
            if (r > 0) const SizedBox(height: 8),
            Row(
              children: [
                for (var c = 0; c < 2; c++) ...[
                  if (c > 0) const SizedBox(width: 8),
                  Expanded(
                    child: _ShortcutItem(
                      item: items[r * 2 + c],
                      scheme: scheme,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: _ShortcutItem(item: items[i], scheme: scheme),
          ),
        ],
      ],
    );
  }
}

class _ShortcutItem extends StatelessWidget {
  final HomeShortcutItem item;
  final ColorScheme scheme;

  const _ShortcutItem({required this.item, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final accent = item.accent;
    final scale = AppLayoutSettings.tvMode.value
        ? TvLayout.uiScale(context)
        : 1.0;
    final iconSize = 44.0 * scale;
    // 卡片内容层（玻璃分支与原分支共用）。
    final content = Padding(
      padding: EdgeInsets.symmetric(vertical: 12 * scale),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 圆形图标容器
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(item.icon, size: iconSize * 0.5, color: accent),
          ),
          SizedBox(height: 6 * scale),
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12 * scale,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
    // 四宫格项是 Material + InkWell：本身可聚焦（Material 自带焦点环 +
    // 主题 focusColor 高亮），聚焦范围即完整卡片。不再包 TvFocusable
    // 缩放/描边，避免聚焦范围只剩图标一小块、右侧空白。
    return GlassGate(
      original: Material(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: item.onTap,
          child: content,
        ),
      ),
      // 玻璃变体：原生玻璃背景 + 内容层（玻璃面不参与命中，触摸落在
      // 内容层的 InkWell 上）。内容层 SizedBox 撑满宽度：Stack 给非
      // positioned 子项的是宽松约束，Material 会收缩到内容宽度导致内容
      // 贴左不居中（原分支 Material 被 Expanded 拉满宽度）。
      glass: Stack(
        children: [
          const Positioned.fill(child: NativeGlassSurface(borderRadius: 16)),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: item.onTap,
              child: SizedBox(width: double.infinity, child: content),
            ),
          ),
        ],
      ),
    );
  }
}
