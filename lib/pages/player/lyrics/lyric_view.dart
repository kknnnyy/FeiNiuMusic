import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_lyric/core/lyric_controller.dart';
import 'package:flutter_lyric/core/lyric_style.dart';
import 'package:flutter_lyric/widgets/lyric_view.dart' as fl;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:signals_flutter/signals_flutter.dart' hide computed;

import '../../../app/services/lyrics/lyrics_service.dart';
import '../../../app/services/lyrics/lyrics_view_colors.dart';
import '../../../app/services/player_service.dart';
import '../../../app/state/settings_state.dart';
import '../../../app/tv/tv_layout.dart';
import '../../../components/index.dart';
import '../widgets/player_bottom_panel.dart';
import 'widgets/lyrics_actions_bar.dart';
import 'widgets/lyrics_drag_to_seek.dart';

class PlayerLyricsView extends StatefulWidget {
  /// 是否在歌词页底部显示播放控件与操作栏（播放页内歌词页开启，
  /// 平板横屏右栏、独立歌词页保持关闭）。
  final bool showControls;

  /// 上下边缘渐隐遮罩。
  ///
  /// 歌词在区域内上下滚动出界时会被硬截断，开启后上下边缘叠加线性渐隐，
  /// 让歌词淡出而非被直接裁掉。
  final bool fadeEdges;

  const PlayerLyricsView({
    super.key,
    this.showControls = false,
    this.fadeEdges = false,
  });

  @override
  State<PlayerLyricsView> createState() => _PlayerLyricsViewState();
}

class _PlayerLyricsViewState extends State<PlayerLyricsView> with SignalsMixin {
  static const String _prefsFontSize = 'lyrics_view_font_size';
  static const String _prefsActiveFontSize = 'lyrics_view_active_font_size';
  static const String _prefsFontFamily = 'lyrics_view_font_family';
  static const String _prefsLineGap = 'lyrics_view_line_gap';
  static const String _prefsAlignment = 'lyrics_view_alignment';
  static const String _prefsShowTranslation = 'lyrics_view_show_translation';
  static const String _prefsDragToSeek = 'lyrics_view_drag_to_seek';
  static const String _prefsDragLyrics = 'lyrics_view_drag_lyrics';
  static const String _prefsDragSeek = 'lyrics_view_drag_seek';
  static const String _prefsForceKaraoke = 'lyrics_view_force_karaoke';
  static const String _prefsInactiveColor = 'lyrics_view_inactive_color';
  static const String _prefsActiveColor = 'lyrics_view_active_color';
  static const String _prefsHighlightColor = 'lyrics_view_highlight_color';
  static const String _prefsMiniEnabled = 'mini_lyrics_enabled';
  static const String _prefsMiniAlignment = 'mini_lyrics_alignment';

  late final _showTranslation = createSignal(true);
  late final _dragLyrics = createSignal(true);
  late final _dragSeek = createSignal(true);
  late final _forceKaraoke = createSignal(false);
  late final _miniEnabled = createSignal(true);
  late final _miniAlignment = createSignal('center');
  late final _fontSize = createSignal(18.0);
  late final _activeFontSize = createSignal(24.0);
  late final _fontFamily = createSignal('');
  late final _lineGap = createSignal(14.0);
  late final _alignment = createSignal('center');
  late final _inactiveColorValue = createSignal<int?>(null);
  late final _activeColorValue = createSignal<int?>(null);
  late final _highlightColorValue = createSignal<int?>(null);
  late final _selectionCentered = createSignal(false);

  /// 拖动歌词（scrub）状态：拖动中完全关闭远端虚化，停止拖动 3s 后恢复。
  late final _scrubbing = createSignal(false);
  Timer? _scrubResumeTimer;

