/// 관상 분류 체계 (Physiognomy Taxonomy) — 코드 구현.
///
/// SSOT 문서: `docs/engine/TAXONOMY.md` v1.0 (2026-04-18).
/// α 옵션: 삼정(三停) 우선 tree + 오관/오악/사독/십이궁 메타데이터 오버레이.
///
/// 14 노드 = 루트 1 + 삼정 3 + leaf 10.
library;

/// 삼정(三停) — 얼굴 수직 3분할.
enum Zone { upper, middle, lower }

/// 오관(五官) — 기능적 기관. 이름은 각 관이 담당하는 부위로 매핑.
enum Organ {
  /// 보수관(保壽官) — 눈썹.
  eyebrow,

  /// 감찰관(監察官) — 눈.
  eye,

  /// 심변관(審辨官) — 코.
  nose,

  /// 출납관(出納官) — 입.
  mouth,

  /// 채청관(採聽官) — 귀.
  ear,
}

/// 오악(五嶽) — 돌출 영역 볼륨 평가. 방위로 구분.
enum Mountain {
  /// 형산(衡山, 남) — 이마.
  south,

  /// 태산(泰山, 동) — 좌 광대.
  east,

  /// 화산(華山, 서) — 우 광대.
  west,

  /// 숭산(嵩山, 중) — 코.
  center,

  /// 항산(恒山, 북) — 턱.
  north,
}

/// 사독(四瀆) — 유통 평가(통/막힘).
enum River {
  /// 강(江) — 귀.
  jiang,

  /// 하(河) — 눈.
  he,

  /// 회(淮) — 코.
  huai,

  /// 제(濟) — 입.
  ji,
}

/// 십이궁(十二宮) — 인생 영역 매핑. 한글 romanized.
/// 복덕궁(bokdeok)·상모궁(sangmo)은 cross-node overlay 용.
enum Palace {
  /// 명궁 — 운명 핵심.
  myeong,

  /// 재백궁 — 재물.
  jaebaek,

  /// 형제궁 — 형제/친구.
  hyeongje,

  /// 전택궁 — 주거/가산.
  jeontaek,

  /// 남녀궁 — 자녀/생식.
  namnyeo,

  /// 노복궁 — 부하운.
  nobok,

  /// 처첩궁 — 배우자.
  cheocheop,

  /// 질액궁 — 건강/질병.
  jilaek,

  /// 천이궁 — 이주/사회.
  cheoni,

  /// 관록궁 — 관직/명예.
  gwallok,

  /// 복덕궁 — 복/덕 (cross-node).
  bokdeok,

  /// 상모궁 — 전체 외모 (cross-node).
  sangmo,
}

/// Tree 노드. 루트·zone·leaf 모두 동일 타입.
class PhysiognomyNode {
  /// 기계 식별자. `'face'`, `'upper'`, `'forehead'` 등.
  final String id;

  /// 한글 표시명.
  final String nameKo;

  /// 소속 삼정. 루트는 null.
  final Zone? zone;

  /// 오관 태그.
  final List<Organ> organs;

  /// 오악 태그.
  final List<Mountain> mountains;

  /// 사독 태그.
  final List<River> rivers;

  /// 십이궁 태그.
  final List<Palace> palaces;

  /// 이 노드 스코프에서 집계되는 metric id 목록.
  /// frontal + lateral 모두 포함. 루트·zone 은 통상 비어있음(roll-up 만 수행).
  final List<String> metricIds;

  /// v1.0 에서 측정 미지원 노드(MediaPipe 기술 제약 등).
  final bool unsupported;

  /// 자식 노드.
  final List<PhysiognomyNode> children;

  const PhysiognomyNode({
    required this.id,
    required this.nameKo,
    this.zone,
    this.organs = const [],
    this.mountains = const [],
    this.rivers = const [],
    this.palaces = const [],
    this.metricIds = const [],
    this.unsupported = false,
    this.children = const [],
  });
}

// ───────────────────────── 14 노드 const tree ─────────────────────────
//
// metricIds 는 이 노드 스코프에서 집계되는 metric 만 명시.
// - 고아 2개(eyebrowLength, noseBridgeRatio) 는 tree 밖 classifier 전용.
// - browSpacing 은 glabella·명궁 노드로 편입 (Phase 2, 2026-04-18).
// - 귀 노드는 metric 0 + unsupported=true.
// - 복덕궁·상모궁은 cross-node overlay 이므로 leaf 태그에 포함하지 않음.

const PhysiognomyNode _forehead = PhysiognomyNode(
  id: 'forehead',
  nameKo: '이마',
  zone: Zone.upper,
  mountains: [Mountain.south],
  palaces: [Palace.gwallok, Palace.cheoni],
  metricIds: ['upperFaceRatio', 'foreheadWidth'],
);

const PhysiognomyNode _glabella = PhysiognomyNode(
  id: 'glabella',
  nameKo: '미간',
  zone: Zone.upper,
  palaces: [Palace.myeong],
  metricIds: ['browSpacing'],
);

const PhysiognomyNode _eyebrow = PhysiognomyNode(
  id: 'eyebrow',
  nameKo: '눈썹',
  zone: Zone.upper,
  organs: [Organ.eyebrow],
  palaces: [Palace.hyeongje],
  metricIds: [
    'eyebrowThickness',
    'browEyeDistance',
    'eyebrowTiltDirection',
    'eyebrowCurvature',
  ],
);

