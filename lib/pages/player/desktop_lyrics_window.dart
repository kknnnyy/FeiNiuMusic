import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

const _desktopLyricsChannelName = 'com.feiniu.music/desktop_lyrics_window';

/// 第二个 Flutter 引擎中的桌面歌词窗口。
Future<void> runDesktopLyricsWindow(WindowController controller) async {
  await windowManager.ensureInitialized();
  const windowSize = Size(760, 112);
  const windowOptions = WindowOptions(
    size: windowSize,
    minimumSize: windowSize,
    maximumSize: windowSize,
    center: true,
    alwaysOnTop: true,
    skipTaskbar: true,
    backgroundColor: Colors.transparent,
    title: '飞牛音乐桌面歌词',
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
  });

  final state = DesktopLyricsWindowState();
  String? lastPosition;
  const channel = WindowMethodChannel(
    _desktopLyricsChannelName,
    mode: ChannelMode.bidirectional,
  );
  await channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'setState':
        if (call.arguments is Map) {
          state.update(Map<String, Object?>.from(call.arguments as Map));
        }
        return null;
      case 'show':
        await windowManager.show();
        return null;
      case 'hide':
        await windowManager.hide();
        return null;
      case 'position':
        final position = call.arguments as String?;
        if (position != lastPosition) {
          lastPosition = position;
          await _applyPosition(position);
        }
        return null;
      default:
        throw MissingPluginException('Unknown desktop lyrics method');
    }
  });

  // Parent window registers its handler before creating this window. The
  // handshake lets it flush the latest song/style payload after startup.
  unawaited(channel.invokeMethod<void>('ready'));
  runApp(DesktopLyricsWindow(state: state));
}

Future<void> _applyPosition(String? value) async {
  const positions = <String, Alignment>{
    'topLeft': Alignment.topLeft,
    'topCenter': Alignment.topCenter,
    'topRight': Alignment.topRight,
    'centerLeft': Alignment.centerLeft,
    'center': Alignment.center,
    'centerRight': Alignment.centerRight,
    'bottomLeft': Alignment.bottomLeft,
    'bottomCenter': Alignment.bottomCenter,
    'bottomRight': Alignment.bottomRight,
  };
  final alignment = positions[value];
  if (alignment != null) await windowManager.setAlignment(alignment);
}

class DesktopLyricsWindowState extends ChangeNotifier {
  Map<String, Object?> _payload = const {};

  Map<String, Object?> get payload => _payload;

  void update(Map<String, Object?> payload) {
    _payload = payload;
    notifyListeners();
  }
}

class DesktopLyricsWindow extends StatelessWidget {
  final DesktopLyricsWindowState state;

  const DesktopLyricsWindow({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, brightness: Brightness.dark),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) => _DesktopLyricsSurface(payload: state.payload),
      ),
    );
  }
}

class _DesktopLyricsSurface extends StatefulWidget {
  final Map<String, Object?> payload;

  const _DesktopLyricsSurface({required this.payload});

  @override
  State<_DesktopLyricsSurface> createState() => _DesktopLyricsSurfaceState();
}

class _DesktopLyricsSurfaceState extends State<_DesktopLyricsSurface> {
  Offset? _windowPosition;

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final current = payload['currentLine'] as String? ?? '暂无歌词';
    final next = payload['nextLine'] as String? ?? '';
    final progress = ((payload['progress'] as num?)?.toDouble() ?? 0).clamp(
      0.0,
      1.0,
    );
    final fontFamily = payload['fontFamily'] as String?;
    final fontSize = (payload['fontSize'] as num?)?.toDouble() ?? 24;
    final textColor = _color(payload['textColor'] as num?, Colors.white);
    final highlightColor = _color(
      payload['highlightColor'] as num?,
      const Color(0xFF59F7E7),
    );
    final opacity = ((payload['backgroundOpacity'] as num?)?.toDouble() ?? 0.64)
        .clamp(0.0, 0.9);

    return GestureDetector(
      onPanStart: (_) async {
        _windowPosition = await windowManager.getPosition();
      },
      onPanUpdate: (details) {
        final origin = _windowPosition;
        if (origin == null) return;
        _windowPosition = origin + details.delta;
        unawaited(windowManager.setPosition(_windowPosition!));
      },
      child: Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: opacity),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: opacity == 0
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _HighlightText(
              text: current,
              progress: progress,
              fontFamily: fontFamily,
              fontSize: fontSize,
              baseColor: textColor,
              highlightColor: highlightColor,
            ),
            if (next.trim().isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                next,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: fontFamily,
                  fontSize: fontSize * 0.68,
                  color: textColor.withValues(alpha: 0.62),
                  shadows: const [Shadow(color: Colors.black54, blurRadius: 4)],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _color(num? value, Color fallback) {
    final raw = value?.toInt();
    return raw == null ? fallback : Color(raw);
  }
}

class _HighlightText extends StatelessWidget {
  final String text;
  final double progress;
  final String? fontFamily;
  final double fontSize;
  final Color baseColor;
  final Color highlightColor;

  const _HighlightText({
    required this.text,
    required this.progress,
    required this.fontFamily,
    required this.fontSize,
    required this.baseColor,
    required this.highlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      fontWeight: FontWeight.w600,
      color: baseColor,
      shadows: const [Shadow(color: Colors.black54, blurRadius: 5)],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          alignment: Alignment.center,
          children: [
            Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: style,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: ClipRect(
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: progress,
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: style.copyWith(
                      color: highlightColor,
                      shadows: [Shadow(color: highlightColor, blurRadius: 10)],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
