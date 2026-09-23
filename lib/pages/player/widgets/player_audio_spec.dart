import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/services/player_service.dart';
import '../../../app/state/song_state.dart';
import '../../../app/utils/song_audio_spec.dart';

class PlayerAudioSpec extends StatelessWidget {
  final ValueListenable<SongEntity?> songListenable;
  final ValueListenable<String?>? playbackCodecListenable;

  const PlayerAudioSpec({
    super.key,
    required this.songListenable,
    this.playbackCodecListenable,
  });

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final codecListenable = playbackCodecListenable ??
        PlayerService.instance.playbackTranscodeCodec;
    return AnimatedBuilder(
      animation: Listenable.merge([songListenable, codecListenable]),
      builder: (context, _) {
        final text = formatPlayerAudioSpec(
          songListenable.value,
          playbackCodec: codecListenable.value,
        );
        if (text.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Tooltip(
            message: '实际播放音频信息',
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: color),
              semanticsLabel: '音频信息：${text.replaceAll('\n', '，')}',
            ),
          ),
        );
      },
    );
  }
}
