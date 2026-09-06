// 두 리포트 → 첫인상 쌍 분석 — 대칭·항등·범위. measure 비교 화면의 계산 소스.

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/data/constants/procrustes_reference.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:facely/domain/services/pair_score.dart';
import 'package:facely/presentation/screens/compatibility/pair_measure_sections.dart';

import 'support/fake_report.dart';

void main() {
  final a = fakeReport(Random(1), gender: Gender.male, age: AgeGroup.values[1]);
  final b = fakeReport(Random(2), gender: Gender.female, age: AgeGroup.values[2]);

  test('대칭 — (a,b) 와 (b,a) 의 네 지표와 케미 합이 같다', () {
    final ab = analyzePairReports(a, b);
    final ba = analyzePairReports(b, a);
    expect(ab.similarity.overall, closeTo(ba.similarity.overall, 1e-9));
    expect(ab.impressionSimilarity, closeTo(ba.impressionSimilarity, 1e-9));
    expect(ab.harmony, closeTo(ba.harmony, 1e-9));
    expect(ab.complementarity, closeTo(ba.complementarity, 1e-9));
    expect(ab.chemistry, closeTo(ba.chemistry, 1e-9));
  });

  test('항등 — 같은 리포트는 닮음 100, 보완 0, 케미 = 조화도 + 100', () {
    final aa = analyzePairReports(a, a);
    expect(aa.similarity.overall, closeTo(100, 1e-9));
    expect(aa.complementarity, closeTo(0, 1e-9));
    expect(aa.chemistry, closeTo(aa.harmony + 100, 1e-9));
  });

  test('계측 차이 순위 — 가장 닮은 3개와 가장 다른 3개는 겹치지 않는다', () {
    final near = rankMetricsByDifference(a, b, mostSimilar: true).take(3).toSet();
    final far = rankMetricsByDifference(a, b, mostSimilar: false).take(3).toSet();
    expect(near.intersection(far), isEmpty);
  });

  testWidgets('MeasurePairBody 가 렌더되고 핵심 섹션이 있다', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: MeasurePairBody(my: a, album: b)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('케미 점수의 세 성분'), findsOneWidget);
    expect(find.text('영역별 닮은 정도'), findsOneWidget);
    expect(find.text('두 얼굴 겹쳐 보기'), findsOneWidget);
    expect(find.text('같이 튀는 곳과 반대로 튀는 곳'), findsOneWidget);
    expect(find.text('대칭과 얼굴형'), findsOneWidget);
    expect(find.text('조화도에서 각 인상을 채우는 쪽'), findsOneWidget);
    expect(find.textContaining('무작위로 만난 두 사람과 비교하면'), findsOneWidget);
    // §25 — 영역 6개 전부 닮은/다른 부분 중 한쪽에 문구와 함께 나온다.
    final phrases = [
      for (final b in SimilarityBand.values) find.text(b.labelKo).evaluate().length,
    ];
    expect(phrases.fold<int>(0, (a, b) => a + b), 6);
    expect(find.text('두 사람의 첫인상'), findsOneWidget);
    expect(find.text('가설 지표'), findsOneWidget);
    expect(find.text(MeasurePairBody.disclaimer), findsOneWidget);
    expect(find.textContaining('천생연분'), findsNothing);
  });

  test('무작위 쌍 백분위 — 중앙값 50, 같은 얼굴은 100 근처', () {
    expect(pairSimilarityPercentile(50), closeTo(50, 1));
    expect(pairSimilarityPercentile(100), 100);
    expect(chemistryPercentile(kChemistryQuantiles[10]), closeTo(50, 1));
    expect(chemistryPercentile(0), 0);
  });

  test('같이/반대로 튀는 곳 — 서로 겹치지 않고 |z| ≥ 1 만', () {
    final same = sharedDeviations(a, b, sameDirection: true);
    final opp = sharedDeviations(a, b, sameDirection: false);
    expect(same.toSet().intersection(opp.toSet()), isEmpty);
    final zA = zMapOf(a), zB = zMapOf(b);
    for (final id in [...same, ...opp]) {
      expect(zA[id]!.abs(), greaterThanOrEqualTo(1));
      expect(zB[id]!.abs(), greaterThanOrEqualTo(1));
    }
    for (final id in same) {
      expect(zA[id]! > 0, zB[id]! > 0);
    }
  });
}
