// attribute quantile 테이블을 **실측 얼굴 11,800장**으로 생성한다.
//
// 기존 `calibration_test.dart` 는 합성 분포를 썼다 — metric z 를 2-factor
// (bone·mid) 모델에서 2만 번 뽑아 파이프라인에 통과시키는 방식. 그 모델의
// 상관계수(_boneLoadings 등)와 얼굴형 분포는 **손으로 적은 값**이고, marginal 은
// 정확한 정규분포로 가정된다. 실제 얼굴은 그렇지 않다.
//
// 이 도구는 AAF 11,800장(정면 yaw<18°, male 5361 / female 6439)의 실측 metric 을
// 그대로 파이프라인에 통과시켜 attribute raw 분포를 만든다. 따라서 부위 간
// 상관·왜도·첨도·얼굴형 분포가 전부 데이터에서 나온다. 가정이 없다.
//
// 입력: tools/face_shape_ml/out/aaf_per_face_shaped.csv
//   생성 = extract_aaf.py (등방 좌표 재측정) → label_shapes.py (프로덕션
//   face_shape_ratios.tflite 로 얼굴형 라벨링).
//
// 실행:
//   flutter test test/calibration_empirical_test.dart --plain-name 'empirical'
// 출력 블록을 attribute_normalize.dart 에 붙여넣는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/attribute_derivation.dart';
import 'package:face_engine/domain/services/physiognomy_scoring.dart';

const _csv =
    '/Users/chuck/Code/face/tools/face_shape_ml/out/aaf_per_face_shaped.csv';

/// 합성 캘리브레이션과 같은 baseline 셀. 이번 변경에서 바꾸는 건 "합성 → 실측"
/// 하나뿐이므로 연령·인종은 건드리지 않는다.
const _ethnicity = Ethnicity.eastAsian;
const _ageGroup = AgeGroup.thirties;

/// (얼굴형 × 성별) 셀의 최소 표본. 21-point quantile 을 안정적으로 잡으려면
/// 수백 장은 있어야 한다. 미달 셀은 테이블에서 빼면 `_quantileFor` 가 성별
/// 전체 테이블로 자동 폴백한다.
const _minCellSamples = 400;

const _shapeByName = {
  'oval': FaceShape.oval,
  'oblong': FaceShape.oblong,
  'round': FaceShape.round,
  'square': FaceShape.square,
  'heart': FaceShape.heart,
};

class _Face {
  final Gender gender;
  final FaceShape shape;
  final Map<String, double> metrics;
  const _Face(this.gender, this.shape, this.metrics);
}

List<_Face> _load() {
  final lines = File(_csv).readAsLinesSync();
  final header = lines.first.split(',');
  final gi = header.indexOf('gender');
  final si = header.indexOf('shape');
  return [
    for (final line in lines.skip(1))
      if (line.trim().isNotEmpty)
        () {
          final cells = line.split(',');
          return _Face(
            cells[gi] == 'male' ? Gender.male : Gender.female,
            _shapeByName[cells[si]] ?? FaceShape.unknown,
            {
              for (var i = 0; i < header.length; i++)
                if (i != gi && i != si) header[i]: double.parse(cells[i]),
            },
          );
        }(),
  ];
}

/// 실측 metric → z → tree → attribute raw. 프로덕션과 같은 경로다.
Map<Attribute, double> _rawScores(_Face f) {
  final refs = referenceData[_ethnicity]![f.gender]!;
  final z = <String, double>{};
  for (final info in metricInfoList) {
    final ref = refs[info.id]!;
    z[info.id] = (f.metrics[info.id]! - ref.mean) / ref.sd;
  }
  return deriveAttributeScores(
    tree: scoreTree(z),
    gender: f.gender,
    ethnicity: _ethnicity,
    ageGroup: _ageGroup,
    hasLateral: false,
    faceShape: f.shape,
    shapeConfidence: f.shape == FaceShape.unknown ? 0.0 : 0.8,
  );
}

