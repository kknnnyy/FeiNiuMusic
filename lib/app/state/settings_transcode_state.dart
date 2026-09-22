import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 转码输出格式。
///
/// [flac] 仅为旧版本配置和兼容测试保留，不再作为用户可选目标格式。
enum TranscodeFormat { opus, mp3, flac }

/// 转码设置。
///
/// 语义（用户确认）：
/// - [enabled]「开启转码」：关 → 全部不转码（直连）；开 → 进入转码逻辑。
/// - [transcodeAll]「全部转码」：开 → **所有文件都转码**（含 DSF/APE/WMA 等
///   无损，忽略 [thresholdMb]）；关 → 仅超过 [thresholdMb] 的文件转码。
/// - [thresholdMb]「转码文件大小」：默认 80MB（20–500），仅「全部转码」关闭
///   时生效；未识别大小的文件不转码。
/// - [format]「转码格式」：默认 OPUS，其次 MP3；不提供 FLAC 目标，避免无损源
///   做无意义的无损转码。
/// - [directOnWifi]「Wi-Fi 下直连」：默认关闭；开启后仅自动转码在 Wi-Fi 下
///   跳过，单曲手动指定转码格式仍然生效。
class AppTranscodeSettings {
  static const String _prefsEnabled = 'transcode_enabled';
  static const String _prefsTranscodeAll = 'transcode_all';
  static const String _prefsThresholdMb = 'transcode_threshold_mb';
  static const String _prefsFormat = 'transcode_format';
  static const String _prefsDirectOnWifi = 'transcode_direct_on_wifi';

  static const int defaultThresholdMb = 80;
  static const int minThresholdMb = 20;
  static const int maxThresholdMb = 500;

  /// 用户可选择的转码目标格式。FLAC 仅保留用于读取旧配置/兼容旧会话。
  static const availableFormats = <TranscodeFormat>[
    TranscodeFormat.opus,
    TranscodeFormat.mp3,
  ];

  static final ValueNotifier<bool> enabled = ValueNotifier(false);
  static final ValueNotifier<bool> transcodeAll = ValueNotifier(true);
  static final ValueNotifier<int> thresholdMb = ValueNotifier(defaultThresholdMb);
  static final ValueNotifier<TranscodeFormat> format =
      ValueNotifier(TranscodeFormat.opus);
  static final ValueNotifier<bool> directOnWifi = ValueNotifier(false);

  static Future<void>? _loading;

  static Future<void> ensureLoaded() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    final prefs = await SharedPreferences.getInstance();
    enabled.value = prefs.getBool(_prefsEnabled) ?? false;
    transcodeAll.value = prefs.getBool(_prefsTranscodeAll) ?? true;
    thresholdMb.value =
        (prefs.getInt(_prefsThresholdMb) ?? defaultThresholdMb)
            .clamp(minThresholdMb, maxThresholdMb);
    final saved = prefs.getString(_prefsFormat);
    format.value = switch (saved) {
      'mp3' => TranscodeFormat.mp3,
      'opus' => TranscodeFormat.opus,
      _ => TranscodeFormat.opus,
    };
    directOnWifi.value = prefs.getBool(_prefsDirectOnWifi) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsEnabled, value);
    enabled.value = value;
  }

  static Future<void> setTranscodeAll(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsTranscodeAll, value);
    transcodeAll.value = value;
  }

  static Future<void> setThresholdMb(int value) async {
    final prefs = await SharedPreferences.getInstance();
    final clamped = value.clamp(minThresholdMb, maxThresholdMb);
    await prefs.setInt(_prefsThresholdMb, clamped);
    thresholdMb.value = clamped;
  }

  static Future<void> setFormat(TranscodeFormat value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsFormat, value.name);
    format.value = value;
  }

  static Future<void> setDirectOnWifi(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsDirectOnWifi, value);
    directOnWifi.value = value;
  }

  /// 测试专用：重置内存状态（清空懒加载缓存），供测试 setUp 复用。
  static void resetForTest() {
    _loading = null;
    enabled.value = false;
    transcodeAll.value = true;
    thresholdMb.value = defaultThresholdMb;
    format.value = TranscodeFormat.opus;
    directOnWifi.value = false;
  }
}
