import 'package:face_engine/domain/services/compat/compat_label.dart';

/// 교감 분석 지도의 4단 밴드 표기 — PIVOT A4.
/// 엔진의 4-tier CompatLabel(임계값 포함)을 그대로 쓰고, 표기만 팀 맥락의
/// 현대 한국어로 바꾼다 (한자 단독 라벨 금지 · 하위 밴드는 "보완 조합" 프레임).
/// UI 레이어 전용 — shared 엔진에는 손대지 않는다.
extension TeamBand on CompatLabel {
  String get bandEmoji {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '💞';
      case CompatLabel.geumseulsanghwa:
        return '🔥';
      case CompatLabel.mahapgaseong:
        return '🤝';
      case CompatLabel.hyeonggeuknanjo:
        return '🌧';
    }
  }

  String get bandLabel {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '환상 케미';
      case CompatLabel.geumseulsanghwa:
        return '시너지';
      case CompatLabel.mahapgaseong:
        return '무난';
      case CompatLabel.hyeonggeuknanjo:
        return '보완 조합';
    }
  }
}
