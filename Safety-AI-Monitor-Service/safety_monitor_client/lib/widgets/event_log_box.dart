// 여러 화면에서 재사용하는 Flutter 위젯 파일입니다.
// 부모 화면에서 받은 값과 콜백을 바탕으로 UI를 구성합니다.

import 'package:flutter/material.dart';

import '../controllers/event_feed_source.dart';
import '../models/event_log_item.dart';

// 이벤트 목록 패널입니다.
// 파일 로그 모드와 API 모드 모두 EventFeedSource만 맞으면 같은 UI를 재사용합니다.
class EventLogBox extends StatelessWidget {
  const EventLogBox({
    super.key,
    required this.eventFeed,
    required this.onTapItem,
    this.baseUrl = '',
  });

  final EventFeedSource eventFeed;
  final void Function(EventLogItem item) onTapItem;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
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
                Text('총 ${eventFeed.logItems.length}건'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: eventFeed.logItems.isEmpty
                ? const Center(child: Text('표시할 로그가 없습니다.'))
                : ListView.separated(
                    itemCount: eventFeed.logItems.length,
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = eventFeed.logItems[index];
                      return _LogTile(
                        item: item,
                        isSelected: eventFeed.selectedKeys.contains(
                          item.selectionKey,
                        ),
                        onTap: () => onTapItem(item),
                      );
                    },
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
    required this.isSelected,
    required this.onTap,
  });

  final EventLogItem item;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      selected: isSelected,
      onTap: onTap,
      // type / level / 메시지를 간단히 보여 주고, 클릭 시 상세 이동이나 클립 재생으로 이어집니다.
      title: Text('${item.typeText} / ${item.levelText}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.messageText),
          const SizedBox(height: 4),
          Text(
            'time=${item.timeText} person=${item.personIdText} duration=${item.durationText}',
          ),
          Text('start=${item.startText} end=${item.endText}'),
          if (item.hasClip) Text('clip=${item.clipPathText}'),
        ],
      ),
    );
  }
}