/// 정렬된 raw 리스트 → 21-point (p0, p5, …, p100). 합성 쪽 `_toQuantiles` 와
/// 동일한 인덱싱이라 두 테이블이 같은 의미를 갖는다.
List<double> _quantiles(List<double> raws) {
  raws.sort();
  return List<double>.generate(21, (i) {
    final idx = ((raws.length - 1) * (i / 20)).round();
    return raws[idx];
  });
}

String _fmt(List<double> q) =>
    '[${q.map((v) => v.toStringAsFixed(3)).join(', ')}]';

void main() {
  test('empirical attribute quantiles (AAF 11,800)', () {
    final faces = _load();
    expect(faces.length, greaterThan(10000));

    // 성별 전체 (shape-agnostic) — 실제 얼굴형 구성비가 그대로 반영된다.
    final byGender = <Gender, Map<Attribute, List<double>>>{
      for (final g in Gender.values)
        g: {for (final a in Attribute.values) a: <double>[]},
    };
    // (얼굴형 × 성별) 셀.
    final byShape = <FaceShape, Map<Gender, Map<Attribute, List<double>>>>{};

    for (final f in faces) {
      final scores = _rawScores(f);
      for (final a in Attribute.values) {
        final v = scores[a] ?? 0.0;
        byGender[f.gender]![a]!.add(v);
        if (f.shape != FaceShape.unknown) {
          byShape
              .putIfAbsent(f.shape, () => {})
              .putIfAbsent(f.gender,
                  () => {for (final x in Attribute.values) x: <double>[]})[a]!
              .add(v);
        }
      }
    }

    final buf = StringBuffer();
    buf.writeln('\n════════ 실측 quantile — AAF ${faces.length}장 ════════');

    for (final g in Gender.values) {
      final n = byGender[g]![Attribute.wealth]!.length;
      buf.writeln('\nconst _attrQuantiles${g == Gender.male ? 'Male' : 'Female'}'
          ' = <Attribute, List<double>>{  // n=$n');
      for (final a in Attribute.values) {
        buf.writeln(
            '  Attribute.${a.name}: ${_fmt(_quantiles(byGender[g]![a]!))},');
      }
      buf.writeln('};');
    }

    buf.writeln('\n──── per-shape (n < $_minCellSamples 셀은 제외 → 성별'
        ' 테이블로 폴백) ────');
    final dropped = <String>[];
    buf.writeln('const _attrQuantilesByShape = '
        '<FaceShape, Map<Gender, Map<Attribute, List<double>>>>{');
    for (final s in [
      FaceShape.oval,
      FaceShape.oblong,
      FaceShape.round,
      FaceShape.square,
      FaceShape.heart,
    ]) {
      final cells = byShape[s];
      if (cells == null) continue;
      final kept = <Gender>[];
      for (final g in Gender.values) {
        final n = cells[g]?[Attribute.wealth]?.length ?? 0;
        if (n >= _minCellSamples) {
          kept.add(g);
        } else if (n > 0) {
          dropped.add('${s.name}/${g.name} n=$n');
        }
      }
      if (kept.isEmpty) continue;
      buf.writeln('  FaceShape.${s.name}: {');
      for (final g in kept) {
        final n = cells[g]![Attribute.wealth]!.length;
        buf.writeln(
            '    Gender.${g.name}: {  // n=$n');
        for (final a in Attribute.values) {
          buf.writeln(
              '      Attribute.${a.name}: ${_fmt(_quantiles(cells[g]![a]!))},');
        }
        buf.writeln('    },');
      }
      buf.writeln('  },');
    }
    buf.writeln('};');
    buf.writeln('\n표본 부족으로 제외된 셀: '
        '${dropped.isEmpty ? '없음' : dropped.join(' · ')}');

    // ignore: avoid_print
    print(buf.toString());
  });
}
