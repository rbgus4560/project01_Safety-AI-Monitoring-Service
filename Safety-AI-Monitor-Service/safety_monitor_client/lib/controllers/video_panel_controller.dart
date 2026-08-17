// 화면에서 사용하는 데이터와 로딩 상태를 관리하는 controller 파일입니다.
// 상태 변경 후 notifyListeners로 연결된 UI 갱신을 요청합니다.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../services/video_service.dart';

// 영상 재생 패널의 상태를 한 곳에서 관리합니다.
// 파일 영상, 스트림, replay clip 재생을 모두 이 controller가 다룹니다.
class VideoPanelController extends ChangeNotifier {
  VideoPanelController({VideoService? service})
    : _service = service ?? VideoService() {
    _listenVideoState();
  }

  final VideoService _service;

  String videoPath = '';
  String liveSourcePath = '';
  String sourceType = '';
  String replayReturnPath = '';
  String replayReturnSourceType = '';
  String replaySourceKey = '';
  bool isPlaying = false;
  Duration currentPosition = Duration.zero;
  Duration totalDuration = Duration.zero;
  Duration replayReturnPosition = Duration.zero;
  double frameRate = 30.0;
  double replayReturnFrameRate = 30.0;
  double replayBaseSourceSeconds = 0.0;
  int videoWidth = 0;
  int videoHeight = 0;
  String errorText = '';
  bool isReplayMode = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<int?>? _videoWidthSub;
  StreamSubscription<int?>? _videoHeightSub;
  bool _isDisposed = false;

  VideoController get videoController => _service.videoController;

  bool get hasVideo => videoPath.isNotEmpty;
  bool get isStreamMode => sourceType == 'stream';
  bool get canReturnFromReplay => isReplayMode && replayReturnPath.isNotEmpty;
  String get replayReturnButtonText =>
      replayReturnSourceType == 'stream' ? '라이브 복귀' : '원래 영상 복귀';
  int get currentFrameValue =>
      ((currentPosition.inMilliseconds / 1000) * frameRate).round();
  double get currentOverlaySeconds => isReplayMode
      ? replayBaseSourceSeconds + (currentPosition.inMilliseconds / 1000)
      : (currentPosition.inMilliseconds / 1000);

  Future<void> openVideo(
    String path, {
    String nextSourceType = 'video',
    bool preserveReplayContext = false,
  }) async {
    // 로컬 파일과 서버 clip URL을 같은 메서드로 열 수 있게 합니다.
    errorText = '';

    if (!preserveReplayContext) {
      isReplayMode = false;
      replayBaseSourceSeconds = 0.0;
      replaySourceKey = '';
      replayReturnPath = '';
      replayReturnSourceType = '';
      replayReturnPosition = Duration.zero;
      replayReturnFrameRate = frameRate;
    }

    if (path.isEmpty) {
      _notifyIfActive();
      return;
    }

    if (nextSourceType == 'video' && !_isNetworkVideoPath(path)) {
      final file = File(path);
      if (!await file.exists()) {
        errorText = '영상 파일을 찾을 수 없습니다.';
        _notifyIfActive();
        return;
      }
    }

    videoPath = path;
    sourceType = nextSourceType;
    if (nextSourceType == 'stream') {
      liveSourcePath = path;
    }
    try {
      await _service.openVideo(path);
    } catch (error) {
      errorText = '영상 열기에 실패했습니다: $error';
      _notifyIfActive();
      return;
    }
    _notifyIfActive();
  }

  Future<void> openReplayClip(
    String path, {
    double replayStartSeconds = 0.0,
    String sourceKey = '',
    bool preserveReturnContext = true,
  }) async {
    // 이벤트 상세나 로그 클릭으로 클립 재생 모드로 전환할 때 사용합니다.
    if (preserveReturnContext && !isReplayMode && videoPath.isNotEmpty) {
      replayReturnPath = videoPath;
      replayReturnSourceType = sourceType;
      replayReturnPosition = currentPosition;
      replayReturnFrameRate = frameRate;
    } else if (!preserveReturnContext) {
      replayReturnPath = '';
      replayReturnSourceType = '';
      replayReturnPosition = Duration.zero;
      replayReturnFrameRate = frameRate;
    }

    await openVideo(path, nextSourceType: 'video', preserveReplayContext: true);
    if (_isDisposed) {
      return;
    }
    isReplayMode = true;
    replayBaseSourceSeconds = replayStartSeconds < 0 ? 0.0 : replayStartSeconds;
    replaySourceKey = sourceKey.trim();
    _notifyIfActive();
  }

