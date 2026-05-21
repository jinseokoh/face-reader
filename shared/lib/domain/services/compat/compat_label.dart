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

/// §8.1 label 경계 — 100점 만점 UI scale.
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

/// MC 20k seed=42 측정의 p30/p60/p90 (61.56 / 81.42 / 90.50) 을 그대로 사용해
/// 10/30/30/30 target 분포를 자연스럽게 만든다. intimacy 가 모든 페어에서
/// 실제 계산되도록 변경되면서 user-scale 분포가 위로 시프트 — anchor 는 그대로
/// 두고 label boundary 만 새 분포에 맞춤.
const CompatLabelThresholds kCompatLabelThresholds = CompatLabelThresholds(
  cheonjakjihap: 90.5,
  sangkyeongyeobin: 81.5,
  mahapgaseong: 61.5,
);

CompatLabel classifyLabel(double total,
    {CompatLabelThresholds thresholds = kCompatLabelThresholds}) {
  if (total >= thresholds.cheonjakjihap) return CompatLabel.cheonjakjihap;
  if (total >= thresholds.sangkyeongyeobin) return CompatLabel.sangkyeongyeobin;
  if (total >= thresholds.mahapgaseong) return CompatLabel.mahapgaseong;
  return CompatLabel.hyeonggeuknanjo;
}
