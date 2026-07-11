import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';

/// full-width 주 버튼 SSOT — DESIGN.md §3.9.
/// 토큰 잠금: 높이 48 · 흰색 배경 + 1px textPrimary border (2026-07-10 전면
/// 전환 — 검정 inverted CTA 폐기) · radius 12 (AppRadius.md + 2) ·
/// label = AppText.subTitle (14 / w600).
/// 화면별 인라인 ElevatedButton 으로 폰트·패딩·radius 가 흩어지는 것을 차단한다.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final FaIconData? icon;
  // true 면 label 대신 spinner (info_confirm 분석 진행 등).
  final bool busy;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      disabledBackgroundColor: AppColors.background,
      disabledForegroundColor: AppColors.textHint,
      elevation: 0,
      // busy 는 "진행 중인 주 행동" — 검정 테두리 유지 + 어두운 spinner.
      // 진짜 비활성만 border 톤 테두리.
      side: BorderSide(
        color: enabled || busy ? AppColors.textPrimary : AppColors.border,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
    );
    final labelColor = enabled ? AppColors.textPrimary : AppColors.textHint;
    final child = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor:
                  AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
            ),
          )
        : Text(label, style: AppText.subTitle.copyWith(color: labelColor));

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: icon == null || busy
          ? ElevatedButton(
              onPressed: busy ? null : onPressed,
              style: style,
              child: child,
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              style: style,
              icon: FaIcon(icon, size: 16),
              label: child,
            ),
    );
  }
}

/// full-width 보조 버튼 — 주 버튼과 동일 규격의 outlined 검정 패턴
/// (두 번째 강조는 outlined, DESIGN 원칙).
class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textHint,
          side: BorderSide(
            color: enabled ? AppColors.textPrimary : AppColors.border,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md + 2),
          ),
        ),
        child: Text(
          label,
          style: AppText.subTitle.copyWith(
            color: enabled ? AppColors.textPrimary : AppColors.textHint,
          ),
        ),
      ),
    );
  }
}
