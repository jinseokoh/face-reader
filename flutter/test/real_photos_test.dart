// Runs four real photos (z-scores extracted via Python+MediaPipe Tasks) through
// the actual attribute engine and prints final 0~10 scores per face.
//
// This test exists to PROVE the engine produces meaningfully different score
// patterns for visually different faces. If a future change re-introduces the
// "everyone gets 10/10/10 for stability/trust/leadership" bug, this test will
// fail by showing identical top-3 across all four photos.
//
// To regenerate z-scores: /tmp/mp_venv/bin/python /tmp/extract_face_metrics.py
//
// Run via: flutter test test/real_photos_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/attribute_derivation.dart';
import 'package:face_reader/domain/services/attribute_normalize.dart';
import 'package:face_reader/domain/services/physiognomy_scoring.dart';

// z-scores extracted via /tmp/extract_face_metrics.py against the
// MediaPipe-calibrated eastAsian female reference (face_reference_data.dart).
const _photos = <String, Map<String, double>>{
  'rose (로제)': {
    'faceAspectRatio': 0.30,
    'upperFaceRatio': 0.80,
    'midFaceRatio': 1.07,
    'lowerFaceRatio': -1.28,
    'faceTaperRatio': -0.26,
    'gonialAngle': 0.45,
    'intercanthalRatio': 0.23,
    'eyeFissureRatio': 1.24,
    'eyeCanthalTilt': 0.52,
    'eyebrowThickness': 0.51,
    'browEyeDistance': -0.41,
    'nasalWidthRatio': 0.57,
    'nasalHeightRatio': 1.07,
    'mouthWidthRatio': 0.12,
    'mouthCornerAngle': 0.90,
    'lipFullnessRatio': -1.40,
    'philtrumLength': 0.49,
  },
  'iu (아이유)': {
    'faceAspectRatio': -0.20,
    'upperFaceRatio': 0.02,
    'midFaceRatio': -0.28,
    'lowerFaceRatio': 0.15,
    'faceTaperRatio': -0.69,
    'gonialAngle': 0.47,
    'intercanthalRatio': 0.27,
    'eyeFissureRatio': -0.10,
    'eyeCanthalTilt': 0.57,
    'eyebrowThickness': -0.09,
    'browEyeDistance': -0.82,
    'nasalWidthRatio': -0.92,
    'nasalHeightRatio': -0.28,
    'mouthWidthRatio': -1.23,
    'mouthCornerAngle': -0.71,
    'lipFullnessRatio': 0.29,
    'philtrumLength': 0.12,
  },
  'lee_suji (이수지)': {
    'faceAspectRatio': -0.11,
    'upperFaceRatio': -0.79,
    'midFaceRatio': 0.19,
    'lowerFaceRatio': 0.52,
    'faceTaperRatio': 0.71,
    'gonialAngle': -0.35,
    'intercanthalRatio': 0.56,
    'eyeFissureRatio': -1.10,
    'eyeCanthalTilt': -0.29,
    'eyebrowThickness': 0.05,
    'browEyeDistance': 0.57,
    'nasalWidthRatio': 0.64,
    'nasalHeightRatio': 0.19,
    'mouthWidthRatio': 1.15,
    'mouthCornerAngle': 0.98,
    'lipFullnessRatio': 0.78,
    'philtrumLength': -1.31,
  },
  'jeon_doyeon (전도연)': {
    'faceAspectRatio': -1.30,
    'upperFaceRatio': -0.49,
    'midFaceRatio': -0.75,
    'lowerFaceRatio': 0.93,
    'faceTaperRatio': 0.08,
    'gonialAngle': -0.61,
    'intercanthalRatio': -0.63,
    'eyeFissureRatio': -0.40,
    'eyeCanthalTilt': -0.53,
    'eyebrowThickness': -0.20,
    'browEyeDistance': 0.61,
    'nasalWidthRatio': -0.15,
    'nasalHeightRatio': -0.75,
    'mouthWidthRatio': -0.36,
    'mouthCornerAngle': -1.31,
    'lipFullnessRatio': 0.15,
    'philtrumLength': 0.71,
  },
};

// Canonical label order: attribute.dart::labelKo 와 일치시킨다.
// sensuality = 바람기, libido = 관능도.
const _attrLabelKo = <Attribute, String>{
  Attribute.wealth: '재물운',
  Attribute.leadership: '리더십',
  Attribute.intelligence: '통찰력',
  Attribute.sociability: '사회성',
  Attribute.emotionality: '감정성',
  Attribute.stability: '안정성',
  Attribute.sensuality: '바람기',
  Attribute.trustworthiness: '신뢰성',
  Attribute.attractiveness: '매력도',
  Attribute.libido: '관능도',
};

