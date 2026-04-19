// Real-user empirical recalibration harness.
//
// 14 명의 eastAsian female 30s 실사용자 metric z-score 를 읽고:
//   1) metric 별 empirical mean/std 계산 → 보정 제안
//   2) 현 엔진으로 14 명의 archetype 분포 생성 → 편향 진단
//
// Reference fix 공식:  new_ref_mean = old_ref_mean + old_ref_std * z_mean
//                     new_ref_std  = old_ref_std * z_std
// 새 reference 아래에선 empirical z' 가 N(0, 1) 이 된다.
//
// Run: flutter test test/real_users_recalibration_test.dart --reporter expanded

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/face_shape.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

// 원본 fixture 는 old broken reference 로 계산된 z-score. 4 개 critical metric
// reference 가 수정됐으므로 raw 로 환원 후 현재 reference 로 재-z 해야 정확.
const _oldRef = <String, ({double mean, double sd})>{
  'eyebrowCurvature': (mean: 0.003, sd: 0.004),
  'chinAngle': (mean: 145.0, sd: 10.0),
  'upperVsLowerLipRatio': (mean: 0.90, sd: 0.15),
  'eyebrowTiltDirection': (mean: 0.008, sd: 0.008),
  'faceAspectRatio': (mean: 1.35, sd: 0.07),
  'midFaceRatio': (mean: 0.30, sd: 0.03),
  'browEyeDistance': (mean: 0.150, sd: 0.020),
  'foreheadWidth': (mean: 0.86, sd: 0.04),
  'cheekboneWidth': (mean: 0.90, sd: 0.04),
  'eyeAspect': (mean: 0.35, sd: 0.06),
  'eyeFissureRatio': (mean: 0.20, sd: 0.025),
  'lowerFaceRatio': (mean: 0.39, sd: 0.05),
  'faceTaperRatio': (mean: 0.79, sd: 0.05),
  'lowerFaceFullness': (mean: 0.50, sd: 0.05),
  'gonialAngle': (mean: 141.0, sd: 6.0),
  'eyebrowThickness': (mean: 0.034, sd: 0.005),
  'nasalWidthRatio': (mean: 0.89, sd: 0.10),
  'nasalHeightRatio': (mean: 0.30, sd: 0.03),
  'mouthWidthRatio': (mean: 0.39, sd: 0.05),
  'mouthCornerAngle': (mean: 3.0, sd: 5.0),
  'philtrumLength': (mean: 0.090, sd: 0.020),
};

Map<String, double> _rebase(Map<String, double> oldZ) {
  final out = Map<String, double>.from(oldZ);
  for (final m in _oldRef.keys) {
    if (!out.containsKey(m)) continue;
    final oldR = _oldRef[m]!;
    final raw = oldR.mean + oldZ[m]! * oldR.sd;
    final newR = referenceData[Ethnicity.eastAsian]![Gender.female]![m]!;
    out[m] = (raw - newR.mean) / newR.sd;
  }
  return out;
}

void main() {
  late List<Map<String, dynamic>> fixtures;

  setUpAll(() {
    final file = File('test/fixtures/real_users_14.json');
    fixtures = (jsonDecode(file.readAsStringSync()) as List)
        .cast<Map<String, dynamic>>();
  });

  test('empirical z distribution vs reference calibration', () {
    final byMetric = <String, List<double>>{};
    for (final f in fixtures) {
      final rawZ = (f['z'] as Map)
          .cast<String, num>()
          .map((k, v) => MapEntry(k, v.toDouble()));
      final z = _rebase(rawZ); // 현재 reference 기준 empirical z
      for (final entry in z.entries) {
        byMetric.putIfAbsent(entry.key, () => []).add(entry.value);
      }
    }

    final rows = <(String, double, double, double, double)>[];
    for (final m in byMetric.keys) {
      final list = byMetric[m]!;
      final mean = list.reduce((a, b) => a + b) / list.length;
      final variance =
          list.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) /
              list.length;
      final std = sqrt(variance);
      final ref = referenceData[Ethnicity.eastAsian]![Gender.female]![m]!;
      final newMean = ref.mean + ref.sd * mean;
      final newStd = ref.sd * (std > 0.1 ? std : 1.0);
      rows.add((m, mean, std, newMean, newStd));
    }
    rows.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));

    // ignore: avoid_print
    print('\n========== Empirical z distribution (14 real users) ==========');
    // ignore: avoid_print
    print('metric                      z_mean   z_std    old_ref(μ/σ)         proposed_ref(μ/σ)');
    // ignore: avoid_print
    print('-' * 95);
    for (final r in rows) {
      final name = r.$1.padRight(28);
      final m = r.$2.toStringAsFixed(2).padLeft(6);
      final s = r.$3.toStringAsFixed(2).padLeft(6);
      final ref = referenceData[Ethnicity.eastAsian]![Gender.female]![r.$1]!;
      final oldR = '${ref.mean.toStringAsFixed(3)} / ${ref.sd.toStringAsFixed(3)}'
          .padRight(20);
      final newR =
          '${r.$4.toStringAsFixed(3)} / ${r.$5.toStringAsFixed(3)}';
      // ignore: avoid_print
      print('$name$m  $s   $oldR $newR');
    }
  });

  test('archetype distribution across 14 real users (current engine)', () {
    final counts = <Attribute, int>{for (final a in Attribute.values) a: 0};
    final primaries = <String>[];
    for (final f in fixtures) {
      final rawZ = (f['z'] as Map)
          .cast<String, num>()
          .map((k, v) => MapEntry(k, v.toDouble()));
      final z = _rebase(rawZ);
      final shape = FaceShape.values.firstWhere(
        (s) => s.name == f['faceShape'],
        orElse: () => FaceShape.unknown,
      );
      final tree = scoreTree(z);
      final raws = deriveAttributeScores(
        tree: tree,
        gender: Gender.female,
        isOver50: false,
        hasLateral: false,
        faceShape: shape,
        shapeConfidence: shape == FaceShape.unknown ? 0.0 : 0.7,
      );
      final normalized = normalizeAllScores(raws, Gender.female);
      final top = normalized.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      counts[top] = counts[top]! + 1;

      final arc = classifyArchetype(normalized, shape: shape);
      primaries.add('${f['id']}: ${arc.primary.name} + ${arc.secondary.name}');
    }

    // ignore: avoid_print
    print('\n========== 14 real users archetype distribution ==========');
    for (final entry in counts.entries..toList()) {
      if (entry.value == 0) continue;
      // ignore: avoid_print
      print('  ${entry.key.name.padRight(18)} ${entry.value}/14');
    }
    // ignore: avoid_print
    print('\n--- per-face primary+secondary ---');
    for (final p in primaries) {
      // ignore: avoid_print
      print('  $p');
    }

    final max = counts.values.reduce((a, b) => a > b ? a : b);
    final ratio = max / 14;
    // ignore: avoid_print
    print('\nmax concentration: $max/14 = ${(ratio * 100).toStringAsFixed(1)}%');
  });
}
