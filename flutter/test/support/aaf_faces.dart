// AAF 11,800장 실측 얼굴 로더 — 분포 검증 테스트 공용.
//
// quantile 테이블(`attribute_normalize.dart`)이 이 얼굴들로 만들어졌으므로,
// 공정성·포화도 같은 분포 검증도 **같은 얼굴들**을 써야 한다. 합성 generator 로
// 샘플링해 놓고 실측 테이블로 정규화하면 서로 다른 두 세계를 섞는 것이라
// 측정값이 의미를 잃는다.
//
// 원본 CSV 생성:
//   tools/face_shape_ml/extract_aaf.py      (등방 좌표 실측)
//   scratchpad/label_shapes.py              (프로덕션 tflite 로 얼굴형 라벨)

import 'dart:io';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';

const aafCsvPath =
    '/Users/chuck/Code/face/tools/face_shape_ml/out/aaf_per_face_shaped.csv';

/// 실측 얼굴 한 장 — 프로덕션과 동일하게 z-score 까지 환산된 상태.
class AafFace {
  final Gender gender;
  final FaceShape shape;
  final Map<String, double> z;
  const AafFace(this.gender, this.shape, this.z);
}

const _shapeByName = {
  'oval': FaceShape.oval,
  'oblong': FaceShape.oblong,
  'round': FaceShape.round,
  'square': FaceShape.square,
  'heart': FaceShape.heart,
};

List<AafFace>? _cache;

/// CSV 를 읽어 metric → z 환산까지 마친 얼굴 목록. 첫 호출에서만 파싱한다.
List<AafFace> loadAafFaces() {
  final cached = _cache;
  if (cached != null) return cached;

  final lines = File(aafCsvPath).readAsLinesSync();
  final header = lines.first.split(',');
  final gi = header.indexOf('gender');
  final si = header.indexOf('shape');

  final faces = <AafFace>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final cells = line.split(',');
    final gender = cells[gi] == 'male' ? Gender.male : Gender.female;
    final refs = referenceData[Ethnicity.eastAsian]![gender]!;

    final z = <String, double>{};
    for (final info in metricInfoList) {
      final col = header.indexOf(info.id);
      final ref = refs[info.id]!;
      z[info.id] = (double.parse(cells[col]) - ref.mean) / ref.sd;
    }
    faces.add(
        AafFace(gender, _shapeByName[cells[si]] ?? FaceShape.unknown, z));
  }

  _cache = faces;
  return faces;
}
