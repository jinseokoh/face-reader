// lite body (0010 daily_faces 투영) — landmarks 없이 `lite: true` 면 파싱되고,
// 계측·인구통계·유형은 전문 body 와 같다. lite 가 아니면 좌표 없는 body 는 거부.
import 'dart:convert';
import 'dart:math';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_report.dart';

void main() {
  final full = fakeReport(Random(7), gender: Gender.male, age: AgeGroup.values[2]);
  final fullJson = jsonDecode(full.toJsonString()) as Map<String, dynamic>;

  Map<String, dynamic> liteOf(Map<String, dynamic> j) => {
        for (final e in j.entries)
          if (e.key != 'landmarks' && e.key != 'lateralLandmarks') e.key: e.value,
        'lite': true,
      };

  test('lite body 는 좌표 없이 파싱되고 유형·인구통계·계측이 전문과 같다', () {
    final lite = FaceReadingReport.fromJsonString(jsonEncode(liteOf(fullJson)));
    final again = FaceReadingReport.fromJsonString(jsonEncode(fullJson));
    expect(lite.landmarks, isEmpty);
    expect(lite.archetype.primary, again.archetype.primary);
    expect(lite.gender, again.gender);
    expect(lite.ageGroup, again.ageGroup);
    expect(lite.metrics.keys.toSet(), again.metrics.keys.toSet());
    for (final id in lite.metrics.keys) {
      expect(lite.metrics[id]!.zScore, closeTo(again.metrics[id]!.zScore, 1e-9));
    }
  });

  test('lite 표시 없이 좌표가 빠진 body 는 거부한다', () {
    final broken = liteOf(fullJson)..remove('lite');
    expect(() => FaceReadingReport.fromJsonString(jsonEncode(broken)), throwsFormatException);
  });
}
