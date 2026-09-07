// 관상/첫인상 모드 스위치 (Android, 2026-09-07) — 앱바 제목 "관상 | 첫인상".
// 컴파일 플래그로 고정된 빌드(--dart-define)나 iOS 에서는 스위치가 없다.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facely/core/edition.dart';
import 'package:facely/core/edition_copy.dart';
import 'package:facely/presentation/providers/edition_provider.dart';
import 'package:facely/presentation/widgets/edition_switch_title.dart';

void main() {
  testWidgets('스위치 — 흐린 쪽을 누르면 확인 뒤 모드가 바뀐다', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(appBar: PreferredSize(
            preferredSize: Size.fromHeight(56),
            child: SafeArea(child: Center(child: EditionSwitchTitle())),
          )),
        ),
      ),
    );
    if (!kEditionSwitchable) {
      expect(find.text(EditionCopy.faceTitle), findsOneWidget);
      return;
    }
    final before = container.read(editionModeProvider);
    expect(find.text('관상'), findsOneWidget);
    expect(find.text('첫인상'), findsOneWidget);

    await tester.tap(find.text(before ? '관상' : '첫인상'));
    await tester.pumpAndSettle();
    expect(find.text('전환'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(container.read(editionModeProvider), before);

    await tester.tap(find.text(before ? '관상' : '첫인상'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('전환'));
    await tester.pumpAndSettle();
    expect(container.read(editionModeProvider), !before);
    expect(kMeasureEdition, !before);
    // 되돌린다 — 다른 테스트가 같은 프로세스 전역을 본다.
    await container.read(editionModeProvider.notifier).switchTo(measure: before);
    expect(kMeasureEdition, before);
  });
}
