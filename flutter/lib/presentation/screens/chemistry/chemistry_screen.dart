import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import '../../../core/theme.dart';
import '../../../data/services/team_service.dart';
import '../../../domain/models/team.dart';
import '../../providers/team_provider.dart';
import '../../providers/history_provider.dart';
import '../../widgets/age_range_pill.dart';
import '../../widgets/compact_snack_bar.dart';
import '../../widgets/emotion_empty_state.dart';
import '../../widgets/face_scan_pill.dart';
import '../../widgets/login_bottom_sheet.dart';
import '../../widgets/sort_selector.dart';
import '../../widgets/source_badge.dart';
import '../team/team_band.dart';
import '../team/team_create_page.dart';
import '../team/team_detail_screen.dart';
import '../team/team_reveal_screen.dart';

/// 케미 탭 = Chemistry Team 방 목록 브라우저.
/// 내부 2탭: 공개 그룹(목록에서 발견·참가) / 내 그룹(진행·완료).
class ChemistryScreen extends ConsumerStatefulWidget {
  const ChemistryScreen({super.key});

  @override
  ConsumerState<ChemistryScreen> createState() => _ChemistryScreenState();
}

/// 공개 그룹·내 그룹 공용 카드 본문 — 제목 / 유형·연령 pill / 참가자 슬롯.
/// 두 목록의 item 은 이 위젯 하나로 같은 결을 강제한다.
class _TeamCardBody extends StatelessWidget {
  final String title;
  final String ageLabel;
  final TeamRoomKind roomKind;
  final int maxPlayers;
  final bool isPrivate;

  /// 좌하단 참가자 미니 아바타 — 상태 무관 모든 카드 공통.
  final String teamId;

  /// 인원 미달 종료 방 — 제목을 hint 색으로 낮춰 살아 있는 방과 구분.
  final bool dimTitle;

  /// 종료(비모집) 방 — 유형 pill 을 흐린 gray 로 낮춘다. 진한 pill 은
  /// 항상 "참여 가능" 신호로만 쓰는 UX 규칙.
  final bool dimKind;
  const _TeamCardBody({
    required this.title,
    required this.ageLabel,
    required this.roomKind,
    required this.maxPlayers,
    required this.isPrivate,
    required this.teamId,
    this.dimTitle = false,
    this.dimKind = false,
  });

  @override
  Widget build(BuildContext context) {
    final kind = roomKind == TeamRoomKind.match ? '이성 케미' : '전체 케미';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dimTitle
              ? AppText.subTitle.copyWith(color: AppColors.textHint)
              : AppText.subTitle,
        ),
        const SizedBox(height: AppSpacing.xs),
        // 방 유형은 invert pill badge(연령 pill 과 동일 위젯) + 정원 텍스트.
        Row(
          children: [
            AgeRangePill(
              label: kind,
              invert: true,
              dim: dimKind,
              icons: roomKind == TeamRoomKind.match
                  ? const [FontAwesomeIcons.child, FontAwesomeIcons.childDress]
                  : const [
                      FontAwesomeIcons.childReaching,
                      FontAwesomeIcons.childReaching,
                    ],
            ),
            const SizedBox(width: AppSpacing.sm),
            AgeRangePill(label: ageLabel),
          ],
        ),
        // 아바타 줄은 위 pill 줄과 붙으면 답답해서 sm(8px)으로 벌린다.
        const SizedBox(height: AppSpacing.sm),
        Row(
          // tailwind items-center 상당 — 아바타·아이콘 수직 중앙 정렬.
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 좌하단 — 참가자 미니 아바타 + 빈자리 슬롯이 정원 표기를 겸한다
            // (궁합 확인 탭 pair 아바타의 1/2 스케일). 종료 표시는 corner ribbon.
            Expanded(
              child: _RosterAvatars(
                teamId: teamId,
                maxPlayers: maxPlayers,
                roomKind: roomKind,
                // 종료 방 — 빈자리를 그리면 참가 가능으로 오독되므로 생략.
                showEmptySlots: !dimTitle,
              ),
            ),
            // 우측 하단 상태 아이콘 — 비밀방 여부.
            FaIcon(
              isPrivate ? FontAwesomeIcons.lock : FontAwesomeIcons.lockOpen,
              size: 14,
              color: AppColors.textHint,
            ),
          ],
        ),
      ],
    );
  }
}

