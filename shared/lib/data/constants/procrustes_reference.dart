/// 닮은 정도(Procrustes) 보정 상수 — AAF 11,800장 무작위 쌍 실측.
///
/// 정규화·Procrustes 정렬(`landmark_normalize.dart`) 뒤의 RMS 거리를 0~100 으로
/// 바꾸는 기준. 무작위 쌍의 중앙 거리가 50점이 되도록 영역마다 지수 감쇠한다.
/// 재생성: flutter test test/procrustes_calibration_test.dart
library;

/// 무작위 쌍 RMS 거리 중앙값 — 'overall' + 영역 6.
const Map<String, double> kProcrustesDistanceMedian = {
  'overall': 0.11054,
  'outline': 0.19718,
  'eyes': 0.05868,
  'brows': 0.09006,
  'nose': 0.10597,
  'mouth': 0.10029,
  'jaw': 0.21309,
};

/// 영역별 닮은 정도의 무작위 쌍 사분위 [p75, p50, p25] — §25 문구(매우 유사·유사·
/// 차이가 있음·차이가 큼)의 경계. 같은 쌍.
const Map<String, List<double>> kRegionSimilarityQuartiles = {
  'overall': [58.8, 50.0, 41.1],
  'outline': [61.8, 50.0, 38.4],
  'eyes': [59.1, 50.0, 40.4],
  'brows': [59.6, 50.0, 40.5],
  'nose': [62.6, 50.0, 38.5],
  'mouth': [59.8, 50.0, 40.3],
  'jaw': [62.6, 50.0, 37.9],
};

/// 무작위 쌍의 닮은 정도(overall) 21-point 분위 — "무작위 두 사람 중 상위 N%".
const List<double> kPairSimilarityQuantiles = [12.6, 29.3, 33.4, 36.3, 38.8, 41.1, 43.1, 44.9, 46.6, 48.4, 50.0, 51.6, 53.3, 55.1, 56.8, 58.8, 60.9, 63.2, 66.0, 70.0, 86.4];

/// 무작위 쌍의 케미 합(조화도+보완도+닮은 정도) 21-point 분위.
const List<double> kChemistryQuantiles = [51.0, 105.3, 114.6, 120.9, 126.0, 130.5, 134.6, 138.4, 141.8, 145.2, 148.7, 152.0, 155.5, 159.0, 162.8, 167.2, 171.6, 177.0, 184.0, 194.7, 240.1];
