import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';

/// 매칭 연령대 outlined pill — SourceBadge 의 pill 레시피와 동일
/// (border 만, radius sm). 상세 페이지 헤더·공개 매칭 카드 우측 상단 공용.
///
/// [invert] true 면 반전 변형(accent gray 배경 + 흰 글자) — 방 유형 badge 용.
class AgeRangePill extends StatelessWidget {
  final String label;
  final bool invert;
  const AgeRangePill({super.key, required this.label, this.invert = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        // 기본은 흰 배경 고정 — 카드 배경(surface/background)과 무관하게 동일 외형.
        color: invert ? AppColors.accent : Colors.white,
        border: Border.all(
          color: invert ? AppColors.accent : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppText.hint.copyWith(
          color: invert ? Colors.white : AppColors.textHint,
        ),
      ),
    );
  }
}