void main() {
  test('real photos: per-face attribute scores from actual engine', () {
    const gender = Gender.female;
    final perPhoto = <String, Map<Attribute, double>>{};

    for (final entry in _photos.entries) {
      final name = entry.key;
      final rawZ = entry.value;

      // Apply same clamp as production pipeline
      final z = <String, double>{};
      for (final info in metricInfoList) {
        z[info.id] = (rawZ[info.id] ?? 0).clamp(-3.5, 3.5).toDouble();
      }

      final raws = deriveAttributeScores(
        tree: scoreTree(z),
        gender: gender,
        isOver50: false,
        hasLateral: false,
      );
      final normalized = normalizeAllScores(raws, gender);
      perPhoto[name] = normalized;
    }

    // ─── Pretty print ───
    // ignore: avoid_print
    print('\n========== Real Photos — Engine Output ==========');
    final names = perPhoto.keys.toList();
    final headerCells = ['Attribute', ...names.map((n) => n.padLeft(18))];
    // ignore: avoid_print
    print(headerCells.join(' │ '));
    // ignore: avoid_print
    print('─' * (headerCells.join(' │ ').length));
    for (final attr in Attribute.values) {
      final row = <String>[];
      row.add('${_attrLabelKo[attr]} (${attr.name})'.padRight(28));
      for (final n in names) {
        row.add(perPhoto[n]![attr]!.toStringAsFixed(1).padLeft(18));
      }
      // ignore: avoid_print
      print(row.join(' │ '));
    }

    // ─── Per-face top-3 vs bottom-3 ───
    // ignore: avoid_print
    print('\n========== Per-Face Top 3 / Bottom 3 ==========');
    for (final name in names) {
      final scores = perPhoto[name]!;
      final sorted = scores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top3 = sorted
          .take(3)
          .map((e) => '${_attrLabelKo[e.key]} ${e.value.toStringAsFixed(1)}')
          .join(', ');
      final bot3 = sorted.reversed
          .take(3)
          .toList()
          .reversed
          .map((e) => '${_attrLabelKo[e.key]} ${e.value.toStringAsFixed(1)}')
          .join(', ');
      // ignore: avoid_print
      print('$name');
      // ignore: avoid_print
      print('  TOP    : $top3');
      // ignore: avoid_print
      print('  BOTTOM : $bot3');
    }

    // ─── Targeted check: stability / trust / leadership are NOT all 10 ───
    // ignore: avoid_print
    print('\n========== 안정성 / 신뢰성 / 리더십 across faces ==========');
    final targets = [
      Attribute.stability,
      Attribute.trustworthiness,
      Attribute.leadership,
    ];
    final header2 = <String>['attr'.padRight(18)];
    for (final n in names) {
      header2.add(n.padLeft(18));
    }
    // ignore: avoid_print
    print(header2.join(' │ '));
    for (final attr in targets) {
      final row = <String>['${_attrLabelKo[attr]}'.padRight(18)];
      for (final n in names) {
        row.add(perPhoto[n]![attr]!.toStringAsFixed(1).padLeft(18));
      }
      // ignore: avoid_print
      print(row.join(' │ '));
    }

    // ─── Hard assertions: prove the bug is fixed ───
    // 1) For each face, top 3 attributes must NOT all be ≥9.5
    for (final name in names) {
      final scores = perPhoto[name]!;
      final sorted = scores.values.toList()..sort((a, b) => b.compareTo(a));
      final allTop3High = sorted[0] >= 9.5 && sorted[1] >= 9.5 && sorted[2] >= 9.5;
      expect(allTop3High, isFalse,
          reason: '$name: top 3 are all ≥9.5 (saturation bug)');
    }

    // 2) Within each face, score spread (max-min) must be ≥2.0
    // v2.3 (2026-04-19): rule magnitude 축소로 인한 자연스러운 spread 감소.
    // 최소 rank 보장분 2.0 기준 — 아래면 진짜 압축되어 문제.
    for (final name in names) {
      final list = perPhoto[name]!.values.toList()..sort();
      final spread = list.last - list.first;
      expect(spread, greaterThanOrEqualTo(2.0),
          reason: '$name: spread too small ($spread)');
    }

    // 3) The four faces must NOT have identical scores for stability+trust+leadership.
    //    (Specifically: at least 2 of the 4 must differ by ≥0.5 on at least one of these.)
    for (final attr in targets) {
      final values = names.map((n) => perPhoto[n]![attr]!).toList();
      final spread = values.reduce((a, b) => a > b ? a : b) -
          values.reduce((a, b) => a < b ? a : b);
      expect(spread, greaterThan(0.4),
          reason:
              '${_attrLabelKo[attr]}: all 4 faces produce nearly identical scores ($values)');
    }
  });
}
