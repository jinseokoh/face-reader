// §54 1~3단계 — 문구가 순서대로 바뀌고 마지막에서 멈춘다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facely/presentation/widgets/analysis_stage_overlay.dart';

void main() {
  testWidgets('단계 문구 순서', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnalysisStageOverlay()));
    expect(find.text(kMeasureAnalysisStages[0]), findsOneWidget);
    expect(find.text('1 / 3'), findsOneWidget);
    await tester.pump(kAnalysisStageStep);
    expect(find.text(kMeasureAnalysisStages[1]), findsOneWidget);
    await tester.pump(kAnalysisStageStep);
    expect(find.text(kMeasureAnalysisStages[2]), findsOneWidget);
    await tester.pump(kAnalysisStageStep * 3);
    expect(find.text(kMeasureAnalysisStages[2]), findsOneWidget);
    expect(find.text('3 / 3'), findsOneWidget);
  });
}
