import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';

/// §3.8 일러스트 빈 상태 — emotion 패밀리 84px + caption 한 줄.
/// 관상·궁합 탭의 fallback/빈 상태가 공유하는 단일 레시피 (§2.5 공용 승격).
/// 이미지 84×84 `BoxFit.contain` · caption(13)+textHint · 가운데 정렬 고정.
class EmotionEmptyState extends StatelessWidget {
  final String asset;
  final String message;

  const EmotionEmptyState({
    super.key,
    required this.asset,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(asset, width: 84, height: 84, fit: BoxFit.contain),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              style: AppText.caption.copyWith(color: AppColors.textHint),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
