import 'package:flutter/material.dart';

import '../../../core/theme.dart';

// 기존 케미 4밴드 색 승계 (신규 색상 도입 금지).
const _kBandGreen = Color(0xFF2E7D32);

/// 밴드 밖 강조 재사용 — 채팅방 열린 매칭 카드 배경·테두리 (신규 색 금지,
/// 천생연분 초록 승계).
const kBandGreen = _kBandGreen;
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

  String get bandLabel => switch (this) {
    0 => '천생연분',
    1 => '금슬화합',
    2 => '상부상조',
    _ => '형극난조',
  };
}

/// 밴드 색 점 — 앱 전역 단일 표기 (매트릭스·순위·범례·쌍 상세 시트 공용).
/// 이모지(🟢…) 표기 금지: OS 글리프 편차 + 색 토큰 이탈.
/// [score] 를 주면 점 가운데 흰색 hint 폰트로 점수를 얹는다 (28px 권장).
class BandDot extends StatelessWidget {
  final int band;
  final double size;
  final int? score;
  const BandDot(this.band, {super.key, this.size = 14, this.score});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: band.bandColor),
      child: score == null
          ? null
          : Center(
              child: Text(
                '$score',
                style: AppText.hint.copyWith(color: Colors.white),
              ),
            ),
    );
  }
}
