/// 十二宮 state computer — raw z + node + age → `Map<Palace, PalaceState>`.
///
/// 입력은 capture 단 raw evidence:
///  - `zMap`: 17 frontal zAdjusted + 8 lateral z (id → double)
///  - `nodeZ`: 14 node ownMeanZ (nodeId → double)
///  - `ageGroup`: age-gated flag (눈꼬리 잔주름은 30+ 에서만 유효) 판정용
///  - `lateralFlags`: aquilineNose 등 (FaceReadingReport 가 이미 산출)
///
/// 출력된 state 는 palace_pair_matcher 의 입력.
library;

import 'package:face_reader/data/enums/age_group.dart';

import 'palace.dart';

/// 궁별 관여 metric/node id. zMean 과 absZMax 계산 대상.
/// `node:` 접두는 nodeZ 조회, 접두 없으면 zMap 조회.
const Map<Palace, List<String>> _palaceSignals = {
  // 命宮 — 미간: glabella 노드 중심.
  Palace.life: ['node:glabella', 'intercanthalRatio'],
  // 財帛宮 — 코 전체.
  Palace.wealth: [
    'node:nose',
    'nasalWidthRatio',
    'nasalHeightRatio',
  ],
  // 兄弟宮 — 눈썹.
  Palace.sibling: ['node:eyebrow', 'eyebrowThickness', 'browEyeDistance'],
  // 田宅宮 — 눈과 눈썹 사이·상안검.
  Palace.property: ['browEyeDistance', 'eyeFissureRatio'],
  // 男女宮 — 누당·눈 아래 와잠. eye node + canthal tilt.
  Palace.children: [
    'node:eye',
    'eyeFissureRatio',
    'eyeCanthalTilt',
  ],
  // 奴僕宮 — 턱 양옆. chin node.
  Palace.slave: [
    'node:chin',
    'lowerFaceRatio',
    'lowerFaceFullness',
  ],
  // 妻妾宮 — 눈꼬리 옆. eyeCanthalTilt·browEyeDistance(외각).
  Palace.spouse: ['eyeCanthalTilt', 'browEyeDistance'],
  // 疾厄宮 — 콧대 뿌리(산근). lateral nasofrontalAngle + intercanthalRatio.
  Palace.illness: ['nasofrontalAngle', 'dorsalConvexity', 'intercanthalRatio'],
  // 遷移宮 — 이마 옆 끝. forehead node + faceAspectRatio.
  Palace.migration: ['node:forehead', 'faceAspectRatio'],
  // 官祿宮 — 이마 중앙.
  Palace.career: ['node:forehead', 'upperFaceRatio', 'foreheadWidth'],
  // 福德宮 — 이마 위 좌우.
  Palace.fortune: ['node:glabella', 'upperFaceRatio', 'browEyeDistance'],
  // 父母宮 — 이마 위 좌우.
  Palace.parents: ['upperFaceRatio', 'foreheadWidth'],
};

/// level 경계. |zMean| ≥ 0.2 → strong/weak, 그 외 balanced.
/// 다중 metric 평균은 std ≈ 0.85/√n 로 좁다. 0.2 면 palace 당 strong ~55%,
/// weak ~35% 까지 fire — pair-matcher subScore spread 확보 + faceTemplates
/// 양성 bias 로 인한 strong 쏠림을 weak 쪽 fire 율 올려 상쇄.
const double _levelThreshold = 0.2;

/// 궁 별 metric 부호 보정 — "palace strong = 吉상" 이 일관되도록 특정
/// metric 의 z 를 뒤집는다. 예: `nasofrontalAngle` z 가 높으면 코-이마
/// 전이가 평탄 = 산근 낮음 = 몸 컨디션 weak 이므로 부호를 뒤집어 평균에 더한다.
const Map<Palace, Map<String, double>> _palaceMetricSign = {
  Palace.illness: {
    // 높은 각 = 산근 평탄(吉상 weak) → 부호 뒤집어 palace zMean 에 반영.
    'nasofrontalAngle': -1.0,
  },
};

double _lookup(String key, Map<String, double> zMap, Map<String, double> nodeZ) {
  if (key.startsWith('node:')) {
    return nodeZ[key.substring(5)] ?? 0.0;
  }
  return zMap[key] ?? 0.0;
}

double _signedLookup(
  Palace palace,
  String key,
  Map<String, double> zMap,
  Map<String, double> nodeZ,
) {
  final v = _lookup(key, zMap, nodeZ);
  final sign = _palaceMetricSign[palace]?[key] ?? 1.0;
  return v * sign;
}

PalaceLevel _classifyLevel(double zMean) {
  if (zMean >= _levelThreshold) return PalaceLevel.strong;
  if (zMean <= -_levelThreshold) return PalaceLevel.weak;
  return PalaceLevel.balanced;
}

