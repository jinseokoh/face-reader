import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 잔액 chip — AppBar 타이틀 옆 "(코인 아이콘) N" 단일 source of truth.
/// 궁합·교감 탭이 공유한다 (§2.5 공용 승격). tap 시 설정 탭으로 보낸다
/// (코인 구매는 설정 탭의 PurchaseSheet 진입로).
class CoinChip extends StatelessWidget {
  final int coins;
  final VoidCallback onTap;
  const CoinChip({super.key, required this.coins, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        // vertical 6 = outlined pill(충전하기·관상보기 등)과 동일 높이.
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: 6,
        ),
        // stadium(999) — AppBar 의 outlined pill(관상보기 등)과 동일 형태.
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const FaIcon(
              FontAwesomeIcons.coins,
              size: 12,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xs),
            Text(
              '$coins',
              style: AppText.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
