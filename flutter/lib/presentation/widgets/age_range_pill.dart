import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';

/// 배틀 연령대 outlined pill — SourceBadge 의 pill 레시피와 동일
/// (border 만, radius sm). 로비 헤더·공개 배틀 카드·조인 화면 우측 상단 공용.
class AgeRangePill extends StatelessWidget {
  final String label;
  const AgeRangePill({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppText.hint.copyWith(color: AppColors.textHint),
      ),
    );
  }
}
