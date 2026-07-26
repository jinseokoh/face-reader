import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 매칭 연령대 outlined pill — SourceBadge 의 pill 레시피와 동일
/// (border 만, radius sm). 상세 페이지 헤더·공개 매칭 카드 우측 상단 공용.
///
/// [invert] true 면 반전 변형(accent gray 배경 + 흰 글자) — 방 유형 badge 용.
/// [dim] true 면 invert 를 무시하고 기본 outlined 모양(흰 배경 + border +
/// hint 글자)으로 낮춘다 — 종료된 방 카드에서 연령 pill 과 동일 외형.
/// 진한 반전 pill 은 항상 "참여 가능" 신호로만 쓰는 UX 규칙.
class AgeRangePill extends StatelessWidget {
  final String label;
  final bool invert;
  final bool dim;

  /// 라벨 앞 아이콘들 — 방 유형 badge 용 (이성 케미 child+childDress /
  /// 전체 케미 childReaching×2). 텍스트와 같은 색 = pill 단일톤 유지.
  final List<FaIconData> icons;
  const AgeRangePill({
    super.key,
    required this.label,
    this.invert = false,
    this.dim = false,
    this.icons = const [],
  });

  @override
  Widget build(BuildContext context) {
    final filled = invert && !dim;
    final fgColor = filled ? Colors.white : AppColors.textHint;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        // 기본은 흰 배경 고정 — 카드 배경(surface/background)과 무관하게 동일 외형.
        color: filled ? AppColors.accent : Colors.white,
        border: Border.all(
          color: filled ? AppColors.accent : AppColors.border,
        ),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 아이콘끼리는 1px overlap — 나란히 두면 커플이 아니라 남남으로
          // 보인다. translate 는 layout 폭을 안 줄이므로 텍스트 앞 여백에서
          // 겹친 만큼 되돌려 시각 간격을 xs 로 유지한다.
          for (var i = 0; i < icons.length; i++)
            Transform.translate(
              offset: Offset(-1.0 * i, 0),
              child: FaIcon(icons[i], size: 10, color: fgColor),
            ),
          if (icons.isNotEmpty)
            SizedBox(width: AppSpacing.xs - 1.0 * (icons.length - 1)),
          Text(label, style: AppText.hint.copyWith(color: fgColor)),
        ],
      ),
    );
  }
}
