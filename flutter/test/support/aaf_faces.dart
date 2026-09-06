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
//   tools/face_shape_ml/extract_aaf_symmetry.py → aaf_per_face_sym.csv 의
//   대칭 6 컬럼을 28 계측 tuple 로 join (2026-09-06, symEyes…symOverall).

import 'dart:io';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/symmetry_reference.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:facely/domain/services/face_metrics.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'aaf_landmarks.dart';

const aafCsvPath =
    '/Users/chuck/Code/face/tools/face_shape_ml/out/aaf_per_face_shaped.csv';

/// 실측 얼굴 한 장 — 프로덕션과 동일하게 z-score 까지 환산된 상태.
class AafFace {
  final Gender gender;
  final FaceShape shape;
  final Map<String, double> z;

  /// 얼굴 전체 비대칭도 symOverall 의 z (symmetryReference 기준).
  final double symZ;
  const AafFace(this.gender, this.shape, this.z, this.symZ);
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
  final symi = header.indexOf('symOverall');

  final faces = <AafFace>[];
  for (final line in lines.skip(1)) {
    if (line.trim().isEmpty) continue;
    final cells = line.split(',');
    final gender = cells[gi] == 'male' ? Gender.male : Gender.female;
    final refs = referenceData[Ethnicity.eastAsian]![gender]!;

    final z = <String, double>{};
    Map<String, double>? computed;
    for (final info in metricInfoList) {
      final col = header.indexOf(info.id);
      final ref = refs[info.id]!;
      final double raw;
      if (col >= 0) {
        raw = double.parse(cells[col]);
      } else {
        // CSV 에 없는 계측(§6 추가분)은 같은 얼굴의 저장 좌표에서 계산한다.
        computed ??= _findComputed([
          for (final id in _keyIds) double.parse(cells[header.indexOf(id)]),
        ]);
        if (computed == null) {
          _unmatched++;
          break;
        }
        raw = computed[info.id]!;
      }
      z[info.id] = (double.parse((raw).toString()) - ref.mean) / ref.sd;
    }
    if (z.length != metricInfoList.length) continue;
    final sref = symmetryReference[gender]!['symOverall']!;
    final symZ = (double.parse(cells[symi]) - sref.mean) / sref.sd;
    faces.add(AafFace(
        gender, _shapeByName[cells[si]] ?? FaceShape.unknown, z, symZ));
  }

  _cache = faces;
  return faces;
}

/// CSV 행 ↔ 좌표(f32) 행 대응. 두 파일의 행 순서가 달라서(얼굴형 라벨 단계에서
/// 섞임) 계측값으로 잇는다. 저장 좌표는 소수 4자리라 계측이 1e-4 수준으로
/// 흔들리므로 정확 키가 아니라 상대 오차 1e-3 안의 후보를 찾는다.
/// 후보 검색은 (얼굴 비율, 입 폭) 을 0.05 칸으로 묶은 버킷과 그 이웃.
const List<String> _keyIds = [
  'faceAspectRatio', 'mouthWidthRatio', 'gonialAngle',
  'nasalWidthRatio', 'eyeAspect', 'intercanthalRatio',
];

int _unmatched = 0;

/// 좌표에서 못 이은 CSV 행 수 — 0 이어야 한다 (aaf_faces_join_test).
int get aafUnmatchedRows => _unmatched;

Map<String, List<Map<String, double>>>? _bucketCache;

String _bucket(double a, double b) =>
    '${(a / 0.05).floor()}|${(b / 0.05).floor()}';

Map<String, List<Map<String, double>>> _buckets() {
  final cached = _bucketCache;
  if (cached != null) return cached;
  final out = <String, List<Map<String, double>>>{};
  for (final f in loadAafLandmarks()) {
    final m = FaceMetrics(
      [for (final p in f.points) FaceMeshLandmark(x: p[0], y: p[1], z: 0)],
    ).computeAll();
    out.putIfAbsent(_bucket(m['faceAspectRatio']!, m['mouthWidthRatio']!), () => [])
        .add(m);
  }
  _bucketCache = out;
  return out;
}

Map<String, double>? _findComputed(List<double> target) {
  final buckets = _buckets();
  final ia = (target[0] / 0.05).floor();
  final ib = (target[1] / 0.05).floor();
  Map<String, double>? best;
  var bestDist = double.infinity;
  for (var da = -1; da <= 1; da++) {
    for (var db = -1; db <= 1; db++) {
      for (final m in buckets['${ia + da}|${ib + db}'] ?? const []) {
        // 계측마다 상대 오차 — 작은 거리의 비율(눈 세로비 등)은 좌표 반올림에
        // 더 흔들리므로 1% 까지 허용하고, 그 안에서 가장 가까운 후보를 고른다.
        var dist = 0.0;
        var ok = true;
        for (var i = 0; i < _keyIds.length; i++) {
          final rel = (m[_keyIds[i]]! - target[i]).abs() /
              (target[i].abs() + 1e-3);
          if (rel > 1e-2) {
            ok = false;
            break;
          }
          dist += rel;
        }
        if (ok && dist < bestDist) {
          bestDist = dist;
          best = m;
        }
      }
    }
  }
  return best;
}
