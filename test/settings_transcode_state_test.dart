import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/state/settings_transcode_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppTranscodeSettings.resetForTest();
  });

  test('Wi-Fi 下直连默认关闭，设置后持久化', () async {
    await AppTranscodeSettings.ensureLoaded();
    expect(AppTranscodeSettings.directOnWifi.value, isFalse);

    await AppTranscodeSettings.setDirectOnWifi(true);
    expect(AppTranscodeSettings.directOnWifi.value, isTrue);

    AppTranscodeSettings.resetForTest();
    await AppTranscodeSettings.ensureLoaded();
    expect(AppTranscodeSettings.directOnWifi.value, isTrue);
  });

  test('默认转码格式为 OPUS，旧 FLAC 配置迁移为 OPUS', () async {
    await AppTranscodeSettings.ensureLoaded();
    expect(AppTranscodeSettings.format.value, TranscodeFormat.opus);
    expect(AppTranscodeSettings.availableFormats, [
      TranscodeFormat.opus,
      TranscodeFormat.mp3,
    ]);

    SharedPreferences.setMockInitialValues({'transcode_format': 'flac'});
    AppTranscodeSettings.resetForTest();
    await AppTranscodeSettings.ensureLoaded();
    expect(AppTranscodeSettings.format.value, TranscodeFormat.opus);
  });
}
