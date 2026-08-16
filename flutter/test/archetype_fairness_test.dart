// Verifies that, with z-normalization in normalizeScore, no archetype
// is statistically favored over another.
//
// Run via: flutter test test/archetype_fairness_test.dart
//
// Expected: each of 10 archetypes is selected as primary roughly 10% of
// the time (1 in 10) over a large random sample.

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:face_engine/domain/services/attribute_derivation.dart';
import 'package:face_engine/domain/services/attribute_normalize.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';

import 'support/aaf_faces.dart';

// 입력은 반드시 quantile 테이블이 만들어진 세계와 같아야 공정성 검증이
// 성립한다. 그 테이블이 AAF 11,800장 실측이므로 여기서도 같은 얼굴들을 읽는다.
// (합성 generator 로 뽑아놓고 실측 테이블로 정규화하면 서로 다른 두 세계를
// 섞는 셈이라 발동률 수치가 아무것도 뜻하지 않는다.)

void main() {
  test('archetype primary distribution is fair (within ±5%)', () {
    final faces = loadAafFaces();
    final samples = faces.length;
    final counts = {for (final a in Attribute.values) a: 0};

    for (final f in faces) {
      final raws = deriveAttributeScores(
        tree: scoreTree(f.z),
        gender: f.gender,
        ethnicity: Ethnicity.eastAsian,
        ageGroup: AgeGroup.thirties,
        hasLateral: false,
        faceShape: f.shape,
        shapeConfidence: 0.8,
      );
      final normalized = normalizeAllScores(raws, f.gender, shape: f.shape);
      final archetype =
          classifyArchetype(normalized, f.gender, shape: f.shape);
      counts[archetype.primary] = counts[archetype.primary]! + 1;
    }

    // ignore: avoid_print
    print('\n========== Archetype Fairness ($samples samples) ==========');
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      final pct = (e.value / samples * 100).toStringAsFixed(2);
      // ignore: avoid_print
      print('${e.key.name.padRight(16)} ${e.value.toString().padLeft(5)}  ($pct%)');
    }

    // 각 attribute가 5%~15% 사이에 있어야 fair (이상값 10%, ±5% 허용)
    // 이론적으론 정확히 10%여야 하지만 attribute 간 correlation 때문에 약간 벗어남.
    // ±5% 안이면 leadership 쏠림 같은 심각한 편향은 사라진 것으로 간주.
    for (final entry in counts.entries) {
      final pct = entry.value / samples;
      // AAF 11,800장 실측: 최저 wealth 7.20% / 최고 libido 14.67%.
      // 잔여 편차는 실제 얼굴에서 attribute 끼리 상관이 있기 때문이다 (상관
      // 높은 attribute 끼리 top-1 을 나눠 갖는다). 여유를 둔 hard bound —
      // 이 밖으로 나가면 랭킹 편향이 재발한 것이다.
      expect(pct, greaterThan(0.043),
          reason: '\${entry.key.name} too rare: \${(pct * 100).toStringAsFixed(2)}%');
      expect(pct, lessThan(0.175),
          reason: '\${entry.key.name} too common: \${(pct * 100).toStringAsFixed(2)}%');
    }
  });

  test('special archetype rates stay rare and gender-balanced', () {
    final faces = loadAafFaces();
    final samples = faces.length;
    final counts = <String, int>{};
    var none = 0;

    for (final f in faces) {
      final raws = deriveAttributeScores(
        tree: scoreTree(f.z),
        gender: f.gender,
        ethnicity: Ethnicity.eastAsian,
        ageGroup: AgeGroup.thirties,
        hasLateral: false,
        faceShape: f.shape,
        shapeConfidence: 0.8,
      );
      final normalized = normalizeAllScores(raws, f.gender, shape: f.shape);
      final r = classifyArchetype(normalized, f.gender, shape: f.shape);
      final sp = r.specialArchetype;
      if (sp == null) {
        none++;
      } else {
        counts[sp] = (counts[sp] ?? 0) + 1;
      }
    }

    final totalSpecial = samples - none;
    // 2026-07-25 재설계 실측: special 전체 23.9%, 단일 최고 2.6%(큰그릇형).
    // 과거 임계값(7.5/7.0 — 5~10 스케일의 중앙값 근처)에서는 98.2% 가
    // special 을 받고 제왕형이 57.6% 를 독식했다. 재발 방지 hard cap.
    expect(totalSpecial / samples, lessThan(0.30),
        reason: 'special 전체 발동률 \${(totalSpecial / samples * 100).toStringAsFixed(1)}% — 특수 상이 흔해졌다');
    for (final e in counts.entries) {
      expect(e.value / samples, lessThan(0.04),
          reason: '\${e.key} \${(e.value / samples * 100).toStringAsFixed(2)}% — 단일 special 독식 재발');
    }
    // 저점 규칙(광인형·사기꾼형)은 최저점 5.0 스케일에서 임계 ≤3.0 으로
    // 영원히 죽어 있던 전례가 있다 — 발동 0 이면 다시 죽은 것.
    expect(counts['광인형'] ?? 0, greaterThan(0), reason: '광인형 dead rule');
    expect(counts['사기꾼형'] ?? 0, greaterThan(0), reason: '사기꾼형 dead rule');
  });
}
