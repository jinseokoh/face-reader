/// 2층 — 재구성 feature.
///
/// 1층(`impression_evidence.dart`)이 말하는 물리적 특징을 이 앱의 정면 계측
/// (`FaceMetrics.computeAll` 28개 중 referenceData 가 있는 26개)으로 다시
/// 정의한다. 입력은 metric id → z-score (AAF 동아시아 성별 기준). 출력은
/// feature id → z 스케일 값. 계측이 이미 z 이므로 대부분은 이름만 바꾸는
/// 대응이고, `averageness` 만 여러 계측을 합친다.
///
/// 논문의 feature 정의를 그대로 재현했다고 주장하지 않는다. 각 항목의 주석이
/// "논문이 말한 특징을 우리 계측 중 무엇으로 대신하는가" 를 적는다.
library;

/// feature id → 그 feature 를 만드는 계측 id 와 부호.
/// 부호 −1 은 "계측이 작을수록 feature 가 큼".
class FeatureSpec {
  final String id;
  final String metric;
  final int sign;
  final String note;

  const FeatureSpec(this.id, this.metric, this.sign, this.note);
}

const List<FeatureSpec> impressionFeatureSpecs = [
  FeatureSpec('mouthCornerUp', 'mouthCornerAngle', 1,
      '입꼬리 각(+ 올라감). 논문의 "U자 입·웃는 방향" 을 대신한다.'),
  FeatureSpec('browHeight', 'browEyeDistance', 1,
      '눈썹-눈 거리. 논문의 "눈썹 안쪽 높이" 를 눈썹 전체 높이로 대신한다.'),
  FeatureSpec('eyeOpenness', 'eyeAspect', 1,
      '눈 세로/가로 비. 논문의 "눈 크기·개방" 을 대신한다.'),
  FeatureSpec('eyeTiltUp', 'eyeCanthalTilt', 1,
      '눈꼬리 각(+ 올라감).'),
  FeatureSpec('browArch', 'eyebrowCurvature', 1,
      '눈썹 곡률(+ 아치).'),
  FeatureSpec('jawRoundness', 'gonialAngle', 1,
      '하악각(클수록 둥근 턱). 논문의 "각진 턱" 은 부호 반대로 쓴다.'),
  FeatureSpec('lowerFaceFullness', 'lowerFaceFullness', 1,
      '하단 풍만도.'),
  FeatureSpec('faceWidth', 'faceAspectRatio', -1,
      '얼굴 세로/가로 비의 반대. 논문의 "넓은 얼굴(fWHR)" 을 대신한다.'),
  FeatureSpec('jawWidth', 'faceTaperRatio', 1,
      '턱 폭/얼굴 폭.'),
  FeatureSpec('browThickness', 'eyebrowThickness', 1,
      '눈썹 두께.'),
  FeatureSpec('cheekboneWidth', 'cheekboneWidth', 1,
      '광대 폭/얼굴 폭.'),
];

/// `averageness` 에 들어가는 계측 — referenceData 가 있는 26개 전부.
/// 값 = −(|z| 의 평균). 평균에 가까울수록 크다.
const String averagenessFeatureId = 'averageness';

/// metric z-map → feature z-map.
///
/// [zByMetric] 에 없는 계측은 건너뛴다 (부분 입력 허용). `averageness` 는
/// [referenceMetricIds] 중 존재하는 것들의 |z| 평균으로 만든다.
Map<String, double> buildImpressionFeatures(
  Map<String, double> zByMetric, {
  required Iterable<String> referenceMetricIds,
}) {
  final out = <String, double>{};
  for (final spec in impressionFeatureSpecs) {
    final z = zByMetric[spec.metric];
    if (z == null) continue;
    out[spec.id] = spec.sign * z;
  }
  var sum = 0.0;
  var n = 0;
  for (final id in referenceMetricIds) {
    final z = zByMetric[id];
    if (z == null) continue;
    sum += z.abs();
    n++;
  }
  if (n > 0) out[averagenessFeatureId] = -(sum / n);
  return out;
}