class _ChemistryScreenState extends ConsumerState<ChemistryScreen> {
  @override
  Widget build(BuildContext context) {
    final hasMyFace = ref.watch(historyProvider).any((r) => r.isMyFace);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('케미'),
          actions: [
            if (!hasMyFace)
              const FaceScanPill()
            else
              _CreatePill(onTap: _create),
            IconButton(
              icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
              tooltip: '케미 그룹에 대하여',
              onPressed: () => _showInfoDialog(context),
            ),
          ],
          // 내부 탭은 내 관상 등록 후에만 노출 — 궁합·관상 탭과 동일 규칙.
          bottom: hasMyFace
              ? const TabBar(
                  labelColor: AppColors.textPrimary,
                  unselectedLabelColor: AppColors.textHint,
                  indicatorColor: AppColors.textPrimary,
                  tabs: [
                    Tab(text: '공개 그룹'),
                    Tab(text: '내 그룹'),
                  ],
                )
              : null,
        ),
        body: !hasMyFace
            ? const EmotionEmptyState(
                asset: 'assets/images/emotion-shrug.png',
                message: '내 관상을 등록하면 케미 그룹에 참가할 수 있습니다',
              )
            : TabBarView(
                children: [
                  const _PublicTab(),
                  _MineTab(onOpen: _openMine),
                ],
              ),
      ),
    );
  }

  Future<void> _create() async {
    // 로그인 게이트 — 비로그인 owner_id null 이면 RLS 거부. login_bottom_sheet 패턴.
    if (!TeamService.instance.isLoggedIn) {
      final ok = await showLoginBottomSheet(context, ref);
      if (!ok || !mounted) return;
    }
    // 10대 차단 — UX §A.0. 연령 하한 20 이 스텝 중간이 아니라 문 앞에서 걸려야
    // 제목까지 고른 뒤 버려지는 낭비가 생기지 않는다.
    final myFace = ref
        .read(historyProvider)
        .where((r) => r.isMyFace)
        .firstOrNull;
    final decade = myFace == null ? null : 10 + myFace.ageGroup.index * 10;
    if (decade != null && decade < 20) {
      if (mounted) _showAgeGateDialog(context);
      return;
    }
    final team = await showTeamCreatePage(context);
    if (team == null || !mounted) return;
    ref.invalidate(myTeamsProvider);
    ref.invalidate(publicTeamsProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamDetailScreen(teamId: team.id),
      ),
    );
  }

  /// 내 그룹 = 전부 참가 중 — 비밀 그룹이어도 비밀번호 재확인 없이 진입
  /// (비밀번호는 입장 자격 검사, 멤버 재인증 아님). 생략 사유는 스낵바로.
  void _openMine(Team team) {
    if (!team.isPublic) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.info(message: '이미 참가한 그룹이라 비밀번호 없이 들어갑니다'),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => team.isRecruiting
            ? TeamDetailScreen(teamId: team.id)
            : TeamRevealScreen(teamId: team.id),
      ),
    );
  }

  void _showAgeGateDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('그룹 만들기 사용불가', style: AppText.modalTitle),
        content: const Text(
          '케미 그룹 만들기는 20세 이상부터 사용할 수 있습니다. '
          '내 관상 분석의 나이대가 10대로 확인되어 지금은 만들 수 없습니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인', style: AppText.subTitle),
          ),
        ],
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('케미 그룹', style: AppText.modalTitle),
        content: const SingleChildScrollView(
          child: Text(
            '6 ~ 12명 정원의 그룹을 만들어 온라인에서 만나는 '
            '다양한 사람들과의 서로 관상학적 케미가 좋은지 확인하는 기능입니다.\n\n'
            '케미 그룹은 누구나 만들 수 있고 그룹에 참여 정원이 다 차면 '
            '그 즉시 그룹내 참여자들간 관상으로 따져본 케미 결과표가 자동으로 발표됩니다.\n\n'
            '해당 그룹내에서 최고의 케미를 보인 베스트 매칭 한 쌍에게는 1:1 채팅 '
            '기회가 주어집니다. 물론, '
            '두 사람 모두 채팅을 원하는 경우에만 채팅방이 열리고, 한쪽이라도 '
            '거부하면 열리지 않습니다. 결과 발표이후 한 달이 지난 뒤에는 자동으로 삭제됩니다.\n\n'
            '공개 그룹은 언제든 참가할 수 있고, '
            '그룹 만들기 기능을 통해 원하는 그룹을 직접 만들 수도 있습니다. '
            '지인들끼리만 모이고 싶다면 그룹을 만들때 비밀번호를 설정하세요.\n\n'
            '공유하기 기능을 이용하면 카카오톡 등 원하는 채널을 통해 내가 만든 그룹에 초대할 수 '
            '있습니다.',
            style: AppText.body,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: AppText.subTitle),
          ),
        ],
      ),
    );
  }
}

