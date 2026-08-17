// 여러 화면에서 재사용하는 Flutter 위젯 파일입니다.
// 부모 화면에서 받은 값과 콜백을 바탕으로 UI를 구성합니다.

import 'package:flutter/material.dart';

class FileBar extends StatelessWidget {
  const FileBar({
    super.key,
    required this.videoPath,
    required this.sourceType,
    required this.sourceHint,
    required this.sourceCount,
    required this.activeSourceLabel,
    required this.hasSelectedSource,
    required this.canReturnFromReplay,
    required this.isReadOnly,
    required this.streamTextController,
    required this.cameraTextController,
    required this.onPickVideo,
    required this.onClearSelectedSource,
    required this.onOpenStream,
    required this.onOpenCamera,
    required this.onReturnLive,
  });

  final String videoPath;
  final String sourceType;
  final String sourceHint;
  final int sourceCount;
  final String activeSourceLabel;
  final bool hasSelectedSource;
  final bool canReturnFromReplay;
  final bool isReadOnly;
  final TextEditingController streamTextController;
  final TextEditingController cameraTextController;
  final VoidCallback? onPickVideo;
  final VoidCallback onClearSelectedSource;
  final VoidCallback? onOpenStream;
  final VoidCallback? onOpenCamera;
  final VoidCallback onReturnLive;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PathCard(
          title: sourceType == 'stream' ? 'Current Stream URL' : 'Video Source',
          value: videoPath.isEmpty ? 'No source selected' : videoPath,
          buttonText: isReadOnly ? 'Read Only' : 'Add Video',
          helperText: sourceHint,
          sourceCount: sourceCount,
          activeSourceLabel: activeSourceLabel,
          onPressed: onPickVideo,
          hasSelectedSource: hasSelectedSource,
          onClearSelectedSource: onClearSelectedSource,
          canReturnFromReplay: canReturnFromReplay,
          onReturnLive: onReturnLive,
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF171A20),
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: streamTextController,
                  enabled: !isReadOnly,
                  decoration: const InputDecoration(
                    labelText: 'CCTV / RTSP / HTTP URL',
                    hintText: 'rtsp://127.0.0.1:8554/live',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: onOpenStream,
                child: Text(isReadOnly ? 'Read Only' : 'Add Stream'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF171A20),
            border: Border.all(color: Colors.white12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: cameraTextController,
                  enabled: !isReadOnly,
                  decoration: const InputDecoration(
                    labelText: 'Local Camera Index',
                    hintText: '0',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: onOpenCamera,
                child: Text(isReadOnly ? 'Read Only' : 'Add Camera'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.title,
    required this.value,
    required this.buttonText,
    required this.helperText,
    required this.sourceCount,
    required this.activeSourceLabel,
    required this.onPressed,
    required this.hasSelectedSource,
    required this.onClearSelectedSource,
    required this.canReturnFromReplay,
    required this.onReturnLive,
  });

  final String title;
  final String value;
  final String buttonText;
  final String helperText;
  final int sourceCount;
  final String activeSourceLabel;
  final VoidCallback? onPressed;
  final bool hasSelectedSource;
  final VoidCallback onClearSelectedSource;
  final bool canReturnFromReplay;
  final VoidCallback onReturnLive;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(value, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Text(
            helperText,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            sourceCount <= 0
                ? 'No registered sources yet.'
                : 'Registered sources: $sourceCount / Active panel: $activeSourceLabel',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white60),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: onPressed, child: Text(buttonText)),
              if (hasSelectedSource) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: onClearSelectedSource,
                  child: const Text('Clear Selection'),
                ),
              ],
              if (canReturnFromReplay) ...[
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: onReturnLive,
                  child: const Text('Close Clip'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
