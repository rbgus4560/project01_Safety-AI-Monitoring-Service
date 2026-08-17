// 여러 화면에서 재사용하는 Flutter 위젯 파일입니다.
// 부모 화면에서 받은 값과 콜백을 바탕으로 UI를 구성합니다.

import 'package:flutter/material.dart';

import '../controllers/event_feed_source.dart';
import '../models/event_log_item.dart';

// 이벤트 목록 패널입니다.
// 파일 로그 모드와 API 모드 모두 EventFeedSource만 맞으면 같은 UI를 재사용합니다.
class EventLogBox extends StatefulWidget {
  const EventLogBox({
    super.key,
    required this.eventFeed,
    required this.baseUrl,
    required this.onTapItem,
    this.sourceLabelResolver,
  });

  final EventFeedSource eventFeed;
  final String baseUrl;
  final void Function(EventLogItem item) onTapItem;
  final String Function(String sourceKey)? sourceLabelResolver;

  @override
  State<EventLogBox> createState() => _EventLogBoxState();
}

class _EventLogBoxState extends State<EventLogBox> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.eventFeed.logItems;
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF171A20),
        border: Border.all(color: Colors.white12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Text('이벤트 로그', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text('총 ${items.length}건'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: items.isEmpty
                ? const Center(child: Text('표시할 로그가 없습니다.'))
                : Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _scrollController,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _LogTile(
                          item: item,
                          baseUrl: widget.baseUrl,
                          isSelected: widget.eventFeed.selectedKeys.contains(
                            item.selectionKey,
                          ),
                          onTap: () => widget.onTapItem(item),
                          sourceLabelResolver: widget.sourceLabelResolver,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogTile extends StatelessWidget {
  const _LogTile({
    required this.item,
    required this.baseUrl,
    required this.isSelected,
    required this.onTap,
    this.sourceLabelResolver,
  });

  final EventLogItem item;
  final String baseUrl;
  final bool isSelected;
  final VoidCallback onTap;
  final String Function(String sourceKey)? sourceLabelResolver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnailUrl = _resolveThumbnailUrl(item.thumbnailUrlText);
    return Material(
      color: isSelected
          ? theme.colorScheme.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EventThumbnail(url: thumbnailUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _ruleLabel(item),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    _MetaLine(
                      icon: Icons.schedule,
                      text: '발생시간 ${_compactTime(item.timeText)}',
                    ),
                    const SizedBox(height: 3),
                    _MetaLine(
                      icon: Icons.computer,
                      text: '클라이언트 ${_clientLabel(item.sourceKeyText)}',
                    ),
                    const SizedBox(height: 3),
                    _MetaLine(
                      icon: Icons.policy_outlined,
                      text: '탐지 룰 ${_ruleLabel(item)}',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveThumbnailUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return '';
    }
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('http://') || lower.startsWith('https://')) {
      return trimmed;
    }
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (trimmed.startsWith('/')) {
      return '$normalizedBase$trimmed';
    }
    return '$normalizedBase/$trimmed';
  }

  String _compactTime(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || trimmed == '-') {
      return '-';
    }
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null) {
      return trimmed;
    }
    return '${parsed.hour.toString().padLeft(2, '0')}:'
        '${parsed.minute.toString().padLeft(2, '0')}:'
        '${parsed.second.toString().padLeft(2, '0')}';
  }

  String _clientLabel(String sourceKey) {
    final resolved = sourceLabelResolver?.call(sourceKey).trim() ?? '';
    if (resolved.isNotEmpty) {
      return resolved;
    }
    final match = RegExp(r'owner=([^|]+)').firstMatch(sourceKey);
    final owner = match?.group(1)?.trim() ?? '';
    if (owner.isEmpty) {
      return '-';
    }
    return owner.replaceFirst(RegExp(r'^client_'), '');
  }

  String _ruleLabel(EventLogItem item) {
    final type = item.typeText.trim();
    final level = item.levelText.trim();
    if (type.isEmpty || type == '-') {
      return level.isEmpty || level == '-' ? '-' : level;
    }
    if (level.isEmpty || level == '-') {
      return type;
    }
    return '$type / $level';
  }
}

class _EventThumbnail extends StatelessWidget {
  const _EventThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 96,
        height: 64,
        color: Colors.black26,
        child: url.isEmpty
            ? const _ThumbnailPlaceholder()
            : Image.network(
                url,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (context, error, stackTrace) {
                  return const _ThumbnailPlaceholder();
                },
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) {
                    return child;
                  }
                  return const _ThumbnailPlaceholder(isLoading: true);
                },
              ),
      ),
    );
  }
}

class _ThumbnailPlaceholder extends StatelessWidget {
  const _ThumbnailPlaceholder({this.isLoading = false});

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        isLoading ? Icons.image_search : Icons.image_not_supported_outlined,
        color: Colors.white38,
        size: 22,
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.white54),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