/// AppBar 우측 pill — 기존 outlined stadium 레시피 (케미 그룹 시작 자리 승계).
class _CreatePill extends StatelessWidget {
  final VoidCallback onTap;
  const _CreatePill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: AppColors.textPrimary),
          ),
          child: Text(
            '그룹 만들기',
            style: AppText.caption.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

/// 종료 방 corner ribbon — 카드 우하단을 대각선으로 가로지르는 밴드.
/// 배경색만 있는 흰 밴드(border 없음) + danger 텍스트. 글자는 정원 표기
/// "1 / 8 명"과 동일한 caption 토큰, height 1.0 으로 밴드 정중앙 정렬.
class _ExpiredRibbon extends StatelessWidget {
  const _ExpiredRibbon();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -math.pi / 4,
      child: Container(
        width: 130,
        height: 20,
        alignment: Alignment.center,
        color: AppColors.danger,
        child: Text(
          '종료',
          style: AppText.caption.copyWith(color: Colors.white, height: 1.0),
        ),
      ),
    );
  }
}

class _MineCard extends ConsumerWidget {
  final Team team;
  final void Function(Team) onOpen;

  /// 베스트 케미 선정 — 초록 tint 배경 + 초록 1px border (내 관상 금색과
  /// 같은 문법). 채팅 개설 여부와 무관하게 발표에서 뽑히면 초록.
  final bool isBestPick;

  /// 나가리 — 결과 발표됐지만 내가 베스트 쌍이 아닌 방. 초록 강조와 같은
  /// 문법의 red 계통 (danger border + danger tint 배경).
  final bool isBusted;
  const _MineCard({
    required this.team,
    required this.onOpen,
    this.isBestPick = false,
    this.isBusted = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expired = team.status == TeamStatus.expired;
    // 마감(발표·종료 전부) — 제목을 hint 색으로 낮춰 모집중 방과 구분.
    final closed = !team.isRecruiting;
    return InkWell(
      onTap: () => onOpen(team),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        // 리스트 아이템 간격 — 관상·궁합 리스트와 동일한 md(12) 리듬.
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        // ribbon 이 카드 radius 밖으로 삐져나가지 않게 clip.
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isBestPick
              ? kBandGreen.withValues(alpha: 0.08)
              : isBusted
              ? AppColors.danger.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: isBestPick
                ? kBandGreen
                : isBusted
                ? AppColors.danger
                : AppColors.border,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: _TeamCardBody(
                title: team.title,
                ageLabel: team.ageRangeLabel,
                roomKind: team.roomKind,
                maxPlayers: team.maxPlayers,
                isPrivate: !team.isPublic,
                teamId: team.id,
                dimTitle: closed,
                dimKind: team.status != TeamStatus.recruiting,
              ),
            ),
            if (expired)
              // 밴드 중심이 우변·하변에서 같은 거리(20px)에 있어야 잘린
              // 구간 정중앙에 글자가 온다: 중심 x = 130/2 - 45 = 20,
              // 중심 y = 10 + 20/2 = 20.
              const Positioned(right: -45, bottom: 10, child: _ExpiredRibbon()),
          ],
        ),
      ),
    );
  }
}

enum _MineFilter {
  all('전체'),
  recruiting('모집중'),
  closed('종료');

  final String label;
  const _MineFilter(this.label);
}

