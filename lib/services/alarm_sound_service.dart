import 'package:audioplayers/audioplayers.dart';

/// 무음/진동 모드에서도 알람음이 들리도록 오디오 스트림을 강제 지정하는 서비스.
///
/// - Android: 알람(STREAM_ALARM) 스트림으로 재생 → 벨소리 무음 설정과 무관하게 재생됨
/// - iOS: AVAudioSessionCategory.playback → 무음 스위치(측면 스위치)가 켜져 있어도 재생됨
///
/// 주의: 이 방식은 "무음 모드"를 우회해 소리를 들려주는 표준적인 방법이며
/// (알람앱들이 쓰는 방식과 동일), 단말의 알람 볼륨 자체가 0으로 설정된 경우까지
/// 강제로 소리를 낼 수는 없습니다.
class AlarmSoundService {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;

  bool get isPlaying => _isPlaying;

  Future<void> _applyAudioContext() async {
    final context = AudioContext(
      android: AudioContextAndroid(
        isSpeakerphoneOn: true,
        stayAwake: true,
        contentType: AndroidContentType.sonification,
        usageType: AndroidUsageType.alarm,
        audioFocus: AndroidAudioFocus.gainTransient,
      ),
      iOS: AudioContextIOS(
        category: AVAudioSessionCategory.playback,
        options: {
          AVAudioSessionOptions.duckOthers,
          AVAudioSessionOptions.mixWithOthers,
        },
      ),
    );
    await _player.setAudioContext(context);
  }

  /// 알람음을 반복 재생 시작 (assets/sounds/alarm_chime.wav)
  Future<void> playLoop() async {
    await _applyAudioContext();
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1.0);
    await _player.play(AssetSource('sounds/alarm_chime.wav'));
    _isPlaying = true;
  }

  Future<void> stop() async {
    if (_isPlaying) {
      await _player.stop();
      _isPlaying = false;
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}
