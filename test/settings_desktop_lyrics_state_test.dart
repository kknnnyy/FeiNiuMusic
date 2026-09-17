import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:feiniu_music/app/state/settings_desktop_lyrics_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DesktopLyricsSettings.resetForTest();
  });

  tearDown(DesktopLyricsSettings.resetForTest);

  test('桌面歌词样式设置可持久化', () async {
    await DesktopLyricsSettings.setEnabled(true);
    await DesktopLyricsSettings.setFontFamily('PingFang SC');
    await DesktopLyricsSettings.setFontSize(32);
    await DesktopLyricsSettings.setTextColor(0xFF112233);
    await DesktopLyricsSettings.setHighlightColor(0xFF44EECC);
    await DesktopLyricsSettings.setBackgroundOpacity(0);
    await DesktopLyricsSettings.setPosition('topCenter');

    DesktopLyricsSettings.resetForTest();
    await DesktopLyricsSettings.ensureLoaded();

    expect(DesktopLyricsSettings.enabled.value, isTrue);
    expect(DesktopLyricsSettings.fontFamily.value, 'PingFang SC');
    expect(DesktopLyricsSettings.fontSize.value, 32);
    expect(DesktopLyricsSettings.textColor.value, 0xFF112233);
    expect(DesktopLyricsSettings.highlightColor.value, 0xFF44EECC);
    expect(DesktopLyricsSettings.backgroundOpacity.value, 0);
    expect(DesktopLyricsSettings.position.value, 'topCenter');
  });

  test('字号和透明度会限制在安全范围内', () async {
    await DesktopLyricsSettings.setFontSize(100);
    await DesktopLyricsSettings.setBackgroundOpacity(-1);

    expect(DesktopLyricsSettings.fontSize.value, 48);
    expect(DesktopLyricsSettings.backgroundOpacity.value, 0);
  });
}