  /// 停止拖动后恢复「播放中」虚化状态的延时。
  static const _scrubResumeDelay = Duration(seconds: 3);
  VoidCallback? _unregisterResumeSelectedLine;
  VoidCallback? _unregisterStopSelection;
  bool _tapSeekEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    final controller = LyricsService.instance.controller;
    controller.selectedIndexNotifier.addListener(_onSelectionIndexChange);
    controller.isSelectingNotifier.addListener(_onSelectingChange);
    _unregisterResumeSelectedLine = controller.registerEvent(
      LyricEvent.resumeSelectedLine,
      (_) {
        if (!mounted) return;
        _selectionCentered.value = true;
        // 拖动已停稳：3s 后回到「播放中」的远端虚化状态。
        _scheduleScrubResume();
      },
    );
    _unregisterStopSelection = controller.registerEvent(
      LyricEvent.stopSelection,
      (_) {
        if (!mounted) return;
        _selectionCentered.value = false;
      },
    );
  }

  @override
  void dispose() {
    final controller = LyricsService.instance.controller;
    controller.selectedIndexNotifier.removeListener(_onSelectionIndexChange);
    controller.isSelectingNotifier.removeListener(_onSelectingChange);
    _unregisterResumeSelectedLine?.call();
    _unregisterStopSelection?.call();
    _scrubResumeTimer?.cancel();
    // 释放全局拖动选中状态：LyricController 是全局单例，若歌词页销毁时
    // 仍处于拖动选中（isSelecting=true / selectedIndex 指向拖到的行），
    // 残留状态会传染给其它共享 controller 的歌词预览（如封面页底栏迷你
    // 歌词、海报预览），表现为「左滑回封面页时左边也被选中」。
    controller.stopSelection();
    super.dispose();
  }

  void _onSelectionIndexChange() {
    _selectionCentered.value = false;
    // 拖动中（选中行在变）：保持「完全不虚化」，并顺延恢复计时。
    _scrubbing.value = true;
    _scheduleScrubResume();
  }

  void _onSelectingChange() {
    final selecting =
        LyricsService.instance.controller.isSelectingNotifier.value;
    if (!selecting) {
      _selectionCentered.value = false;
      _scrubResumeTimer?.cancel();
      _scrubbing.value = false;
      return;
    }
    // 开始拖动：完全关闭远端虚化（歌词全部锐利），停止拖动 3s 后恢复。
    _scrubbing.value = true;
    _scheduleScrubResume();
  }

  /// 停止拖动 [_scrubResumeDelay] 后恢复「播放中」的远端虚化状态。
  void _scheduleScrubResume() {
    _scrubResumeTimer?.cancel();
    _scrubResumeTimer = Timer(_scrubResumeDelay, () {
      if (!mounted) return;
      final controller = LyricsService.instance.controller;
      // 手指仍在拖动（选中行未停稳）：继续保持不虚化，等下一次「停稳」
      // 事件重新计时。
      if (controller.isSelectingNotifier.value &&
          !_selectionCentered.value) {
        _scrubbing.value = true;
        return;
      }
      _scrubbing.value = false;
    });
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    _showTranslation.value = prefs.getBool(_prefsShowTranslation) ?? true;
    final legacyDrag = prefs.getBool(_prefsDragToSeek);
    _dragLyrics.value = prefs.getBool(_prefsDragLyrics) ?? legacyDrag ?? true;
    _dragSeek.value = prefs.getBool(_prefsDragSeek) ?? legacyDrag ?? true;
    _forceKaraoke.value = prefs.getBool(_prefsForceKaraoke) ?? false;
    _miniEnabled.value = prefs.getBool(_prefsMiniEnabled) ?? true;
    _miniAlignment.value = prefs.getString(_prefsMiniAlignment) ?? 'center';
    _fontSize.value = switch (prefs.getDouble(_prefsFontSize)) {
      null => 18,
      // 旧默认 16 迁移为参考 APK 观感的 18（用户显式设置其它值则保留）。
      16.0 => 18,
      final v => v,
    };
    _activeFontSize.value = switch (prefs.getDouble(_prefsActiveFontSize)) {
      null => 24,
      // 旧默认 20 迁移为参考 APK 观感的 24。
      20.0 => 24,
      final v => v,
    };
    _fontFamily.value = prefs.getString(_prefsFontFamily) ?? '';
    _lineGap.value = prefs.getDouble(_prefsLineGap) ?? 14;
    _alignment.value = prefs.getString(_prefsAlignment) ?? 'center';
    _inactiveColorValue.value = prefs.getInt(_prefsInactiveColor);
    _activeColorValue.value = prefs.getInt(_prefsActiveColor);
    _highlightColorValue.value = prefs.getInt(_prefsHighlightColor);
  }

  Future<void> _setPrefBool(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
    LyricsService.instance.notifyViewSettingsChanged();
  }

  Future<void> _setPrefDouble(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
    LyricsService.instance.notifyViewSettingsChanged();
  }

  Future<void> _setPrefString(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value);
    LyricsService.instance.notifyViewSettingsChanged();
  }

  Future<void> _setPrefColor(String key, Color? color) async {
    final prefs = await SharedPreferences.getInstance();
    if (color == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, color.toARGB32());
    }
    LyricsService.instance.notifyViewSettingsChanged();
  }

  Future<void> _openColorPicker({
    required String title,
    required Color initialColor,
    required ValueChanged<Color?> onSelected,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return _LyricsColorPickerDialog(
          title: title,
          initialColor: initialColor,
          onSelected: onSelected,
        );
      },
    );
  }

  TextAlign _lineTextAlign() {
    switch (_alignment.value) {
      case 'left':
        return TextAlign.left;
      case 'right':
        return TextAlign.right;
      default:
        return TextAlign.center;
    }
  }

  CrossAxisAlignment _contentAlignment() {
    switch (_alignment.value) {
      case 'left':
        return CrossAxisAlignment.start;
      case 'right':
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.center;
    }
  }

  void _openLyricsSettingsSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.55,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          snap: true,
          builder: (context, scrollController) {
            return Watch.builder(
              builder: (context) {
                final fontSize = _fontSize.value;
                final activeFontSize = _activeFontSize.value;
                final fontFamily = _fontFamily.value;
                final lineGap = _lineGap.value;
                final alignment = _alignment.value;
                final dragLyrics = _dragLyrics.value;
                final dragSeek = _dragSeek.value;
                final forceKaraoke = _forceKaraoke.value;
                final miniEnabled = _miniEnabled.value;
                final miniAlignment = _miniAlignment.value;
                final inactiveColorValue = _inactiveColorValue.value;
                final activeColorValue = _activeColorValue.value;
                final highlightColorValue = _highlightColorValue.value;
                return AppSheetPanel(
                  title: '歌词设置',
                  expand: true,
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppSettingSection(
                          title: '样式',
                          showDividers: false,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: SystemFontPicker(
                                label: '歌词字体',
                                value: fontFamily,
                                onChanged: (value) {
                                  _fontFamily.value = value;
                                  _setPrefString(_prefsFontFamily, value);
                                },
                              ),
                            ),
                            LabeledSlider(
                              title: '字号',
                              value: fontSize,
                              min: 14.0,
                              max: 32.0,
                              divisions: 9,
                              valueText: fontSize.toStringAsFixed(0),
                              onChanged: (v) => _fontSize.value = v,
                              onChangeEnd: (v) =>
                                  _setPrefDouble(_prefsFontSize, v),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                            ),
                            LabeledSlider(
                              title: '播放字号',
                              value: activeFontSize,
                              min: 16.0,
                              max: 48.0,
                              divisions: 16,
                              valueText: activeFontSize.toStringAsFixed(0),
                              onChanged: (v) => _activeFontSize.value = v,
                              onChangeEnd: (v) =>
                                  _setPrefDouble(_prefsActiveFontSize, v),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                            ),
                            LabeledSlider(
                              title: '行距',
                              value: lineGap,
                              min: 8.0,
                              max: 32.0,
                              divisions: 12,
                              valueText: lineGap.toStringAsFixed(0),
                              onChanged: (v) => _lineGap.value = v,
                              onChangeEnd: (v) =>
                                  _setPrefDouble(_prefsLineGap, v),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                12,
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                              child: SizedBox(
                                width: double.infinity,
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                      value: 'left',
                                      label: Text('居左'),
                                      icon: Icon(Icons.format_align_left),
                                    ),
                                    ButtonSegment(
                                      value: 'center',
                                      label: Text('居中'),
                                      icon: Icon(Icons.format_align_center),
                                    ),
                                    ButtonSegment(
                                      value: 'right',
                                      label: Text('居右'),
                                      icon: Icon(Icons.format_align_right),
                                    ),
                                  ],
                                  selected: {alignment},
                                  onSelectionChanged: (selection) {
                                    final v = selection.first;
                                    _alignment.value = v;
                                    _setPrefString(_prefsAlignment, v);
                                  },
                                  showSelectedIcon: false,
                                ),
                              ),
                            ),
                            _LyricsColorSettingTile(
                              title: '普通歌词颜色',
                              color: inactiveColorValue == null
                                  ? null
                                  : Color(inactiveColorValue),
                              onTap: () {
                                final fallback =
                                    LyricsViewColors.defaultInactiveColor(
                                      context,
                                    );
                                _openColorPicker(
                                  title: '普通歌词颜色',
                                  initialColor: inactiveColorValue == null
                                      ? fallback
                                      : Color(inactiveColorValue),
                                  onSelected: (color) {
                                    _inactiveColorValue.value = color
                                        ?.toARGB32();
                                    _setPrefColor(_prefsInactiveColor, color);
                                  },
                                );
                              },
                              onReset: inactiveColorValue == null
                                  ? null
                                  : () {
                                      _inactiveColorValue.value = null;
                                      _setPrefColor(_prefsInactiveColor, null);
                                    },
                            ),
                            _LyricsColorSettingTile(
                              title: '当前歌词颜色',
                              color: activeColorValue == null
                                  ? null
                                  : Color(activeColorValue),
                              onTap: () {
                                final fallback =
                                    LyricsViewColors.defaultActiveColor(
                                      context,
                                    );
                                _openColorPicker(
                                  title: '当前歌词颜色',
                                  initialColor: activeColorValue == null
                                      ? fallback
                                      : Color(activeColorValue),
                                  onSelected: (color) {
                                    _activeColorValue.value = color?.toARGB32();
                                    _setPrefColor(_prefsActiveColor, color);
                                  },
                                );
                              },
                              onReset: activeColorValue == null
                                  ? null
                                  : () {
                                      _activeColorValue.value = null;
                                      _setPrefColor(_prefsActiveColor, null);
                                    },
                            ),
                            _LyricsColorSettingTile(
                              title: '逐字高亮颜色',
                              color: highlightColorValue == null
                                  ? null
                                  : Color(highlightColorValue),
                              onTap: () {
                                final fallback =
                                    LyricsViewColors.defaultHighlightColor(
                                      context,
                                    );
                                _openColorPicker(
                                  title: '逐字高亮颜色',
                                  initialColor: highlightColorValue == null
                                      ? fallback
                                      : Color(highlightColorValue),
                                  onSelected: (color) {
                                    _highlightColorValue.value = color
                                        ?.toARGB32();
                                    _setPrefColor(_prefsHighlightColor, color);
                                  },
                                );
                              },
                              onReset: highlightColorValue == null
                                  ? null
                                  : () {
                                      _highlightColorValue.value = null;
                                      _setPrefColor(_prefsHighlightColor, null);
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppSettingSection(
                          title: '交互',
                          showDividers: false,
                          children: [
                            AppSettingSwitchTile(
                              title: '拖动歌词',
                              value: dragLyrics,
                              onChanged: (v) {
                                _dragLyrics.value = v;
                                _setPrefBool(_prefsDragLyrics, v);
                              },
                            ),
                            if (dragLyrics)
                              AppSettingSwitchTile(
                                title: '拖动调节进度',
                                value: dragSeek,
                                onChanged: (v) {
                                  _dragSeek.value = v;
                                  _setPrefBool(_prefsDragSeek, v);
                                },
                              ),
                            AppSettingSwitchTile(
                              title: '强制逐字',
                              subtitle: '对非逐字歌词进行逐字处理',
                              value: forceKaraoke,
                              onChanged: (v) async {
                                _forceKaraoke.value = v;
                                await _setPrefBool(_prefsForceKaraoke, v);
                                await LyricsService.instance.refreshSettings();
                                LyricsService.instance.reloadCurrentSong();
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AppSettingSection(
                          title: '三行歌词',
                          showDividers: false,
                          children: [
                            AppSettingSwitchTile(
                              title: '显示三行歌词',
                              value: miniEnabled,
                              onChanged: (v) {
                                _miniEnabled.value = v;
                                _setPrefBool(_prefsMiniEnabled, v);
                              },
                            ),
                            if (miniEnabled)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  4,
                                  16,
                                  12,
                                ),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: SegmentedButton<String>(
                                    segments: const [
                                      ButtonSegment(
                                        value: 'left',
                                        label: Text('居左'),
                                        icon: Icon(Icons.format_align_left),
                                      ),
                                      ButtonSegment(
                                        value: 'center',
                                        label: Text('居中'),
                                        icon: Icon(Icons.format_align_center),
                                      ),
                                      ButtonSegment(
                                        value: 'right',
                                        label: Text('居右'),
                                        icon: Icon(Icons.format_align_right),
                                      ),
                                    ],
                                    selected: {miniAlignment},
                                    onSelectionChanged: (selection) {
                                      final v = selection.first;
                                      _miniAlignment.value = v;
                                      _setPrefString(_prefsMiniAlignment, v);
                                    },
                                    showSelectedIcon: false,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final onSurface = scheme.onSurface;
    final player = PlayerService.instance;
    final lyrics = LyricsService.instance;

    return Watch.builder(
      builder: (context) {
        final dragLyrics = _dragLyrics.value;
        final dragSeek = _dragSeek.value;
        final showTranslation = _showTranslation.value;
        final forceKaraoke = _forceKaraoke.value;
        final fontSizeScale = AppLayoutSettings.tvMode.value
            ? TvLayout.uiScale(context)
            : 1.0;
        final rawFontSize = _fontSize.value;
        final rawActiveFontSize = _activeFontSize.value;
        final configuredFontFamily = _fontFamily.value.trim();
        final fontFamily = configuredFontFamily.isEmpty
            ? null
            : configuredFontFamily;
        final rawLineGap = _lineGap.value;
        final fontSize = rawFontSize * fontSizeScale;
        final activeFontSize = rawActiveFontSize * fontSizeScale;
        final lineGap = rawLineGap * fontSizeScale;
        final snap = lyrics.snapshotSignal.value;
        final isPlaying = player.isPlayingSignal.value;
        final model = lyrics.lyricModelSignal.value;
        final selecting = lyrics.isSelectingSignal.value;
        final centered = _selectionCentered.value;
        final scrubbing = _scrubbing.value;
        final index = lyrics.selectedIndexSignal.value;
        if (dragSeek != _tapSeekEnabled) {
          _tapSeekEnabled = dragSeek;
          if (dragSeek) {
            lyrics.controller.setOnTapLineCallback((pos) {
              lyrics.controller.stopSelection();
              player.seek(pos);
            });
          } else {
            lyrics.controller.cancelOnTapLineCallback();
          }
        }
        final hasTranslation =
            model?.lines.any(
              (line) => (line.translation ?? '').trim().isNotEmpty,
            ) ??
            false;

        return Column(
          children: [
            Expanded(
              // 上下边缘渐隐遮罩：fadeEdges 关闭时全白（dstIn 无效果），
              // 开启时上下各约 22% 高度淡出，歌词滑出边界不被硬截断。
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0.0, 0.22, 0.78, 1.0],
                  colors: widget.fadeEdges
                      ? const [
                          Colors.transparent,
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ]
                      : const [
                          Colors.white,
                          Colors.white,
                          Colors.white,
                          Colors.white,
                        ],
                ).createShader(rect),
                child: LyricsDragToSeek(
                  enabled: dragLyrics,
                  player: player,
                  lyrics: lyrics,
                  child: () {
                    final hasLines = model?.lines.isNotEmpty ?? false;
                    if (snap.status == LyricsLoadStatus.loading && !hasLines) {
                      return const SizedBox.shrink();
                    }
                    if (!hasLines) {
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '暂无歌词',
                              style: TextStyle(
                                fontFamily: fontFamily,
                                fontSize: 16,
                                color: onSurface.withValues(alpha: 0.8),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '纯音乐或未匹配到歌词',
                              style: TextStyle(
                                fontFamily: fontFamily,
                                fontSize: 14,
                                color: onSurface.withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      );
                    }
                    final hasKaraokeWords = model!.lines.any(
                      (line) => line.words?.isNotEmpty ?? false,
                    );
                    final karaokeMode = forceKaraoke || hasKaraokeWords;
                    final inactiveColor = LyricsViewColors.customColorOrDefault(
                      _inactiveColorValue.value,
                      LyricsViewColors.defaultInactiveColor(context),
                    );
                    final activeColor = LyricsViewColors.customColorOrDefault(
                      _activeColorValue.value,
                      LyricsViewColors.defaultActiveColor(context),
                    );
                    final highlightColor =
                        LyricsViewColors.customColorOrDefault(
                          _highlightColorValue.value,
                          LyricsViewColors.defaultHighlightColor(context),
                        );
                    final isLight = theme.brightness == Brightness.light;
                    final karaokeBaseColor = LyricsViewColors.karaokeBaseColor(
                      context,
                      inactiveColor: inactiveColor,
                    );

                    final translationStyle = showTranslation
                        ? TextStyle(
                            fontFamily: fontFamily,
                            color: isLight
                                ? const Color(0xFF7A7A7A)
                                : onSurface.withValues(alpha: 0.35),
                            fontSize: fontSize * 0.85,
                            height: 1.2,
                          )
                        : const TextStyle(
                            color: Colors.transparent,
                            fontSize: 0,
                            height: 0,
                          );

                    final style = LyricStyle(
                      textStyle: TextStyle(
                        fontFamily: fontFamily,
                        color: inactiveColor,
                        fontSize: fontSize,
                        height: 1.3,
                      ),
                      activeStyle: TextStyle(
                        fontFamily: fontFamily,
                        // karaokeBaseColor 仅在用户显式开启「强制卡拉OK」
                        // 时使用；自动 karaoke（词级数据）走整行 activeColor
                        // ——参考 APK 当前行观感即整行纯色常亮，无扫色
                        // 分界。扫色渐变走 srcIn 全行重涂，会把文字抗锯齿
                        // 边缘强制涂成实色（笔画外扩发白），是当前行白晕
                        // 的根因。
                        color: (forceKaraoke && karaokeMode)
                            ? karaokeBaseColor
                            : activeColor,
                        fontSize: activeFontSize,
                        // 参考 APK 当前行笔画为中等字重；w700 过粗白字在
                        // 暗背景上泛光（观感即「笔画周围发白」）。
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                      translationStyle: translationStyle,
                      translationActiveColor: showTranslation
                          ? onSurface.withValues(alpha: 0.9)
                          : Colors.transparent,
                      lineTextAlign: _lineTextAlign(),
                      contentAlignment: _contentAlignment(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      lineGap: lineGap,
                      translationLineGap: showTranslation ? 8 : 0,
                      selectionAnchorPosition: 0.5,
                      activeAnchorPosition: 0.5,
                      selectionAlignment: MainAxisAlignment.center,
                      activeAlignment: MainAxisAlignment.center,
                      scrollDuration: const Duration(milliseconds: 380),
                      scrollCurve: Curves.easeOutCubic,
                      selectedColor: activeColor,
                      selectedTranslationColor: onSurface.withValues(
                        alpha: 0.9,
                      ),
                      selectionAutoResumeDuration: const Duration(
                        milliseconds: 200,
                      ),
                      activeAutoResumeDuration: isPlaying
                          ? const Duration(seconds: 3)
                          : const Duration(days: 365),
                      disableTouchEvent: !dragLyrics,
                      enableSwitchAnimation: false,
                      // 扫色渐变仅限用户显式开启「强制卡拉OK」：srcIn 全行
                      // 重涂会破坏文字边缘 alpha（白晕），自动 karaoke 一律
                      // 整行常亮（对齐参考 APK）。
                      activeHighlightGradient: (forceKaraoke && karaokeMode)
                          ? LinearGradient(
                              colors: [
                                highlightColor.withValues(alpha: 1.0),
                                highlightColor.withValues(alpha: 1.0),
                              ],
                            )
                          : null,
                      activeHighlightExtraFadeWidth: 0,
                      // 远端虚化（APK 效果）：按与当前播放行的「行距」逐行
                      // 变模糊 + 变淡。模糊作用在文字内容本身（插件内
                      // saveLayer + ImageFilter），不采样页面背景——背景采样
                      // 会把底色与亮色文字一起重绘成不透明色块，观感即
                      // 「字体发白、蒙一层白雾」。当前行与相邻行保持锐利。
                      // 过渡区间放得较宽（2~8 行），远端仍保留 88% 不透明度，
                      // 只做一点点景深提示，不影响远端歌词的可读性。
                      // 拖动歌词（scrub）期间完全关闭虚化：歌词全部锐利，
                      // 停止拖动 3s 后自动回到播放态的虚化效果。
                      defocusSigma: widget.fadeEdges && !scrubbing ? 1.8 : 0,
                      defocusStartDistance: 2.0,
                      defocusEndDistance: 8.0,
                      defocusMinOpacity: scrubbing ? 1.0 : 0.88,
                    );
                    return Stack(
                      children: [
                        // 参考 APK（飞牛音乐）歌词页「镜头失焦·远端虚化」：
                        // 当前行整行加粗常亮、锐利；越远离当前行的歌词越模糊、
                        // 越淡，直到融进背景。逐行虚化由插件内按「行距」实现
                        // （saveLayer + ImageFilter，只作用于文字内容本身），
                        // 这里只保留一层很轻的视口边缘渐隐，避免歌词被视口硬切。
                        // 关键：绝不使用 BackdropFilter / ProgressiveBlur——它
                        // 采样的是整块背景，会把页面底色与亮色文字一起模糊后
                        // 以不透明方式重绘回该区域，观感即「字体发白、蒙一层
                        // 白雾」（本次要修掉的正是这个问题）。
                        if (widget.fadeEdges)
                          ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) {
                              Color a(double v) =>
                                  Colors.white.withValues(alpha: v);
                              return LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  a(0),
                                  a(0.35),
                                  a(1),
                                  a(1),
                                  a(0.35),
                                  a(0),
                                ],
                                stops: const [
                                  0.0,
                                  0.04,
                                  0.12,
                                  0.88,
                                  0.96,
                                  1.0,
                                ],
                              ).createShader(bounds);
                            },
                            child: fl.LyricView(
                              controller: lyrics.controller,
                              style: style,
                            ),
                          )
                        else
                          fl.LyricView(
                            controller: lyrics.controller,
                            style: style,
                          ),
                        if (!dragLyrics || !selecting)
                          const SizedBox.shrink()
                        else
                          Align(
                            alignment: Alignment.center,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              child: SizedBox(
                                height: 44,
                                child: () {
                                  final m = model;
                                  final showDetails =
                                      index >= 0 && index < m.lines.length;
                                  final timeText = showDetails
                                      ? "${m.lines[index].start.inMinutes.toString().padLeft(2, '0')}:${(m.lines[index].start.inSeconds % 60).toString().padLeft(2, '0')}"
                                      : '';
                                  return Row(
                                    children: [
                                      if (showDetails)
                                        Text(
                                          timeText,
                                          style: TextStyle(
                                            color: activeColor,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      if (showDetails) const SizedBox(width: 8),
                                      Expanded(
                                        child: Container(
                                          height: 1,
                                          // 拖动（scrub）期间隐藏横线，只留时间提示，
                                          // 避免细线横穿歌词造成视觉干扰。
                                          color: (scrubbing || centered)
                                              ? Colors.transparent
                                              : onSurface.withValues(
                                                  alpha: 0.25,
                                                ),
                                        ),
                                      ),
                                      if (showDetails) const SizedBox(width: 8),
                                      // 拖动期间保留播放键：它是「从这里播放」的
                                      // 唯一入口，隐藏后拖动中无法确认/使用。
                                      if (showDetails && dragSeek)
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onTap: () {
                                            if (index < 0 ||
                                                index >= m.lines.length) {
                                              return;
                                            }
                                            final start = m.lines[index].start;
                                            lyrics.controller.stopSelection();
                                            player.seek(start);
                                          },
                                          child: Icon(
                                            Icons.play_arrow_rounded,
                                            size: 32,
                                            color: activeColor,
                                          ),
                                        ),
                                    ],
                                  );
                                }(),
                              ),
                            ),
                          ),
                      ],
                    );
                  }(),
                ),
              ),
            ),
            // 词/译 切换栏
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: LyricsActionsBar(
                hasTranslation: hasTranslation,
                showTranslation: showTranslation,
                onOpenSettings: _openLyricsSettingsSheet,
                onToggleTranslation: () {
                  _showTranslation.value = !showTranslation;
                  _setPrefBool(_prefsShowTranslation, _showTranslation.value);
                },
                color: onSurface,
              ),
            ),
            // 播放控件 + 底部操作栏（可选，播放页内歌词页开启）
            if (widget.showControls) ..._buildControlsArea(context),
          ],
        );
      },
    );
  }

  List<Widget> _buildControlsArea(BuildContext context) {
    final player = PlayerService.instance;
    final stylePreset = PlayerStyleSettings.stylePreset.value;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomSpacing = bottomInset > 20 ? bottomInset + 16.0 : 24.0;
    final Widget controls;
    if (stylePreset == PlayerStylePreset.poster) {
      // 海报模式：与封面页海报布局一致（模式 + 上一首/播放/下一首 + 更多）
      controls = PosterControls(player: player);
    } else {
      // 经典模式：播放控件 + 底部操作栏
      controls = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          PlayerControls(player: player, stylePreset: stylePreset),
          const SizedBox(height: 20),
          BottomActions(player: player, stylePreset: stylePreset),
        ],
      );
    }
    return [controls, SizedBox(height: bottomSpacing)];
  }
}

