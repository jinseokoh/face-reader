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
        return '정말 잘 맞는 사이';
      case CompatLabel.sangkyeongyeobin:
        return '조용히 깊어지는 사이';
      case CompatLabel.mahapgaseong:
        return '맞춰 가야 완성되는 사이';
      case CompatLabel.hyeonggeuknanjo:
        return '자주 부딪히는 사이';
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

/// aggregator 의 `_remapToUserScale` 가 MC p30/p60/p90 을 56/78/90 에 정확히
/// 꽂도록 설계되어 있어, 이 리터럴이 그대로 10/30/30/30 target 분포를 만든다.
/// UX 기준: 한국 사용자 직관에 맞춰 50/75/90 근처 짝수 경계.
const CompatLabelThresholds kCompatLabelThresholds = CompatLabelThresholds(
  cheonjakjihap: 90.0,
  sangkyeongyeobin: 78.0,
  mahapgaseong: 56.0,
);

CompatLabel classifyLabel(double total,
    {CompatLabelThresholds thresholds = kCompatLabelThresholds}) {
  if (total >= thresholds.cheonjakjihap) return CompatLabel.cheonjakjihap;
  if (total >= thresholds.sangkyeongyeobin) return CompatLabel.sangkyeongyeobin;
  if (total >= thresholds.mahapgaseong) return CompatLabel.mahapgaseong;
  return CompatLabel.hyeonggeuknanjo;
}
