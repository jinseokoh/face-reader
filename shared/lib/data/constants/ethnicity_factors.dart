import 'package:face_engine/data/enums/ethnicity.dart';

/// Per-ethnicity scale factors used by the report pipeline *beyond* z-score
/// baseline correction (which is handled in `face_reference_data.dart`).
///
/// 세 축 모두 peer-reviewed 근거가 있는 anatomy 차원이며, baseline mean/sd 로
/// 흡수되지 않는 *2차* 신호다:
///
/// 1. [agingTrajectoryScale]  — 노화 보정 강도 (50+ 만 발동)
/// 2. [dimorphismScale]       — 성별 weight delta 크기
/// 3. [physiognomyCanonScale] — 麻衣相法 rule 의 cultural-domain dampening
///
/// 값은 보수적으로 잡음 — empirical 검증이 누적되면 미세조정. 모든 lookup 은
/// `?? 1.0` fallback 으로 안전 (enum 확장 시 baseline 동작).

/// Aging trajectory scale per ethnicity.
///
/// `age_adjustment.dart` 의 50+ z-shift offset 에 곱해진다. wrinkle / sagging /
/// philtrum lengthening / lip thinning 같은 노화 신호의 *발현 시점* 이 인종별
/// ~10년 shift 라는 dermatology robust 발견 반영.
///
/// References:
///   - Vashi NA et al. (2016) *Aging Differences in Ethnic Skin*
///     J Clin Aesthet Dermatol 9(1):31-32. PMC4756870.
///     → Asian skin: wrinkle onset ~10y delayed vs Caucasian.
///   - Rawlings AV (2006) *The different characteristics of facial skin aging
///     in Caucasian, African American, Indian, Hispanic, and East Asian women*
///     J Am Acad Dermatol 54:S190-S196.
///     → African American: fine line onset 5-6th decade.
///   - Tsukahara K et al. (2007) — Japanese·Chinese·Thai sagging differences.
///
/// Baseline 1.0 = caucasian (Vashi/Rawlings reference cohort).
const Map<Ethnicity, double> agingTrajectoryScale = {
  Ethnicity.caucasian: 1.0,
  Ethnicity.hispanic: 1.0,
  Ethnicity.middleEastern: 1.0,
  Ethnicity.eastAsian: 0.6,
  Ethnicity.southeastAsian: 0.6,
  Ethnicity.african: 0.5,
};

/// Sexual dimorphism magnitude scale per ethnicity.
///
/// `attribute_derivation.dart::_effectiveWeight` 의 `_GenderDelta` 에 곱해진다.
/// 남녀 face shape 거리가 인종별로 다르다는 cross-population finding.
///
/// References:
///   - Kleisner K et al. (2021) *How and why patterns of sexual dimorphism in
///     human faces vary across the world* Sci Rep 11:5978. PMC7966798.
///     → European/South American > African; smaller/isolated populations lower.
///   - Weinberg SM et al. (2016) *Using the 3D Facial Norms Database to
///     investigate craniofacial sexual dimorphism* Biol Sex Differ 7:46.
///   - Flis (Folia Morphologica review):
///     "facial sexual dimorphism data obtained from one population can neither
///      be considered representative of another population... algorithms ...
///      should take biogeographical ancestry into account."
///
/// Baseline 1.0 = caucasian/hispanic/middleEastern (Kleisner Tier-1 cohort).
const Map<Ethnicity, double> dimorphismScale = {
  Ethnicity.caucasian: 1.0,
  Ethnicity.hispanic: 1.0,
  Ethnicity.middleEastern: 1.0,
  Ethnicity.eastAsian: 0.7,
  Ethnicity.southeastAsian: 0.7,
  Ethnicity.african: 0.6,
};

/// East-Asian physiognomy canon scale per ethnicity.
///
/// Stage 2-5 rule effect magnitude 에 곱해진다 (Zone/Organ/Palace/Age/Lateral).
/// z-score baseline 으로 anatomical 차이는 흡수되지만, 麻衣相法·神相全編·
/// 유장상법의 *해석 rule* 자체는 漢族·朝鮮 얼굴 canon 에서 calibrate 됨.
/// 비-동아시아 얼굴에 같은 magnitude 로 발동하면 invalid 일반화.
///
/// 근거 (도메인 구조적 + cross-cultural):
///   - 麻衣相法 卷一 五官總論 — 鼻 (재백궁), 印堂, 산근 임계가 漢族 평균 비율
///     기준으로 fixed. magnitude 가 그 canon 안에서 calibrate 됨.
///   - 神相全編 卷四 十二宮 — 천창·지각·간문·처첩궁의 cutoff 가 동아시아 얼굴
///     분포 기반.
///   - Coetzee V et al. (2014) PLOS ONE PMC4079334 — cross-cultural
///     attractiveness universal floor 는 유지되나 own-race bias 가 비-EA
///     해석의 신뢰도 하락 시사.
///
/// 동남아시아 (베트남·태국·필리핀): 麻衣相法 의 漢字 문화권 전파 역사로
/// 명목 1.0 에 근접 (0.9). 그 외 인종: 외부 cultural domain (0.7) — 완전
/// 차단이 아니라 universal anatomy signal 은 흘리되 rule 의 *동아시아 특수
/// 해석* 강도만 낮춤.
const Map<Ethnicity, double> physiognomyCanonScale = {
  Ethnicity.eastAsian: 1.0,
  Ethnicity.southeastAsian: 0.9,
  Ethnicity.caucasian: 0.7,
  Ethnicity.hispanic: 0.7,
  Ethnicity.middleEastern: 0.7,
  Ethnicity.african: 0.7,
};
