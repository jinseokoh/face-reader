import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 회귀 방지: 다이얼로그 TextField 컨트롤러는 닫힘 애니메이션이 끝난 뒤에만
/// 해제돼야 한다. 컨트롤러를 State 에 묶고 dispose 에서 해제하면, 다이얼로그를
/// 저장으로 닫는 동안(페이드 아웃) "used after disposed" 가 나면 안 된다.
///
/// 위젯 구조는 team_room_screen.dart 의 _TextInputDialog 와 동일.
class _TextInputDialog extends StatefulWidget {
  final String title;
  final int maxLength;
  const _TextInputDialog({
    required this.title,
    required this.maxLength,
  });
  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  late final TextEditingController _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: widget.maxLength,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('저장'),
        ),
      ],
    );
  }
}

void main() {
  testWidgets('dialog controller survives close animation', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await showDialog<String>(
                    context: context,
                    builder: (_) => const _TextInputDialog(
                      title: '이름 붙이기',
                      maxLength: 10,
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '성주');
    await tester.tap(find.text('저장'));
    // pump 한 프레임씩 — 닫힘 애니메이션 진행 중 프레임에서 크래시 없어야 함.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(result, '성주');
    expect(tester.takeException(), isNull);
  });
}
