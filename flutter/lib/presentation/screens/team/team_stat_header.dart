import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../domain/models/team.dart';

// 화면-국지 팔레트 — 관상·궁합 상세 hero 박스(_Palette/_CompatPalette)와
// 동일 hex (DESIGN.md §2.4 file-local 격리, 신규 색 아님).
const _kDarkBrown = Color(0xFF5C4033);
const _kWarmBrown = Color(0xFF7B5B3A);
const _kSand = Color(0xFFBFA67A);

// 관상·궁합 상세의 강점(그린) chip 과 동일 hex — 연령대 tag 공용 레시피.
const _kGreenBg = Color(0xFFE0EBDA);
const _kGreenFg = Color(0xFF2C5A36);
const _kGreenBorder = Color(0xFF6B9F70);

/// hero 박스 안에 함께 그려지는 위젯(참가자 그리드 등)이 쓰는 sand 액센트 —
/// 상세 화면과 공유 (team_band.kBandGreen 과 같은 export 문법).
const kTeamHeroSand = _kSand;

/// 케미 그룹 방 stat 카드 — 좌상단 yyyy.mm.dd(생성일) + 마감 설명 한 줄,
/// 그 아래 관상·궁합 상세 hero 와 동일한 다크 그라데이션 박스(제목 / 유형·
/// 연령 pill + 조회수). 모집중(상세)·마감(결과판)·인원미달 어느 상태든
/// 최상단에 동일하게 노출하는 공용 위젯.
///
/// 마감 시각은 cron SSOT (모집 7일 · closed_at) 기준 — 모집중이면 미래
/// (지금부터 13시간 후 마감), 종료면 과거(2시간 전 마감) 상대 표기.
/// 마감은 살아있는 정보라 날짜 옆 괄호 설명문으로 병기하고, 박스 안
/// 생성·마감 중복 표기는 두지 않는다 (2026-07-30).
class TeamStatHeader extends StatelessWidget {
  static Widget _greenChip(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: _kGreenBg,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: _kGreenBorder),
    ),
    child: Text(
      label,
      style: AppText.caption.copyWith(
        color: _kGreenFg,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
    ),
  );

  final Team team;

  /// hero 박스 하단 섹션 (상세 페이지의 참가자 슬롯 그리드) — pill 줄
  /// 아래 반투명 구분선으로 나뉘어 들어간다. 다크 박스 위에 놓이므로
  /// 밝은 글자색을 쓸 것.
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
        team.createdAt.add(const Duration(days: 7));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 좌측 날짜(관상·궁합 상세와 동일 포맷 yyyy.mm.dd) ↔ 우측 마감 —
        // 같은 caption + textHint 토큰. '지금부터' 접두어는 '후'에 이미
        // 함축돼 있어 제거 (timeago ko fromNow 기본 접두어).
        Row(
          children: [
            Text(
              dateStr,
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
            const Spacer(),
            Text(
              '${timeago.format(deadline, locale: 'ko', allowFromNow: true).replaceFirst('지금부터 ', '')} 마감',
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
          ],
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
              // 궁합 상세 hero 의 '궁합도 과학이다' 와 동일 레시피
              // (hint + sand + w700 + letterSpacing 1).
              Text(
                '케미도 과학이다',
                style: AppText.hint.copyWith(
                  color: _kSand,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 제목은 브랜드 세리프(appBarTitle 토큰 기반) — 16 으로 낮추고
              // 최대 2줄. 긴 그룹 제목이 한 줄 말줄임으로 잘리지 않게.
              Text(
                team.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppText.appBarTitle.copyWith(
                  color: Colors.white,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // 연령 + 정원 그린 chip — 관상·궁합 hero 의 그린 chip 과 동일
              // 디자인 (sage 배경 + 초록 border + radius 20). 방 유형 pill 과
              // 조회수는 목록 카드가 이미 전달한 정보라 제거 (2026-07-30).
              Row(
                children: [
                  _greenChip(team.ageRangeLabel),
                  const SizedBox(width: AppSpacing.sm),
                  _greenChip('${team.maxPlayers}명 그룹'),
                ],
              ),
              if (extra != null) ...[
                const SizedBox(height: AppSpacing.lg),
                // 반투명 구분선 — 박스 내부를 "제목·pill ─ 참가자" 2단으로
                // 구조화 (궁합 hero 의 인물 섹션과 같은 위계).
                Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.18),
                ),
                const SizedBox(height: AppSpacing.lg),
                extra!,
              ],
            ],
          ),
        ),
      ],
    );
  }
}
