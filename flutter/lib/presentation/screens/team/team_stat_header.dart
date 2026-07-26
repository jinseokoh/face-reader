import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../domain/models/team.dart';
import '../../widgets/age_range_pill.dart';

/// 케미 그룹 방 stat 카드 — 제목 / 유형·연령 pill + 조회수 / 생성·마감 메타.
/// 모집중(상세)·마감(결과판)·인원미달 종료 어느 상태든 최상단에 동일하게
/// 노출하는 공용 위젯. 마감 시각은 cron SSOT (모집 48h · closed_at) 기준 —
/// 모집중이면 미래(마감: 약 1일 후), 종료면 과거(마감: 2시간 전) 상대 표기.
class TeamStatHeader extends StatelessWidget {
  final Team team;

  /// 상태별 추가 줄 (미참가 이성방의 남은 자리 등) — pill 줄과 메타 줄 사이.
  final Widget? extra;
  const TeamStatHeader({super.key, required this.team, this.extra});

  @override
  Widget build(BuildContext context) {
    final hint = AppText.caption.copyWith(color: AppColors.textHint);
    final deadline =
        team.closedAt?.toLocal() ??
        team.createdAt.add(const Duration(hours: 48));
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            team.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppText.subTitle,
          ),
          const SizedBox(height: AppSpacing.xs),
          // 목록 카드(_TeamCardBody)와 동일 pill 문법 + 우측 끝 조회수.
          // 진한 반전 pill 은 "참여 가능" 신호 — 비모집 상태는 outlined 강등.
          Row(
            children: [
              AgeRangePill(
                label: team.roomKind == TeamRoomKind.match
                    ? '이성 케미'
                    : '전체 케미',
                invert: true,
                dim: !team.isRecruiting,
                icons: team.roomKind == TeamRoomKind.match
                    ? const [
                        FontAwesomeIcons.child,
                        FontAwesomeIcons.childDress,
                      ]
                    : const [
                        FontAwesomeIcons.childReaching,
                        FontAwesomeIcons.childReaching,
                      ],
              ),
              const SizedBox(width: AppSpacing.sm),
              AgeRangePill(label: team.ageRangeLabel),
              const Spacer(),
              FaIcon(
                FontAwesomeIcons.eye,
                size: 12,
                color: AppColors.textHint,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text('${team.views}회', style: hint),
            ],
          ),
          if (extra != null) ...[
            const SizedBox(height: AppSpacing.sm),
            extra!,
          ],
          const SizedBox(height: AppSpacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '생성: ${timeago.format(team.createdAt, locale: 'ko')}',
                style: hint,
              ),
              Text(
                '마감: ${timeago.format(deadline, locale: 'ko', allowFromNow: true)}',
                style: hint,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
