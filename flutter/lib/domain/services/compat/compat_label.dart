/// 궁합 4-tier label — §8.1.
library;

enum CompatLabel { cheonjakjihap, sangkyeongyeobin, mahapgaseong, hyeonggeuknanjo }

extension CompatLabelLabel on CompatLabel {
  String get hanja {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '天作之合';
      case CompatLabel.sangkyeongyeobin:
        return '相敬如賓';
      case CompatLabel.mahapgaseong:
        return '磨合可成';
      case CompatLabel.hyeonggeuknanjo:
        return '刑剋難調';
    }
  }

  String get korean {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '천작지합';
      case CompatLabel.sangkyeongyeobin:
        return '상경여빈';
      case CompatLabel.mahapgaseong:
        return '마합가성';
      case CompatLabel.hyeonggeuknanjo:
        return '형극난조';
    }
  }

  /// 10/30/30/30 목표 분포.
  double get targetShare {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return 0.10;
      case CompatLabel.sangkyeongyeobin:
        return 0.30;
      case CompatLabel.mahapgaseong:
        return 0.30;
      case CompatLabel.hyeonggeuknanjo:
        return 0.30;
    }
  }
}

/// §8.1 초기 경계. MC 재보정 완료 후 이 표 갱신.
/// total ≥ thresholds.cheonjakjihap → 天作之合
/// total ≥ thresholds.sangkyeongyeobin → 相敬如賓
/// total ≥ thresholds.mahapgaseong → 磨合可成
/// else → 刑剋難調
class CompatLabelThresholds {
  final double cheonjakjihap;
  final double sangkyeongyeobin;
  final double mahapgaseong;

  const CompatLabelThresholds({
    required this.cheonjakjihap,
    required this.sangkyeongyeobin,
    required this.mahapgaseong,
  });
}

/// MC 재보정 결과 — `compat_calibration_test.dart` 의 20k pair seed=42 분포에서
/// total 의 p90/p60/p30. 10/30/30/30 target 분포를 달성한다.
const CompatLabelThresholds kCompatLabelThresholds = CompatLabelThresholds(
  cheonjakjihap: 59.63,
  sangkyeongyeobin: 54.44,
  mahapgaseong: 50.54,
);

CompatLabel classifyLabel(double total,
    {CompatLabelThresholds thresholds = kCompatLabelThresholds}) {
  if (total >= thresholds.cheonjakjihap) return CompatLabel.cheonjakjihap;
  if (total >= thresholds.sangkyeongyeobin) return CompatLabel.sangkyeongyeobin;
  if (total >= thresholds.mahapgaseong) return CompatLabel.mahapgaseong;
  return CompatLabel.hyeonggeuknanjo;
}