  Future<void> returnToLive() async {
    if (!canReturnFromReplay) {
      return;
    }

    final returnPath = replayReturnPath;
    final returnSourceType = replayReturnSourceType;
    final returnPosition = replayReturnPosition;
    final returnFrameRate = replayReturnFrameRate;

    replayReturnPath = '';
    replayReturnSourceType = '';
    replayReturnPosition = Duration.zero;
    replayReturnFrameRate = frameRate;
    replayBaseSourceSeconds = 0.0;
    replaySourceKey = '';
    isReplayMode = false;

    await openVideo(returnPath, nextSourceType: returnSourceType);
    setFrameRate(returnFrameRate);
    if (returnSourceType != 'stream' && returnPosition > Duration.zero) {
      await _service.seek(returnPosition);
    }

    _notifyIfActive();
  }

  Future<void> closeReplay() async {
    if (!isReplayMode) {
      return;
    }
    if (canReturnFromReplay) {
      await returnToLive();
      return;
    }

    replayReturnPath = '';
    replayReturnSourceType = '';
    replayReturnPosition = Duration.zero;
    replayReturnFrameRate = frameRate;
    replayBaseSourceSeconds = 0.0;
    replaySourceKey = '';
    isReplayMode = false;
    clearCurrentSource();
    _notifyIfActive();
  }

  Future<void> togglePlay() async {
    if (!hasVideo) {
      return;
    }

    if (isPlaying) {
      await _service.pause();
    } else {
      await _service.play();
    }
  }

  Future<void> pausePlayback() async {
    if (!hasVideo || !isPlaying) {
      return;
    }
    await _service.pause();
  }

  Future<void> movePrevFrame() async {
    await _moveByFrame(-1);
  }

  Future<void> moveNextFrame() async {
    await _moveByFrame(1);
  }

  Future<void> moveToRatio(double ratio) async {
    if (totalDuration.inMilliseconds <= 0) {
      return;
    }

    final safeRatio = ratio.clamp(0.0, 1.0);
    final nextMs = (totalDuration.inMilliseconds * safeRatio).round();
    await _service.seek(Duration(milliseconds: nextMs));
  }

  Future<void> setMuted(bool muted) async {
    if (_isDisposed) {
      return;
    }
    await _service.setMuted(muted);
  }

  void clearCurrentSource() {
    videoPath = '';
    liveSourcePath = '';
    sourceType = '';
    replayReturnPath = '';
    replayReturnSourceType = '';
    replaySourceKey = '';
    currentPosition = Duration.zero;
    totalDuration = Duration.zero;
    replayReturnPosition = Duration.zero;
    replayBaseSourceSeconds = 0.0;
    errorText = '';
    isReplayMode = false;
    _notifyIfActive();
  }

  void setFrameRate(double value) {
    if (value <= 0) {
      return;
    }
    frameRate = value;
    _notifyIfActive();
  }

  void disposeController() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    unawaited(_positionSub?.cancel());
    unawaited(_durationSub?.cancel());
    unawaited(_playingSub?.cancel());
    unawaited(_videoWidthSub?.cancel());
    unawaited(_videoHeightSub?.cancel());
    unawaited(_service.dispose());
    dispose();
  }

  void _listenVideoState() {
    // media_kit의 재생 상태 변화를 UI용 필드로 반영합니다.
    _positionSub = _service.positionStream.listen((value) {
      if (_isDisposed) {
        return;
      }
      currentPosition = value;
      _notifyIfActive();
    });

    _durationSub = _service.durationStream.listen((value) {
      if (_isDisposed) {
        return;
      }
      totalDuration = value;
      _notifyIfActive();
    });

    _playingSub = _service.playingStream.listen((value) {
      if (_isDisposed) {
        return;
      }
      isPlaying = value;
      _notifyIfActive();
    });

    _videoWidthSub = _service.videoWidthStream.listen((value) {
      if (_isDisposed) {
        return;
      }
      final nextWidth = value ?? 0;
      if (videoWidth == nextWidth) {
        return;
      }
      videoWidth = nextWidth;
      _notifyIfActive();
    });

    _videoHeightSub = _service.videoHeightStream.listen((value) {
      if (_isDisposed) {
        return;
      }
      final nextHeight = value ?? 0;
      if (videoHeight == nextHeight) {
        return;
      }
      videoHeight = nextHeight;
      _notifyIfActive();
    });
  }

  Future<void> _moveByFrame(int frameStep) async {
    if (frameRate <= 0) {
      return;
    }

    final frameMs = (1000 / frameRate).round();
    final nextMs = currentPosition.inMilliseconds + (frameMs * frameStep);
    final safeMs = nextMs < 0 ? 0 : nextMs;
    await _service.seek(Duration(milliseconds: safeMs));
  }

  bool _isNetworkVideoPath(String path) {
    // clip_url처럼 HTTP 주소가 들어오면 로컬 파일 존재 검사를 건너뛰기 위해 사용합니다.
    final normalized = path.trim().toLowerCase();
    return normalized.startsWith('http://') ||
        normalized.startsWith('https://');
  }

  void _notifyIfActive() {
    if (_isDisposed) {
      return;
    }
    notifyListeners();
  }
}
