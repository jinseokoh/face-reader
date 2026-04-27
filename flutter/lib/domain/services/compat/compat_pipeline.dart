/// 궁합 엔진 end-to-end pipeline — 두 사람의 raw evidence → CompatibilityReport.
///
/// §10 capture-only 원칙: Hive 에는 `myReportId` · `albumReportId` 만 저장하고
/// 이 파이프라인으로 매번 재계산. 엔진 버전 업은 Hive drop 없이 이루어진다.
library;

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import '../yin_yang.dart';
import 'compat_aggregator.dart';
import 'compat_label.dart';
import 'element_classifier.dart';
import 'element_matrix.dart';
import 'five_element.dart';
import 'intimacy.dart';
import 'organ_pair_rules.dart';
import 'palace.dart';
import 'palace_pair_matcher.dart';
import 'palace_state.dart';
import 'qi_score.dart';
import 'yinyang_matcher.dart';
import 'zone_harmony.dart';

/// 한 사람의 파이프라인 입력. 관상 엔진 `FaceReadingReport` 로부터 직접
/// 채운다 — zMap 17+8, nodeZ 14, lateralFlags, FaceShape + confidence,
/// Gender/AgeGroup.
class CompatPersonInput {
  final Map<String, double> zMap;
  final Map<String, double> nodeZ;
  final Map<String, bool> lateralFlags;
  final FaceShape faceShape;
  final double shapeConfidence;
  final Gender gender;
  final AgeGroup ageGroup;

  const CompatPersonInput({
    required this.zMap,
    required this.nodeZ,
    required this.lateralFlags,
    required this.faceShape,
    required this.shapeConfidence,
    required this.gender,
    required this.ageGroup,
  });
}

/// §10 schema (v1). narrative 는 P6 에서 뒤에 붙는다 — 현 시점엔 없음.
class CompatibilityReport {
  static const int kCompatSchemaVersion = 1;
  final int schemaVersion = kCompatSchemaVersion;

  // L1 五行.
  final FiveElements myElement;
  final FiveElements albumElement;
  final ElementRelation elementRelation; // 方向성 kind (my 관점). score 는 비대칭.

  // L2 十二宮.
  final Map<Palace, PalaceState> myPalaces;
  final Map<Palace, PalaceState> albumPalaces;
  final PalacePairResult palacePair;

  // L3a/b/c 氣質.
  final OrganPairResult organPair;
  final ZoneHarmony zoneHarmony;
  final YinYangMatch yinYangMatch;
  final QiScoreResult qiScore;

  // L4 性情.
  final IntimacyResult intimacy;

  // aggregate.
  final CompatSubScores sub;
  final double total;
  final CompatLabel label;

  // narrative perspective — intimacy chapter 의 gender-별 advice 분기 등에 사용.
  final Gender myGender;

  const CompatibilityReport({
    required this.myElement,
    required this.albumElement,
    required this.elementRelation,
    required this.myPalaces,
    required this.albumPalaces,
    required this.palacePair,
    required this.organPair,
    required this.zoneHarmony,
    required this.yinYangMatch,
    required this.qiScore,
    required this.intimacy,
    required this.sub,
    required this.total,
    required this.label,
    required this.myGender,
  });
}

/// L1 element score 는 matrix 가 directional (生 70 / 被生 65 등) 이라 비대칭.
/// §8.2 #3 total 대칭 불변을 만족시키기 위해 aggregator 에 주입할 땐 forward
/// 와 reverse 의 산술 평균을 쓴다. narrative 용 kind 는 forward 방향 유지.
double _symmetricElementScore(ElementRelation fwd, ElementRelation rev) =>
    (fwd.score + rev.score) / 2.0;

CompatibilityReport analyzeCompatibility({
  required CompatPersonInput my,
  required CompatPersonInput album,
  CompatLabelThresholds thresholds = kCompatLabelThresholds,
}) {
  // ── L1 五形 ─────────────────────────────────────────────
  final myEl = classifyFiveElements(
    zMap: my.zMap,
    faceShape: my.faceShape,
    shapeConfidence: my.shapeConfidence,
  );
  final alEl = classifyFiveElements(
    zMap: album.zMap,
    faceShape: album.faceShape,
    shapeConfidence: album.shapeConfidence,
  );
  final elFwd = elementRelationScore(my: myEl, album: alEl);
  final elRev = elementRelationScore(my: alEl, album: myEl);
  final elementSymScore = _symmetricElementScore(elFwd, elRev);

  // ── L2 十二宮 ───────────────────────────────────────────
  final myPalaces = computePalaceStates(
    zMap: my.zMap,
    nodeZ: my.nodeZ,
    ageGroup: my.ageGroup,
    lateralFlags: my.lateralFlags,
  );
  final alPalaces = computePalaceStates(
    zMap: album.zMap,
    nodeZ: album.nodeZ,
    ageGroup: album.ageGroup,
    lateralFlags: album.lateralFlags,
  );
  final palacePair = palacePairScore(my: myPalaces, album: alPalaces);

  // ── L3 氣質 ────────────────────────────────────────────
  final organ = organPairScore(
    myZ: my.zMap,
    albumZ: album.zMap,
    myFlags: my.lateralFlags,
    albumFlags: album.lateralFlags,
  );
  final zone = matchZoneHarmony(
    my: computeZoneStates(my.zMap),
    album: computeZoneStates(album.zMap),
  );
  final yy = matchYinYang(
    my: computeYinYang(my.zMap),
    album: computeYinYang(album.zMap),
    myGender: my.gender,
    albumGender: album.gender,
  );
  final qi = computeQiScore(organ: organ, zone: zone, yinYang: yy);

  // ── L4 性情 (gate) ─────────────────────────────────────
  final intimacy = computeIntimacy(
    myZ: my.zMap,
    albumZ: album.zMap,
    myPalaces: myPalaces,
    albumPalaces: alPalaces,
    myGender: my.gender,
    albumGender: album.gender,
    myAge: my.ageGroup,
    albumAge: album.ageGroup,
  );

  // ── aggregate ──────────────────────────────────────────
  final sub = CompatSubScores(
    elementScore: elementSymScore,
    palaceScore: palacePair.subScore,
    qiScore: qi.subScore,
    intimacyScore: intimacy.subScore,
  );
  final agg = aggregateCompat(sub: sub, thresholds: thresholds);

  return CompatibilityReport(
    myElement: myEl,
    albumElement: alEl,
    elementRelation: elFwd,
    myPalaces: myPalaces,
    albumPalaces: alPalaces,
    palacePair: palacePair,
    organPair: organ,
    zoneHarmony: zone,
    yinYangMatch: yy,
    qiScore: qi,
    intimacy: intimacy,
    sub: sub,
    total: agg.total,
    label: agg.label,
    myGender: my.gender,
  );
}
