import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:flutter/material.dart';

// 밴드 색상 스케일 — best→worst. matrix 셀 색깔 닷 전용 (화면-국지 상수).
const _kBandGreen = Color(0xFF2E7D32); // 환상 케미
const _kBandBlue = Color(0xFF1565C0); // 시너지
const _kBandOrange = Color(0xFFEF6C00); // 무난
const _kBandRed = Color(0xFFD32F2F); // 보완 조합

/// 교감도의 4단 밴드 표기 — PIVOT A4.
/// 엔진의 4-tier CompatLabel(임계값 포함)을 그대로 쓰고, 표기만 팀 맥락의
/// 현대 한국어로 바꾼다 (한자 단독 라벨 금지 · 하위 밴드는 "보완 조합" 프레임).
/// UI 레이어 전용 — shared 엔진에는 손대지 않는다.
extension TeamBand on CompatLabel {
  /// 밴드 색상 — matrix 셀 색깔 닷. 녹색(최상)→파랑→오렌지→빨강(최하).
  Color get bandColor {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return _kBandGreen;
      case CompatLabel.geumseulsanghwa:
        return _kBandBlue;
      case CompatLabel.mahapgaseong:
        return _kBandOrange;
      case CompatLabel.hyeonggeuknanjo:
        return _kBandRed;
    }
  }

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
        return '천작지합';
      case CompatLabel.geumseulsanghwa:
        return '금슬상화';
      case CompatLabel.mahapgaseong:
        return '마합가성';
      case CompatLabel.hyeonggeuknanjo:
        return '형극난조';
    }
  }
}