class _MineTab extends ConsumerStatefulWidget {
  final void Function(Team) onOpen;
  const _MineTab({required this.onOpen});

  @override
  ConsumerState<_MineTab> createState() => _MineTabState();
}

class _MineTabState extends ConsumerState<_MineTab> {
  _MineFilter _filter = _MineFilter.all;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(myTeamsProvider);
    // 내가 베스트 쌍인 방 — 초록/red 판정 공용 소스. 로딩 중(null)엔
    // 판정을 유보해 완료 카드가 red 로 번쩍이지 않게 한다.
    final matchTeams = ref.watch(myMatchTeamsProvider).value;
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myTeamsProvider);
        ref.invalidate(openChatTeamsProvider);
        ref.invalidate(myMatchTeamsProvider);
      },
      color: AppColors.textPrimary,
      child: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.huge),
              child: Text(
                '목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotion-laugh.png',
                  message: '참가 중인 그룹이 없습니다',
                ),
              ],
            );
          }
          final filtered = [
            for (final b in list)
              if (switch (_filter) {
                _MineFilter.all => true,
                _MineFilter.recruiting => b.status == TeamStatus.recruiting,
                _MineFilter.closed => b.status != TeamStatus.recruiting,
              })
                b,
          ];
          // 필터 selector 는 스크롤 밖 고정(sticky) 바 — 스크롤 중에도 항상
          // 보인다 (관상·궁합 탭과 동일 패턴). 빈 탭엔 노출하지 않는다.
          return Column(
            children: [
              Padding(
                // selector 위 lg(16)/아래 md(12) — 관상 탭 정렬 헤더와 동일 리듬.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: SortSelector<_MineFilter>(
                  tooltip: '필터',
                  value: _filter,
                  values: _MineFilter.values,
                  labelOf: (f) => f.label,
                  onChanged: (f) => setState(() => _filter = f),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) => _MineCard(
                    team: filtered[i],
                    onOpen: widget.onOpen,
                    isBestPick:
                        matchTeams != null &&
                        filtered[i].status == TeamStatus.completed &&
                        matchTeams.contains(filtered[i].id),
                    isBusted:
                        matchTeams != null &&
                        filtered[i].status == TeamStatus.completed &&
                        !matchTeams.contains(filtered[i].id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 비밀 그룹 문 앞 비밀번호 입력 dialog — 상세 참가 폼의 PIN 입력과 동일 스펙
/// (숫자 4자리). 확인 시 check_team_password RPC 로 서버 검증하고, 일치할
/// 때만 입력값을 pop 으로 돌려준다. 불일치·통신 실패는 dialog 안 errorText.
class _PinDialog extends StatefulWidget {
  final String teamId;
  const _PinDialog({required this.teamId});

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _ctrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final ready = _ctrl.text.trim().length == 4 && !_busy;
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      title: const Text('비밀 그룹', style: AppText.modalTitle),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: TextInputType.number,
        maxLength: 4,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: AppText.body.copyWith(color: AppColors.textPrimary),
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(hintText: '비밀번호 4자리', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: Text(
            '취소',
            style: AppText.body.copyWith(color: AppColors.textHint),
          ),
        ),
        TextButton(
          onPressed: ready ? _submit : null,
          child: Text(
            '확인',
            style: AppText.subTitle.copyWith(
              color: ready ? AppColors.textPrimary : AppColors.textHint,
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _ctrl.text.trim();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final ok = await TeamService.instance.checkPassword(
        widget.teamId,
        pin,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context, pin);
        return;
      }
      setState(() {
        _busy = false;
        _error = TeamJoinError.badPassword.labelKo;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = TeamJoinError.unknown.labelKo;
      });
    }
  }
}

class _PublicCard extends StatefulWidget {
  final PublicTeam team;
  final bool isOwner;

  /// 내가 이미 참가 중인 그룹 — 비밀번호는 입장 자격 검사이지 멤버 재인증이
  /// 아니므로 (오픈채팅 비밀방과 동일 모델) dialog 없이 바로 진입한다.
  final bool isJoined;
  const _PublicCard({
    required this.team,
    this.isOwner = false,
    this.isJoined = false,
  });

  @override
  State<_PublicCard> createState() => _PublicCardState();
}

class _PublicCardState extends State<_PublicCard> {
  PublicTeam get team => widget.team;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _open,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        // 리스트 아이템 간격 — 관상·궁합 리스트와 동일한 md(12) 리듬.
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.border),
        ),
        child: _TeamCardBody(
          title: team.title,
          ageLabel: team.ageRangeLabel,
          roomKind: team.roomKind,
          maxPlayers: team.maxPlayers,
          isPrivate: team.isPrivate,
          teamId: team.id,
        ),
      ),
    );
  }

  /// 참가 여부 분기는 상세 페이지가 화면 안에서 처리 — 탭은 진입만.
  /// 미참가 비밀 그룹은 문 앞 dialog 가 check_team_password RPC 로 검증한
  /// 비밀번호를 받아야만 상세로 진입하고, 그 값을 참가 폼에 채워 넘긴다
  /// (조인 시 join_team 이 같은 비교를 다시 한다).
  Future<void> _open() async {
    String? pin;
    if (team.isPrivate && !widget.isJoined) {
      pin = await showDialog<String>(
        context: context,
        builder: (_) => _PinDialog(teamId: team.id),
      );
      if (pin == null || !mounted) return;
    }
    // 참가 중인 비밀 그룹 — dialog 생략 사유를 스낵바로 알린다.
    if (team.isPrivate && widget.isJoined) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.info(message: '이미 참가한 그룹이라 비밀번호 없이 들어갑니다'),
      );
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TeamDetailScreen(teamId: team.id, initialPin: pin),
      ),
    );
  }
}

