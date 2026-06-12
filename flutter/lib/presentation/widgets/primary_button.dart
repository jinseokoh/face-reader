import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';

/// full-width 주 버튼 SSOT — DESIGN.md §3.9.
/// 토큰 잠금: 높이 48 · 검정 inverted (textPrimary bg + white fg) ·
/// radius 12 (AppRadius.md + 2) · label = AppText.subTitle (14 / w600).
/// 화면별 인라인 ElevatedButton 으로 폰트·패딩·radius 가 흩어지는 것을 차단한다
/// (LoginEntryButton 과 동일 규격 — 설정 탭 로그인/가입 버튼이 기준).
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
    final style = ElevatedButton.styleFrom(
      backgroundColor: AppColors.textPrimary,
      foregroundColor: Colors.white,
      // busy 는 "진행 중인 주 행동" — 검정 유지 + 흰 spinner. 진짜 비활성만 surface.
      disabledBackgroundColor: busy ? AppColors.textPrimary : AppColors.surface,
      disabledForegroundColor: AppColors.textHint,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
    );
    final enabled = onPressed != null && !busy;
    final labelColor = enabled ? Colors.white : AppColors.textHint;
    final child = busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
