// 사진별 첫인상 비교(§56) — 카드 2장 이상 고르면 4축 + 대칭 표가 나온다.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:facely/presentation/screens/compatibility/photo_compare_screen.dart';

import 'support/fake_report.dart';

void main() {
  testWidgets('두 장을 고르면 사진 A·B 열과 축 4개 + 얼굴 대칭 행이 나온다',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 3000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final a = fakeReport(Random(1), gender: Gender.female, age: AgeGroup.values[1])
      ..alias = '첫째';
    final b = fakeReport(Random(2), gender: Gender.female, age: AgeGroup.values[1])
      ..alias = '둘째';
    await tester.pumpWidget(MaterialApp(home: PhotoCompareBody(reports: [a, b])));
    await tester.pumpAndSettle();
    expect(find.text('사진 A'), findsNothing);

    await tester.tap(find.text('첫째'));
    await tester.pump();
    expect(find.text('사진 A'), findsOneWidget);
    expect(find.text('신뢰감 있는 인상'), findsNothing); // 1장으론 표 없음

    await tester.tap(find.text('둘째'));
    await tester.pump();
    expect(find.text('사진 A'), findsNWidgets(2)); // 목록 표시 + 표 헤더
    expect(find.text('사진 B'), findsNWidgets(2));
    expect(find.text('신뢰감 있는 인상'), findsOneWidget);
    expect(find.text('얼굴 대칭'), findsOneWidget);
    expect(find.textContaining('상위 '), findsNWidgets(10)); // 5행 × 2열
    expect(tester.takeException(), isNull);

    // 다시 누르면 해제.
    await tester.tap(find.text('첫째'));
    await tester.pump();
    expect(find.text('사진 B'), findsNothing);
  });
}
