// 방 생성 시트 ② 방 제목 — 기타(자유 입력) 포커스로 키보드가 올라온 상황에서
// 시트 내부가 overflow 하지 않아야 한다.
//
// 실행: flutter test test/battle_create_overflow_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/screens/team/battle_create_page.dart';

/// Hive·AuthService 를 건드리는 실제 build() 를 빈 목록으로 대체.
class _FakeHistory extends HistoryNotifier {
  @override
  List<FaceReadingReport> build() => const [];
}

void main() {
  testWidgets('기타 자유 입력 + 키보드 inset — overflow 없음', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400); // 360x800 logical
    tester.view.devicePixelRatio = 3.0;
    // 실기기 safe area — 노치(59)·제스처 바(34) logical.
    tester.view.padding = const FakeViewPadding(top: 177, bottom: 102);
    // iOS 텍스트 크기 확대 사용자 (접근성 설정 1단계).
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    addTearDown(tester.view.reset);
    await _openCustomTitleWithKeyboard(tester, keyboardPhysical: 1140);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면(SE급)에서도 overflow 없음', (tester) async {
    tester.view.physicalSize = const Size(750, 1334); // 375x667 logical
    tester.view.devicePixelRatio = 2.0;
    tester.view.padding = const FakeViewPadding(top: 40); // status bar 20
    tester.platformDispatcher.textScaleFactorTestValue = 1.2;
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    addTearDown(tester.view.reset);
    await _openCustomTitleWithKeyboard(tester, keyboardPhysical: 672); // kb 336
    expect(tester.takeException(), isNull);
  });
}

/// 시트 열기 → ① 전체 케미 → ② 기타 선택 → 키보드 등장까지 공통 시퀀스.
Future<void> _openCustomTitleWithKeyboard(
  WidgetTester tester, {
  required double keyboardPhysical,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [historyProvider.overrideWith(_FakeHistory.new)],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showBattleCreatePage(ctx),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();

  // ① 방 유형 → 다음.
  await tester.tap(find.text('전체 케미 배틀방'));
  await tester.pump();
  await tester.tap(find.text('다음'));
  await tester.pumpAndSettle();

  // ② 기타 카테고리 → 자유 입력 필드 (chip 가로 스크롤 밖 — 먼저 노출).
  await tester.ensureVisible(find.text('기타'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('기타'));
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsOneWidget);

  // 키보드 등장 (물리 px).
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardPhysical);
  await tester.showKeyboard(find.byType(TextField));
  await tester.pumpAndSettle();
}