class _PublicTab extends ConsumerStatefulWidget {
  const _PublicTab();

  @override
  ConsumerState<_PublicTab> createState() => _PublicTabState();
}

class _PublicTabState extends ConsumerState<_PublicTab> {
  _SortOrder _order = _SortOrder.newest;

  @override
  Widget build(BuildContext context) {
    final teams = ref.watch(publicTeamsProvider);
    // 공개 목록엔 방장 정보가 없다 (public_teams 화이트리스트) — 내 그룹
    // 목록과 대조해 내가 방장인 방·이미 참가한 방을 식별한다.
    final myUid = TeamService.instance.myUid;
    final myTeams = ref.watch(myTeamsProvider).value ?? const <Team>[];
    final mineIds = {
      for (final b in myTeams)
        if (b.ownerId != null && b.ownerId == myUid) b.id,
    };
    final joinedIds = {for (final b in myTeams) b.id};
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(publicTeamsProvider),
      color: AppColors.textPrimary,
      child: teams.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.huge),
              child: Text(
                '목록을 불러오지 못했습니다\n당겨서 새로고침',
                style: AppText.caption,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        data: (list) {
          if (list.isEmpty) {
            return ListView(
              children: const [
                SizedBox(height: 120),
                EmotionEmptyState(
                  asset: 'assets/images/emotion-frown.png',
                  message: '모집 중인 공개 그룹이 없습니다',
                ),
              ],
            );
          }
          final sorted = [...list]
            ..sort(
              (a, b) => _order == _SortOrder.newest
                  ? b.createdAt.compareTo(a.createdAt)
                  : a.createdAt.compareTo(b.createdAt),
            );
          // 정렬 selector 는 스크롤 밖 고정(sticky) 바 — 스크롤 중에도 항상
          // 보인다 (관상·궁합 탭과 동일 패턴). 빈 탭엔 노출하지 않는다.
          return Column(
            children: [
              Padding(
                // selector 위 lg(16)/아래 md(12) — 관상 탭 정렬 헤더와 동일 리듬.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: SortSelector<_SortOrder>(
                  value: _order,
                  values: _SortOrder.values,
                  labelOf: (o) => o.label,
                  onChanged: (o) => setState(() => _order = o),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: sorted.length,
                  itemBuilder: (ctx, i) => _PublicCard(
                    team: sorted[i],
                    isOwner: mineIds.contains(sorted[i].id),
                    isJoined: joinedIds.contains(sorted[i].id),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 카드 좌하단 참가자 아바타 — 궁합 확인 탭 pair 아바타(42 thumb +
/// 2 ring, step 32)의 정확히 1/2 스케일(21 + 1, step 16) overlap 배치.
/// 채워진 아바타 뒤에 빈자리 슬롯을 이어 붙여 정원 표기를 겸한다 —
/// 이성 케미는 남/여 잔여석을 각 성별 아이콘으로, 전체 케미는 user 아이콘.
class _RosterAvatars extends ConsumerWidget {
  // 42(md) 리스트 표준의 정확한 1/2 스케일 — 흰 ring 없이 thumb 만.
  static const _kThumb = 21.0;
  static const _kBox = _kThumb;
  static const _kStep = 16.0;
  final String teamId;
  final int maxPlayers;

  final TeamRoomKind roomKind;
  final bool showEmptySlots;
  const _RosterAvatars({
    required this.teamId,
    required this.maxPlayers,
    required this.roomKind,
    required this.showEmptySlots,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avatars =
        ref.watch(teamRosterAvatarsProvider(teamId)).value ?? const [];
    if (avatars.isEmpty) return const SizedBox(height: _kBox);
    // 빈자리 슬롯 svg 목록 — 이성 케미는 남녀 반반 정원이라 성별별 잔여석,
    // 전체 케미는 성별 무관 잔여석.
    final emptySvgs = <String>[];
    if (showEmptySlots) {
      if (roomKind == TeamRoomKind.match) {
        final half = maxPlayers ~/ 2;
        final males = avatars.where((a) => a.gender == 'male').length;
        final females = avatars.length - males;
        emptySvgs.addAll([
          for (var i = males; i < half; i++) 'assets/svgs/male.svg',
          for (var i = females; i < half; i++) 'assets/svgs/female.svg',
        ]);
      } else {
        emptySvgs.addAll([
          for (var i = avatars.length; i < maxPlayers; i++)
            'assets/svgs/user.svg',
        ]);
      }
    }
    final total = avatars.length + emptySvgs.length;
    // 정원 최대 12명까지 자르지 않고 전부 — 좁으면 FittedBox 가 줄인다.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: SizedBox(
        width: _kBox + _kStep * (total - 1),
        height: _kBox,
        child: Stack(
          children: [
            for (var i = 0; i < avatars.length; i++)
              Positioned(left: _kStep * i, child: _thumb(avatars[i])),
            for (var i = 0; i < emptySvgs.length; i++)
              Positioned(
                left: _kStep * (avatars.length + i),
                child: _emptySlot(emptySvgs[i]),
              ),
          ],
        ),
      ),
    );
  }

  /// 빈자리 슬롯 — 흰 원 + hint 색 svg 실루엣. border 는 기본색이라
  /// 채워진 자리와 확연히 구분된다.
  Widget _emptySlot(String asset) {
    return Container(
      width: _kThumb,
      height: _kThumb,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: AppColors.border),
      ),
      child: SvgPicture.asset(
        asset,
        height: 11,
        colorFilter: const ColorFilter.mode(
          AppColors.textHint,
          BlendMode.srcIn,
        ),
      ),
    );
  }

  Widget _genderIcon(String gender) => Center(
    child: SvgPicture.asset(
      gender == 'male' ? 'assets/svgs/male.svg' : 'assets/svgs/female.svg',
      height: 11,
      colorFilter: const ColorFilter.mode(
        AppColors.textHint,
        BlendMode.srcIn,
      ),
    ),
  );

  Widget _thumb(RosterAvatar a) {
    final showPhoto = a.url != null;
    return Container(
      width: _kThumb,
      height: _kThumb,
      clipBehavior: Clip.antiAlias,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.surface,
      ),
      // border 는 foreground — 이미지가 테두리 안쪽을 덮지 않게.
      // 사진일 때만 촬영 경로 border 규칙 — 아이콘 fallback 은 기본 border.
      foregroundDecoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: showPhoto ? sourceBorderColor(a.source) : AppColors.border,
        ),
      ),
      child: showPhoto
          ? CachedNetworkImage(
              imageUrl: a.url!,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(color: AppColors.surface),
              errorWidget: (_, _, _) => _genderIcon(a.gender),
            )
          : _genderIcon(a.gender),
    );
  }
}

enum _SortOrder {
  newest('최신순'),
  oldest('오래된순');

  final String label;
  const _SortOrder(this.label);
}
