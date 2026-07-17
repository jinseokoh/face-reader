import 'package:flutter/material.dart';

// 기존 케미 4밴드 색 승계 (신규 색상 도입 금지).
const _kBandGreen = Color(0xFF2E7D32);
const _kBandBlue = Color(0xFF1565C0);
const _kBandOrange = Color(0xFFEF6C00);
const _kBandRed = Color(0xFFD32F2F);

/// result_payload 의 band 코드(0~3 = CompatLabel.index) 표기.
extension BattleBand on int {
  Color get bandColor => switch (this) {
        0 => _kBandGreen,
        1 => _kBandBlue,
        2 => _kBandOrange,
        _ => _kBandRed,
      };

  String get bandEmoji => switch (this) {
        0 => '🟢',
        1 => '🔵',
        2 => '🟠',
        _ => '🔴',
      };

  String get bandLabel => switch (this) {
        0 => '천생연분',
        1 => '금슬화합',
        2 => '상부상조',
        _ => '형극난조',
      };
}
