import 'package:flutter/material.dart';
import '../../ui/portfolio_theme.dart';

class CameraAddResult {
  const CameraAddResult.camera({
    required this.cameraIndex,
    required this.displayName,
    required this.startImmediately,
  }) : videoFile = false;

  const CameraAddResult.video({
    required this.displayName,
    required this.startImmediately,
  })  : cameraIndex = -1,
        videoFile = true;

  final int cameraIndex;
  final bool videoFile;
  final String displayName;
  final bool startImmediately;
}

Future<CameraAddResult?> showCameraAddDialog(BuildContext context) {
  return showDialog<CameraAddResult>(
    context: context,
    builder: (context) => const _CameraAddDialog(),
  );
}

class _CameraAddDialog extends StatefulWidget {
  const _CameraAddDialog();
  @override
  State<_CameraAddDialog> createState() => _CameraAddDialogState();
}

class _CameraAddDialogState extends State<_CameraAddDialog> {
  String _type = 'USB Camera';
  final _name = TextEditingController(text: '생산라인 카메라');
  final _index = TextEditingController(text: '1');
  bool _startImmediately = true;

  @override
  void dispose() {
    _name.dispose();
    _index.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: PortfolioColors.panel,
      child: SizedBox(
        width: 780,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                const Text('카메라 추가', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ]),
              const Divider(),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  flex: 3,
                  child: Column(children: [
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: '카메라 이름', hintText: '예) 생산라인 - 2'),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      value: _type,
                      decoration: const InputDecoration(labelText: '카메라 유형'),
                      items: const [
                        DropdownMenuItem(value: 'USB Camera', child: Text('USB Camera')),
                        DropdownMenuItem(value: 'Video File', child: Text('Video File (테스트용)')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? 'USB Camera'),
                    ),
                    const SizedBox(height: 14),
                    if (_type == 'USB Camera')
                      TextField(
                        controller: _index,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '장치 인덱스',
                          hintText: '0, 1, 2 ...',
                          helperText: '학교에서 여러 USB 카메라를 연결할 때 장치별 인덱스를 선택합니다.',
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: PortfolioColors.panelAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: PortfolioColors.border),
                        ),
                        child: const Row(children: [
                          Icon(Icons.video_file_outlined),
                          SizedBox(width: 10),
                          Expanded(child: Text('추가를 누르면 영상 파일 선택 창이 열립니다.\nUSB 카메라가 없을 때 다중 카메라 테스트용으로 사용할 수 있습니다.')),
                        ]),
                      ),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _startImmediately,
                      onChanged: (v) => setState(() => _startImmediately = v ?? true),
                      title: const Text('추가 후 즉시 분석 시작'),
                      subtitle: const Text('실제 카메라가 없으면 연결 실패 상태로 표시될 수 있습니다.'),
                    ),
                  ]),
                ),
                const SizedBox(width: 18),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 250,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: PortfolioColors.border),
                    ),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(_type == 'USB Camera' ? Icons.videocam_outlined : Icons.movie_outlined, size: 68, color: PortfolioColors.textMuted),
                      const SizedBox(height: 12),
                      const Text('미리보기', style: TextStyle(color: PortfolioColors.textMuted)),
                      const SizedBox(height: 6),
                      const Text('추가 후 실제 영상이 표시됩니다.', style: TextStyle(fontSize: 11, color: PortfolioColors.textMuted)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    final name = _name.text.trim();
                    if (_type == 'Video File') {
                      Navigator.pop(
                        context,
                        CameraAddResult.video(displayName: name, startImmediately: _startImmediately),
                      );
                      return;
                    }
                    Navigator.pop(
                      context,
                      CameraAddResult.camera(
                        cameraIndex: int.tryParse(_index.text.trim()) ?? 0,
                        displayName: name,
                        startImmediately: _startImmediately,
                      ),
                    );
                  },
                  child: const Text('추가'),
                ),
              ]),
            ],
          ),
        ),
      ),
    );
  }
}
