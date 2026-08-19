// 궁합 unlock 다이얼로그의 회전 숫자 휠 — 창 두 칸이 계속 돌고,
// 릴이 창 밖으로 넘쳐 레이아웃 예외를 내지 않아야 한다.
//
// 실행: flutter test test/spinning_number_wheel_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facely/presentation/widgets/spinning_number_wheel.dart';

List<String> _digits(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((t) => t.data!)
    .toList(growable: false);

void main() {
  testWidgets('릴 두 개가 각각 숫자 4칸을 그린다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SpinningNumberWheel(size: 200))),
      ),
    );
    final digits = _digits(tester);
    expect(digits, hasLength(8)); // 창 2개 × 4칸
    expect(digits.every((d) => RegExp(r'^[0-9]$').hasMatch(d)), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('시간이 지나면 숫자가 계속 바뀐다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: SpinningNumberWheel(size: 200))),
      ),
    );
    final before = _digits(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(_digits(tester), isNot(equals(before)));
    // 한 주기(8초)를 넘겨도 멈추거나 예외를 내지 않는다.
    await tester.pump(const Duration(seconds: 8));
    expect(_digits(tester), hasLength(8));
    expect(tester.takeException(), isNull);
  });
}
