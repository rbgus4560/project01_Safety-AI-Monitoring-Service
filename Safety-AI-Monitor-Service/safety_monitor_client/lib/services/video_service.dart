// Flutter 쪽에서 서버 API나 로컬 프로세스 같은 외부 기능을 호출하는 파일입니다.
// HTTP 주소 생성, 요청 전송, 응답 JSON 변환 흐름이 포함되어 있습니다.

import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

class VideoService {
  VideoService() : player = Player() {
    videoController = VideoController(player);
  }

  final Player player;
  late final VideoController videoController;
  bool _isDisposed = false;

  Stream<Duration> get positionStream => player.stream.position;
  Stream<Duration> get durationStream => player.stream.duration;
  Stream<bool> get playingStream => player.stream.playing;
  Stream<int?> get videoWidthStream => player.stream.width;
  Stream<int?> get videoHeightStream => player.stream.height;

  Future<void> openVideo(String source) async {
    // 로컬 파일이나 RTSP/HTTP 주소를 연다
    await player.open(Media(source));
  }

  Future<void> play() async {
    await player.play();
  }

  Future<void> pause() async {
    await player.pause();
  }

  Future<void> seek(Duration position) async {
    await player.seek(position);
  }

  Future<void> setMuted(bool muted) async {
    try {
      await player.setVolume(muted ? 0 : 100);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    try {
      await player.pause();
    } catch (_) {}
    try {
      await player.dispose();
    } catch (_) {}
  }
}
