// AAF 11,800장 실측 랜드마크 로더 — Procrustes 보정·닮은 정도 분포 테스트 공용.
//
// 원본: tools/face_shape_ml/extract_aaf_landmarks.py →
//   out/aaf_landmarks.f32 (float32 N×936, [x0,y0,x1,y1,…] 등방 좌표 소수 4자리)
//   out/aaf_landmarks_meta.csv (stem,gender,age — 행 순서 동일)
// 앱 저장 형식(리포트 `landmarks`)과 같다.

import 'dart:io';

import 'package:face_engine/data/enums/gender.dart';

const aafLandmarksPath =
    '/Users/chuck/Code/face/tools/face_shape_ml/out/aaf_landmarks.f32';
const aafLandmarksMetaPath =
    '/Users/chuck/Code/face/tools/face_shape_ml/out/aaf_landmarks_meta.csv';

class AafLandmarks {
  final Gender gender;
  final int age;
  final List<List<double>> points;
  const AafLandmarks(this.gender, this.age, this.points);
}

List<AafLandmarks>? _cache;

List<AafLandmarks> loadAafLandmarks() {
  final cached = _cache;
  if (cached != null) return cached;
  final bytes = File(aafLandmarksPath).readAsBytesSync();
  final f = bytes.buffer.asFloat32List(bytes.offsetInBytes, bytes.length ~/ 4);
  final meta = File(aafLandmarksMetaPath).readAsLinesSync().skip(1).toList();
  assert(f.length == meta.length * 936, 'f32/meta 행 수 불일치');
  final out = <AafLandmarks>[];
  for (var r = 0; r < meta.length; r++) {
    final c = meta[r].split(',');
    final base = r * 936;
    out.add(AafLandmarks(
      c[1] == 'male' ? Gender.male : Gender.female,
      int.parse(c[2]),
      [for (var i = 0; i < 468; i++) [f[base + 2 * i], f[base + 2 * i + 1]]],
    ));
  }
  _cache = out;
  return out;
}
