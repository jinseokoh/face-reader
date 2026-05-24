import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/theme.dart';

/// Empty-state placeholder — 모든 빈 상태 (분석 기록 없음 / 등록된 관상 없음 등)
/// 는 본 위젯 하나로 통일.
///
/// 색·폰트·spacing 은 [AppColors]·[AppText]·[AppSpacing] 토큰에 잠겨 있어
/// 호출부에서 override 불가. 스펙은 `docs/DESIGN.md §3.8 Empty state` 참고.
class EmptyStatePlaceholder extends StatelessWidget {
  const EmptyStatePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    this.detail,
  });

  /// FontAwesome icon. 56px / [AppColors.border] 로 렌더된다.
  final IconData icon;

  /// 1차 메시지. [AppText.sectionTitle] w400 + [AppColors.textHint].
  final String title;

  /// 보조 설명 (optional). [AppText.hint] = 12 w400 textHint.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FaIcon(icon, color: AppColors.border, size: 56),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.sectionTitle.copyWith(
                fontWeight: FontWeight.w400,
                color: AppColors.textHint,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: AppText.hint,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
