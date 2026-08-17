// 여러 화면에서 재사용하는 Flutter 위젯 파일입니다.
// 부모 화면에서 받은 값과 콜백을 바탕으로 UI를 구성합니다.

import 'package:flutter/material.dart';

import '../controllers/video_panel_controller.dart';

// 재생, 프레임 이동, 탐색 슬라이더를 묶은 하단 제어 바입니다.
class VideoControlBar extends StatelessWidget {
  const VideoControlBar({
    super.key,
    required this.controller,
    this.compact = false,
  });

  final VideoPanelController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 현재 시간을 비율로 바꿔 Slider와 연결합니다.
    final totalMs = controller.totalDuration.inMilliseconds;
    final currentMs = controller.currentPosition.inMilliseconds;
    final sliderValue = totalMs <= 0 ? 0.0 : currentMs / totalMs;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 4 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: compact ? 2 : 3,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: compact ? 7 : 8,
              ),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: sliderValue.clamp(0.0, 1.0),
              onChanged: controller.hasVideo
                  ? (value) => controller.moveToRatio(value)
                  : null,
            ),
          ),
          SizedBox(height: compact ? 0 : 2),
          Row(
            children: [
              IconButton(
                onPressed: controller.hasVideo
                    ? controller.movePrevFrame
                    : null,
                tooltip: '이전 프레임',
                iconSize: compact ? 16 : 18,
                padding: EdgeInsets.all(compact ? 2 : 3),
                constraints: BoxConstraints.tightFor(
                  width: compact ? 24 : 28,
                  height: compact ? 24 : 28,
                ),
                icon: const Icon(Icons.skip_previous),
              ),
              IconButton(
                onPressed: controller.hasVideo ? controller.togglePlay : null,
                tooltip: '재생 또는 일시정지',
                iconSize: compact ? 16 : 18,
                padding: EdgeInsets.all(compact ? 2 : 3),
                constraints: BoxConstraints.tightFor(
                  width: compact ? 24 : 28,
                  height: compact ? 24 : 28,
                ),
                icon: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
              ),
              IconButton(
                onPressed: controller.hasVideo
                    ? controller.moveNextFrame
                    : null,
                tooltip: '다음 프레임',
                iconSize: compact ? 16 : 18,
                padding: EdgeInsets.all(compact ? 2 : 3),
                constraints: BoxConstraints.tightFor(
                  width: compact ? 24 : 28,
                  height: compact ? 24 : 28,
                ),
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
