/// 얼굴 기하학 프로필 (APPLE.md §7·§8) — 영역별 상위 지표 0~100.
///
/// 원시 계측 대신 "그 영역이 기준 집단(AAF 동아시아 11,800장) 평균에 얼마나
/// 가까운가" 를 백분위로 보여준다. 영역 = 닮은 정도와 같은 `geometryRegions`
/// (윤곽·눈·눈썹·코·입·턱선), 원점수 = 그 영역 계측 |z| 의 평균. 점수 = 100 −
/// (원점수의 성별 백분위) → 100 에 가까울수록 평균에 가깝다. `symmetry` 는
/// 전체 비대칭도의 같은 식 → 높을수록 대칭.
///
/// 가치 판단이 아니다 — 평균에서 먼 것이 나쁜 것이 아니라 "드문 형태" 다.
/// 임의 점수를 만들지 않는다: 분위표는 전부 실측(§8).
library;

import 'package:face_engine/data/constants/geometry_profile_quantiles.dart';
import 'package:face_engine/data/constants/symmetry_reference.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/services/first_impression.dart';

/// 화면 순서. `symmetry` 다음 `geometryRegions` 순.
const List<String> geometryProfileIds = [
  'symmetry',
  'outline',
  'eyes',
  'brows',
  'nose',
  'mouth',
  'jaw',
];

const Map<String, String> geometryProfileNameKo = {
  'symmetry': '얼굴 대칭',
  'outline': '얼굴 윤곽',
  'eyes': '눈 영역',
  'brows': '눈썹 영역',
  'nose': '코 영역',
  'mouth': '입 영역',
  'jaw': '턱선',
};

/// 영역 원점수 — 있는 계측 |z| 의 평균. 하나도 없으면 null.
double? regionMeanAbsZ(Map<String, double> z, Iterable<String> ids) {
  var sum = 0.0;
  var n = 0;
  for (final id in ids) {
    final v = z[id];
    if (v == null) continue;
    sum += v.abs();
    n++;
  }
  return n == 0 ? null : sum / n;
}

/// id → 0~100. 계산 불가한 영역(계측·대칭 없음)은 빠진다.
Map<String, double> computeGeometryProfile({
  required Map<String, double> zByMetric,
  required Gender gender,
  Map<String, double>? symmetry,
}) {
  final out = <String, double>{};
  final sym = symmetry?['symOverall'];
  if (sym != null) {
    out['symmetry'] = 100 -
        percentileFromQuantiles(
            sym, symmetryReference[gender]!['symOverall']!.quantiles);
  }
  final table = geometryProfileQuantiles[gender]!;
  for (final e in geometryRegions.entries) {
    final raw = regionMeanAbsZ(zByMetric, e.value);
    if (raw == null) continue;
    out[e.key] = 100 - percentileFromQuantiles(raw, table[e.key]!);
  }
  return out;
}