/// sub-flag 산출 — §3.2 의 전통 명칭을 metric 임계로 근사.
Set<PalaceFlag> _computeFlags({
  required Palace palace,
  required Map<String, double> zMap,
  required Map<String, double> nodeZ,
  required Map<String, bool> lateralFlags,
  required AgeGroup ageGroup,
}) {
  final flags = <PalaceFlag>{};
  double z(String id) => _lookup(id, zMap, nodeZ);
  double nz(String id) => nodeZ[id] ?? 0.0;

  switch (palace) {
    case Palace.life:
      // 미간이 넓고 밝음 — glabella 넓고 밝음 + 미간이 답답하게 좁지 않아야.
      if (nz('glabella') >= 1.0 && z('intercanthalRatio') >= -0.3) {
        flags.add(PalaceFlag.glabellaBright);
      }
      // 미간이 좁고 어두움 — glabella 어둡거나 미간 좁음. AND 조건으로 꽉 조이는 경우.
      if (nz('glabella') <= -1.0 && z('intercanthalRatio') <= -0.5) {
        flags.add(PalaceFlag.glabellaTight);
      }
      break;
    case Palace.wealth:
      if (nz('nose') >= 0.8 && z('nasalWidthRatio') >= 0.4) {
        flags.add(PalaceFlag.bulbousTip);
      }
      if (lateralFlags['aquilineNose'] == true) {
        flags.add(PalaceFlag.hookedNose);
      }
      if (z('nasalWidthRatio') <= -1.0) flags.add(PalaceFlag.thinBridge);
      break;
    case Palace.children:
      if (nz('eye') >= 0.6) flags.add(PalaceFlag.plumpLowerEyelid);
      if (nz('eye') <= -0.5) flags.add(PalaceFlag.hollowLowerEyelid);
      break;
    case Palace.spouse:
      final tiltAbs = z('eyeCanthalTilt').abs();
      if (tiltAbs <= 0.4 && !ageGroup.isOver30) {
        flags.add(PalaceFlag.smoothFishTail);
      }
      if (tiltAbs >= 1.0 && ageGroup.isOver30) {
        flags.add(PalaceFlag.fishTailWrinkle);
      }
      break;
    case Palace.illness:
      // lateral nasofrontalAngle: 높은 z = 산근 함몰 (flat transition).
      // FRAMEWORK §3.2 의 sanGenLow = z<-1 은 개념상 역전 — 우리는 실제
      // lateral geometry 가 높은 산근(움푹) = 깊은 각도 = nasofrontalAngle
      // z 음수 근사로 본다. 반대로 z≥+1 은 산근 평탄 = sanGenLow.
      // (직관: 동양인 평균 141°, 산근이 함몰하면 더 꺾여 각이 커진다.)
      final nf = z('nasofrontalAngle');
      if (nf >= 1.0) flags.add(PalaceFlag.sanGenLow);
      if (nf <= -1.0) flags.add(PalaceFlag.sanGenHigh);
      break;
    case Palace.fortune:
      if (z('upperFaceRatio') >= 0.8 && nz('forehead') >= 0.5) {
        flags.add(PalaceFlag.cloudlessForehead);
      }
      if (z('upperFaceRatio') <= -1.0 || nz('forehead') <= -0.8) {
        flags.add(PalaceFlag.dentedTemple);
      }
      break;
    case Palace.sibling:
    case Palace.property:
    case Palace.slave:
    case Palace.migration:
    case Palace.career:
    case Palace.parents:
      // flag 미정의 — state level 만으로 해석.
      break;
  }

  return flags;
}

/// 12 궁 state 전부 계산.
Map<Palace, PalaceState> computePalaceStates({
  required Map<String, double> zMap,
  required Map<String, double> nodeZ,
  required AgeGroup ageGroup,
  required Map<String, bool> lateralFlags,
}) {
  final out = <Palace, PalaceState>{};
  for (final p in Palace.values) {
    final signals = _palaceSignals[p]!;
    double sum = 0.0;
    double absMax = 0.0;
    int count = 0;
    for (final s in signals) {
      final v = _signedLookup(p, s, zMap, nodeZ);
      sum += v;
      if (v.abs() > absMax) absMax = v.abs();
      count++;
    }
    final zMean = count == 0 ? 0.0 : sum / count;
    final flags = _computeFlags(
      palace: p,
      zMap: zMap,
      nodeZ: nodeZ,
      lateralFlags: lateralFlags,
      ageGroup: ageGroup,
    );
    out[p] = PalaceState(
      palace: p,
      level: _classifyLevel(zMean),
      zMean: zMean,
      absZMax: absMax,
      flags: flags,
    );
  }
  return out;
}
