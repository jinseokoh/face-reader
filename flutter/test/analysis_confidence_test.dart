// 분석 확신도(§14) — 사진 상태 기반 3단. 실제 AAF 정면 얼굴은 높음, 돌리거나
// 작아지면 내려간다.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/analysis_confidence.dart';
import 'package:face_engine/domain/services/symmetry_metrics.dart';
import 'package:facely/presentation/screens/chemistry/report_measure_sections.dart';

import 'support/demo_landmarks.dart';

void main() {
  final face = demoLandmarks(Gender.male);

  test('AAF 정면 얼굴 — 높음', () {
    expect(landmarkYaw(face).abs(), lessThan(kConfidenceYawHigh));
    expect(faceWidthFraction(face), greaterThan(kConfidenceWidthHigh));
    expect(
      analysisConfidence(
          landmarks: face, gender: Gender.male, symmetry: computeSymmetry(face)),
      AnalysisConfidence.high,
    );
  });

  test('작게 찍힌 얼굴 — 보통', () {
    final small = [for (final p in face) [0.4 + p[0] * 0.3, p[1] * 0.3]];
    expect(faceWidthFraction(small), lessThan(kConfidenceWidthHigh));
    expect(analysisConfidence(landmarks: small, gender: Gender.male),
        AnalysisConfidence.medium);
  });

  test('옆으로 돌린 얼굴 — 낮음', () {
    // 코끝을 오른쪽 가장자리 쪽으로 당겨 yaw 를 키운다.
    final turned = [for (final p in face) [p[0], p[1]]];
    turned[1] = [face[234][0] + (face[454][0] - face[234][0]) * 0.05, face[1][1]];
    expect(landmarkYaw(turned).abs(), greaterThan(kConfidenceYawMedium));
    expect(analysisConfidence(landmarks: turned, gender: Gender.male),
        AnalysisConfidence.low);
  });

  test('5칸 — 백분위 20% 단위, 1~5', () {
    expect(segmentLevel(0), 1);
    expect(segmentLevel(20), 1);
    expect(segmentLevel(20.1), 2);
    expect(segmentLevel(81), 5);
    expect(segmentLevel(100), 5);
  });
}
