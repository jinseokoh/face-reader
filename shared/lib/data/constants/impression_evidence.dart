/// 1층 — 학술 보고 관계.
///
/// 공개 학술연구가 검증한 "얼굴의 물리적 특징 → 사회적 첫인상" 의 방향만 적는다.
/// 원 논문의 계수를 옮기지 않는다 (APPLE.md §81.1). 여기 적힌 것은 부호(+/−)와
/// 논문에서의 비중(주/보조)뿐이고, 어떤 계측으로 그 특징을 재구성하는지는
/// 2층(`impression_features.dart`)이, 점수로 만드는 식은 3층
/// (`first_impression.dart`)이 맡는다.
///
/// 출처
/// - [OT08]  Oosterhof & Todorov 2008, PNAS 105(32). 얼굴 평가의 2축(valence≈
///           trustworthiness, dominance). 신뢰감은 표정을 닮은 특징(입꼬리·눈썹
///           안쪽)에, 지배력은 신체적 강함을 닮은 특징(얼굴 폭·턱·눈썹 높이)에
///           민감.
/// - [TD13]  Todorov, Dotsch, Porter, Oosterhof & Falvello 2013, Emotion 13(4).
///           7개 판단(attractiveness·competence·dominance·extroversion·
///           likability·threat·trustworthiness)의 데이터 기반 형태 모델 검증.
/// - [SU13]  Sutherland et al. 2013, Cognition 127(1). 1,000장 ambient 사진에서
///           approachability · youthful-attractiveness · dominance 3축.
/// - [SU18]  Sutherland et al. 2018, PSPB 44(4). 중국·영국 평가자에서 같은
///           approachability · youthful-attractiveness 축 확인 (동아시아 적용 근거).
/// - [VE14]  Vernon, Sutherland, Young & Hartley 2014, PNAS 111(32). 랜드마크
///           기반 물리 속성 65개의 선형 조합이 3축 인상 변동 58% 설명. 입 모양
///           (웃는 방향)이 approachability 의 최대 기여, 눈 크기·눈썹이
///           youthful-attractiveness, 얼굴 폭·눈썹 높이·턱이 dominance.
/// - [RH06]  Rhodes 2006, Annual Review of Psychology 57. 매력의 진화적 기초:
///           평균성·대칭·성별 전형성.
library;

/// 첫인상 축 (v1 4축). 표시명은 반드시 "~한 인상" 형태 — 성격이 아니다.
enum ImpressionAxis {
  trust('신뢰감 있는 인상', 'trustworthy'),
  approach('친근한 인상', 'approachable'),
  dominance('주도적인 인상', 'dominant'),
  attractive('매력적인 인상', 'attractive');

  const ImpressionAxis(this.labelKo, this.labelEn);

  final String labelKo;
  final String labelEn;
}

/// 논문에서의 비중. 3층은 primary 1.0 · secondary 0.5 로 쓴다.
enum EvidenceTier { primary, secondary }

/// 논문이 보고한 물리적 특징 하나. [feature] 는 2층의 재구성 feature id.
class EvidenceLink {
  final ImpressionAxis axis;

  /// 2층 feature id (`impression_features.dart`).
  final String feature;

  /// +1: feature 값이 클수록 그 인상이 강함. −1: 반대.
  final int sign;
  final EvidenceTier tier;

  /// 논문이 보고한 특징의 서술 (재구성 근거를 남긴다).
  final String reported;
  final List<String> sources;

  const EvidenceLink({
    required this.axis,
    required this.feature,
    required this.sign,
    required this.tier,
    required this.reported,
    required this.sources,
  });
}

const List<EvidenceLink> impressionEvidence = [
  // ── 신뢰감 있는 인상 ──
  EvidenceLink(
    axis: ImpressionAxis.trust,
    feature: 'mouthCornerUp',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '입꼬리가 올라간(U자) 입 — 미소를 닮은 형태가 신뢰감을 높인다',
    sources: ['OT08', 'TD13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.trust,
    feature: 'browHeight',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '눈썹 안쪽이 올라간(높은) 눈썹 — 찡그림의 반대 형태',
    sources: ['OT08', 'TD13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.trust,
    feature: 'eyeOpenness',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '크게 열린 눈',
    sources: ['OT08'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.trust,
    feature: 'eyeTiltUp',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '내려가지 않은 눈꼬리',
    sources: ['TD13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.trust,
    feature: 'symmetry',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '좌우 대칭 — 매력·신뢰 평가와 함께 움직이는 특징',
    sources: ['RH06', 'TD13'],
  ),

  // ── 친근한 인상 (approachability) ──
  EvidenceLink(
    axis: ImpressionAxis.approach,
    feature: 'mouthCornerUp',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '입 모양(웃는 방향)이 approachability 의 최대 기여',
    sources: ['VE14', 'SU13', 'SU18'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.approach,
    feature: 'eyeOpenness',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '열린 눈 — 눈 영역이 approachability 의 두 번째 기여',
    sources: ['VE14'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.approach,
    feature: 'browArch',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '아치형 눈썹 (찡그림의 반대)',
    sources: ['VE14'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.approach,
    feature: 'jawRoundness',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '둥근 하안면 — 각진 턱의 반대 (위협 신호의 부재)',
    sources: ['OT08', 'SU13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.approach,
    feature: 'lowerFaceFullness',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '풍만한 볼·하안면 — 어려 보임·부드러움과 함께 묶이는 특징',
    sources: ['SU13'],
  ),

  // ── 주도적인 인상 (dominance) ──
  EvidenceLink(
    axis: ImpressionAxis.dominance,
    feature: 'faceWidth',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '넓은 얼굴(높은 폭/높이 비) — 신체적 강함을 닮은 특징',
    sources: ['OT08', 'VE14'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.dominance,
    feature: 'jawWidth',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '넓고 큰 턱',
    sources: ['OT08', 'TD13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.dominance,
    feature: 'browHeight',
    sign: -1,
    tier: EvidenceTier.primary,
    reported: '낮은(눈에 가까운) 눈썹',
    sources: ['OT08', 'VE14'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.dominance,
    feature: 'browThickness',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '굵은 눈썹 — 남성적 특징',
    sources: ['TD13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.dominance,
    feature: 'cheekboneWidth',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '넓은 광대',
    sources: ['OT08'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.dominance,
    feature: 'jawRoundness',
    sign: -1,
    tier: EvidenceTier.secondary,
    reported: '각진 턱',
    sources: ['OT08', 'VE14'],
  ),

  // ── 매력적인 인상 ──
  EvidenceLink(
    axis: ImpressionAxis.attractive,
    feature: 'averageness',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '평균에 가까운 얼굴이 더 매력적으로 평가된다',
    sources: ['RH06'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.attractive,
    feature: 'symmetry',
    sign: 1,
    tier: EvidenceTier.primary,
    reported: '좌우 대칭이 높을수록 매력적으로 평가된다',
    sources: ['RH06'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.attractive,
    feature: 'eyeOpenness',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '큰 눈 — youthful-attractiveness 축의 기여',
    sources: ['VE14', 'SU13'],
  ),
  EvidenceLink(
    axis: ImpressionAxis.attractive,
    feature: 'mouthCornerUp',
    sign: 1,
    tier: EvidenceTier.secondary,
    reported: '웃는 방향의 입 — youthful-attractiveness 와 함께 움직임',
    sources: ['VE14'],
  ),
];
