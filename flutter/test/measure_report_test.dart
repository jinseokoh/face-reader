// measure 에디션 리포트 본문 — 서술 없이 렌더되고 핵심 섹션이 있다.
// 위젯 자체는 에디션과 무관하게 존재하므로 두 에디션에서 같은 결과.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:facely/presentation/screens/chemistry/report_measure_sections.dart';

import 'support/fake_report.dart';

void main() {
  testWidgets('첫인상 4축·특이점·계측 26·얼굴형·참고 자료가 렌더된다', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    final report = fakeReport(Random(3), gender: Gender.female, age: AgeGroup.values[1]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MeasureReportBody(report: report)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('첫인상'), findsOneWidget);
    expect(find.text('신뢰감 있는 인상'), findsOneWidget);
    expect(find.text('매력적인 인상'), findsOneWidget);
    expect(find.text('얼굴 기하학 프로필'), findsOneWidget);
    expect(find.text('턱선'), findsOneWidget);
    expect(find.textContaining('이(가)'), findsWidgets); // §13 특징 문장
    expect(find.text('내 얼굴의 특이점'), findsOneWidget);
    expect(find.text('정면 계측 26'), findsOneWidget);
    expect(find.text('좌우 대칭'), findsOneWidget);
    expect(find.text('얼굴 대칭'), findsNWidgets(2)); // 프로필 행 + 대칭 섹션 행
    expect(find.text('얼굴형'), findsOneWidget);
    expect(find.text('참고 자료'), findsOneWidget);
    expect(find.text(MeasureReportBody.disclaimer), findsOneWidget);
    // 서술 섹션은 없다.
    expect(find.text('관상 해석'), findsNothing);
    expect(find.text('관상 10대 속성'), findsNothing);
  });
}
