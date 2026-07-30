import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../domain/models/team.dart';
import '../../widgets/age_range_pill.dart';

// 화면-국지 팔레트 — 관상·궁합 상세 hero 박스(_Palette/_CompatPalette)와
// 동일 hex (DESIGN.md §2.4 file-local 격리, 신규 색 아님).
const _kDarkBrown = Color(0xFF5C4033);
const _kWarmBrown = Color(0xFF7B5B3A);
const _kSand = Color(0xFFBFA67A);

/// 케미 그룹 방 stat 카드 — 좌상단 yyyy.mm.dd(생성일) + 마감 설명 한 줄,
/// 그 아래 관상·궁합 상세 hero 와 동일한 다크 그라데이션 박스(제목 / 유형·
/// 연령 pill + 조회수). 모집중(상세)·마감(결과판)·인원미달 어느 상태든
/// 최상단에 동일하게 노출하는 공용 위젯.
///
/// 마감 시각은 cron SSOT (모집 48h · closed_at) 기준 — 모집중이면 미래
/// (지금부터 13시간 후 마감), 종료면 과거(2시간 전 마감) 상대 표기.
/// 마감은 살아있는 정보라 날짜 옆 괄호 설명문으로 병기하고, 박스 안
/// 생성·마감 중복 표기는 두지 않는다 (2026-07-30).
class TeamStatHeader extends StatelessWidget {
  final Team team;

  /// 상태별 추가 줄 (미참가 이성방의 남은 자리 등) — pill 줄 아래.
  /// 다크 박스 위에 놓이므로 밝은 글자색을 쓸 것.
  final Widget? extra;
  const TeamStatHeader({super.key, required this.team, this.extra});

  @override
  Widget build(BuildContext context) {
    final created = team.createdAt.toLocal();
    final dateStr =
        '${created.year}.'
        '${created.month.toString().padLeft(2, '0')}.'
        '${created.day.toString().padLeft(2, '0')}';
    final deadline =
        team.closedAt?.toLocal() ??
        team.createdAt.add(const Duration(hours: 48));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌상단 날짜 — 관상·궁합 상세와 동일 포맷(yyyy.mm.dd)·토큰
        // (caption + textHint).
        Text(
          '$dateStr '
          '(${timeago.format(deadline, locale: 'ko', allowFromNow: true)} 마감)',
          style: AppText.caption.copyWith(color: AppColors.textHint),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_kDarkBrown, _kWarmBrown],
            ),
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                team.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.subTitle.copyWith(color: Colors.white),
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
                  const FaIcon(FontAwesomeIcons.eye, size: 12, color: _kSand),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${team.views}회',
                    style: AppText.caption.copyWith(color: _kSand),
                  ),
                ],
              ),
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.sm),
                extra!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