const PhysiognomyNode _eye = PhysiognomyNode(
  id: 'eye',
  nameKo: '눈',
  zone: Zone.middle,
  organs: [Organ.eye],
  rivers: [River.he],
  palaces: [Palace.jeontaek, Palace.namnyeo, Palace.cheocheop],
  metricIds: [
    'intercanthalRatio',
    'eyeFissureRatio',
    'eyeCanthalTilt',
    'eyeAspect',
  ],
);

const PhysiognomyNode _nose = PhysiognomyNode(
  id: 'nose',
  nameKo: '코',
  zone: Zone.middle,
  organs: [Organ.nose],
  mountains: [Mountain.center],
  rivers: [River.huai],
  palaces: [Palace.jaebaek, Palace.jilaek],
  metricIds: [
    'nasalWidthRatio',
    'nasalHeightRatio',
    'nasofrontalAngle',
    'nasolabialAngle',
    'noseTipProjection',
    'dorsalConvexity',
  ],
);

const PhysiognomyNode _cheekbone = PhysiognomyNode(
  id: 'cheekbone',
  nameKo: '광대',
  zone: Zone.middle,
  mountains: [Mountain.east, Mountain.west],
  metricIds: ['cheekboneWidth'],
);

const PhysiognomyNode _ear = PhysiognomyNode(
  id: 'ear',
  nameKo: '귀',
  zone: Zone.middle,
  organs: [Organ.ear],
  rivers: [River.jiang],
  metricIds: [],
  unsupported: true, // MediaPipe 정면 mesh 커버리지 부족 — v1.0 미지원.
);

const PhysiognomyNode _philtrum = PhysiognomyNode(
  id: 'philtrum',
  nameKo: '인중',
  zone: Zone.lower,
  metricIds: ['philtrumLength'],
);

const PhysiognomyNode _mouth = PhysiognomyNode(
  id: 'mouth',
  nameKo: '입',
  zone: Zone.lower,
  organs: [Organ.mouth],
  rivers: [River.ji],
  metricIds: [
    'mouthWidthRatio',
    'mouthCornerAngle',
    'lipFullnessRatio',
    'upperVsLowerLipRatio',
    'upperLipEline',
    'lowerLipEline',
    'mentolabialAngle',
  ],
);

const PhysiognomyNode _chin = PhysiognomyNode(
  id: 'chin',
  nameKo: '턱',
  zone: Zone.lower,
  mountains: [Mountain.north],
  palaces: [Palace.nobok],
  metricIds: [
    'gonialAngle',
    'lowerFaceRatio',
    'lowerFaceFullness',
    'chinAngle',
    'facialConvexity',
  ],
);

const PhysiognomyNode _upperZone = PhysiognomyNode(
  id: 'upper',
  nameKo: '상정',
  zone: Zone.upper,
  children: [_forehead, _glabella, _eyebrow],
);

const PhysiognomyNode _middleZone = PhysiognomyNode(
  id: 'middle',
  nameKo: '중정',
  zone: Zone.middle,
  children: [_eye, _nose, _cheekbone, _ear],
);

const PhysiognomyNode _lowerZone = PhysiognomyNode(
  id: 'lower',
  nameKo: '하정',
  zone: Zone.lower,
  children: [_philtrum, _mouth, _chin],
);

/// root node. 얼굴 전체 종합 지표는 aggregation 으로 별도 계산.
/// `faceAspectRatio`, `faceTaperRatio`, `midFaceRatio` 등 root-scope metric 은
/// 특정 leaf 에 매이지 않으므로 root 에 배치.
const PhysiognomyNode faceTree = PhysiognomyNode(
  id: 'face',
  nameKo: '얼굴',
  metricIds: ['faceAspectRatio', 'faceTaperRatio', 'midFaceRatio'],
  children: [_upperZone, _middleZone, _lowerZone],
);

// ───────────────────────── 룩업 헬퍼 ─────────────────────────

List<PhysiognomyNode> _flatten(PhysiognomyNode root) {
  final out = <PhysiognomyNode>[];
  void walk(PhysiognomyNode n) {
    out.add(n);
    for (final c in n.children) {
      walk(c);
    }
  }
  walk(root);
  return out;
}

/// 모든 노드(루트 포함) 리스트. 테스트·디버그·UI 에서 재활용.
final List<PhysiognomyNode> allNodes = List.unmodifiable(_flatten(faceTree));

/// id → 노드 룩업. 존재하지 않는 id 는 null.
final Map<String, PhysiognomyNode> nodeById =
    Map.unmodifiable({for (final n in allNodes) n.id: n});

/// metric id → 소속 노드 룩업.
/// 한 metric 은 정확히 한 노드에만 속한다는 규약 — 중복 등록 시 첫 번째 유지.
final Map<String, PhysiognomyNode> nodeByMetricId = _buildMetricIndex();

Map<String, PhysiognomyNode> _buildMetricIndex() {
  final out = <String, PhysiognomyNode>{};
  for (final n in allNodes) {
    for (final m in n.metricIds) {
      out.putIfAbsent(m, () => n);
    }
  }
  return Map.unmodifiable(out);
}