class _LyricsColorSettingTile extends StatelessWidget {
  final String title;
  final Color? color;
  final VoidCallback onTap;
  final VoidCallback? onReset;

  const _LyricsColorSettingTile({
    required this.title,
    required this.color,
    required this.onTap,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Text(title),
      subtitle: Text(color == null ? '跟随默认样式' : '自定义颜色'),
      onTap: onTap,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color ?? scheme.surfaceContainerHighest,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: color == null
                ? Icon(
                    Icons.auto_awesome,
                    size: 14,
                    color: scheme.onSurfaceVariant,
                  )
                : null,
          ),
          if (onReset != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: '恢复默认',
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _LyricsColorPickerDialog extends StatefulWidget {
  final String title;
  final Color initialColor;
  final ValueChanged<Color?> onSelected;

  const _LyricsColorPickerDialog({
    required this.title,
    required this.initialColor,
    required this.onSelected,
  });

  @override
  State<_LyricsColorPickerDialog> createState() =>
      _LyricsColorPickerDialogState();
}

class _LyricsColorPickerDialogState extends State<_LyricsColorPickerDialog> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.initialColor);
  }

  void _updateSaturationValue(Offset localPosition, double size) {
    final dx = localPosition.dx.clamp(0.0, size);
    final dy = localPosition.dy.clamp(0.0, size);
    setState(() {
      _hsv = _hsv
          .withSaturation((dx / size).clamp(0.0, 1.0))
          .withValue((1 - dy / size).clamp(0.0, 1.0));
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final preview = _hsv.toColor();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Spacer(),
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: preview,
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final size = constraints.maxWidth;
                  return GestureDetector(
                    onPanDown: (details) =>
                        _updateSaturationValue(details.localPosition, size),
                    onPanUpdate: (details) =>
                        _updateSaturationValue(details.localPosition, size),
                    child: Stack(
                      children: [
                        SizedBox(
                          width: size,
                          height: size,
                          child: CustomPaint(
                            painter: _LyricsSaturationValuePainter(
                              hue: _hsv.hue,
                            ),
                          ),
                        ),
                        Positioned(
                          left: _hsv.saturation * size - 10,
                          top: (1 - _hsv.value) * size - 10,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.onSurface,
                                width: 2,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.2),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              _LyricsHueSlider(
                value: _hsv.hue,
                onChanged: (value) {
                  setState(() {
                    _hsv = _hsv.withHue(value);
                  });
                },
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      widget.onSelected(null);
                      Navigator.pop(context);
                    },
                    child: const Text('默认'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  TextButton(
                    onPressed: () {
                      widget.onSelected(preview);
                      Navigator.pop(context);
                    },
                    child: const Text('确定'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LyricsSaturationValuePainter extends CustomPainter {
  final double hue;

  _LyricsSaturationValuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final baseColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [Colors.white, baseColor],
        ).createShader(rect),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _LyricsSaturationValuePainter oldDelegate) {
    return oldDelegate.hue != hue;
  }
}

class _LyricsHueSlider extends StatefulWidget {
  final double value;
  final ValueChanged<double> onChanged;

  const _LyricsHueSlider({required this.value, required this.onChanged});

  @override
  State<_LyricsHueSlider> createState() => _LyricsHueSliderState();
}

class _LyricsHueSliderState extends State<_LyricsHueSlider> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final displayValue = _dragValue ?? widget.value;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanDown: (details) => _updateValue(details.localPosition.dx, width),
          onPanUpdate: (details) =>
              _updateValue(details.localPosition.dx, width),
          onPanEnd: (_) => setState(() => _dragValue = null),
          child: SizedBox(
            height: 28,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 12,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFFFF0000),
                        Color(0xFFFFFF00),
                        Color(0xFF00FF00),
                        Color(0xFF00FFFF),
                        Color(0xFF0000FF),
                        Color(0xFFFF00FF),
                        Color(0xFFFF0000),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: (displayValue / 360 * width) - 10,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: HSVColor.fromAHSV(1, displayValue, 1, 1).toColor(),
                      border: Border.all(color: scheme.onSurface, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.2),
                          blurRadius: 6,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _updateValue(double dx, double width) {
    final clamped = dx.clamp(0.0, width);
    final next = (clamped / width * 360).clamp(0.0, 360.0);
    setState(() {
      _dragValue = next;
    });
    widget.onChanged(next);
  }
}
