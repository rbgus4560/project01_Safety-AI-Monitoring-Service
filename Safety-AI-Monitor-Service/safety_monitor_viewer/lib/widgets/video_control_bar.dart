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
              SizedBox(width: compact ? 6 : 8),
              Expanded(
                child: Text(
                  '${_formatTime(controller.currentPosition)} / '
                  '${_formatTime(controller.totalDuration)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (compact
                              ? Theme.of(context).textTheme.bodySmall
                              : Theme.of(context).textTheme.bodyMedium)
                          ?.copyWith(fontSize: compact ? 11 : 13),
                ),
              ),
              SizedBox(
                width: compact ? 58 : 72,
                child: TextFormField(
                  initialValue: controller.frameRate.toStringAsFixed(1),
                  style:
                      (compact
                              ? Theme.of(context).textTheme.bodySmall
                              : Theme.of(context).textTheme.bodyMedium)
                          ?.copyWith(fontSize: compact ? 11 : 13),
                  decoration: InputDecoration(
                    labelText: 'FPS',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: compact ? 6 : 8,
                      vertical: compact ? 4 : 5,
                    ),
                    border: const OutlineInputBorder(),
                  ),
                  onFieldSubmitted: (value) {
                    final nextValue = double.tryParse(value);
                    if (nextValue != null) {
                      controller.setFrameRate(nextValue);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(Duration value) {
    final hours = value.inHours;
    final minutes = value.inMinutes.remainder(60);
    final seconds = value.inSeconds.remainder(60);
    final milliseconds = value.inMilliseconds.remainder(1000);

    if (hours > 0) {
      return '$hours:${_two(minutes)}:${_two(seconds)}.${_three(milliseconds)}';
    }

    return '${_two(minutes)}:${_two(seconds)}.${_three(milliseconds)}';
  }

  String _two(int value) => value.toString().padLeft(2, '0');
  String _three(int value) => value.toString().padLeft(3, '0');
}
