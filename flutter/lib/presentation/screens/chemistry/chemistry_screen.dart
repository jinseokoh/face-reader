import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/compat/compat_label.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/domain/services/team_matrix.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/screens/team/team_band.dart';
import 'package:facely/presentation/screens/team/team_create_page.dart';
import 'package:facely/presentation/screens/team/team_room_screen.dart';
import 'package:facely/presentation/widgets/coin_chip.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';


class ChemistryScreen extends ConsumerStatefulWidget {
  const ChemistryScreen({super.key});

  @override
  ConsumerState<ChemistryScreen> createState() => _ChemistryScreenState();
}

class _ChemistryScreenState extends ConsumerState<ChemistryScreen>
    with SingleTickerProviderStateMixin {
  // 탭 수는 2 고정 (내가 만든 / 초대받은) — 동적 재생성 불필요.
  late final TabController _tabController =
      TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 720;
    final topGap = compact ? AppSpacing.sm : AppSpacing.xl;
    final bottomGap = compact ? AppSpacing.lg : AppSpacing.huge;

    // 팀 카드의 alias·썸네일이 history 변화에 반응하도록 watch 유지.
    final history = ref.watch(historyProvider);
    // 관상·궁합 탭과 동일 규칙 — 내부 탭은 내 관상 등록 후에만 나타난다.
    final hasMyFace = history.any((r) => r.isMyFace);
    final auth = ref.watch(authProvider);
    final teams = ref.watch(teamsProvider);
    // 소유는 생성 시점에 고정된 ownedByMe 로 판정 — 변경 가능한 내 관상 id 와
    // 비교하지 않는다(재등록해도 내 그룹이 초대받은 그룹으로 새지 않게).
    // P3 원격 합류 방은 ownedByMe=false 로 들어와 자동으로 invited 에 분류된다.
    final owned = <TeamRoom>[];
    final invited = <TeamRoom>[];
    for (final t in teams) {
      (t.ownedByMe ? owned : invited).add(t);
    }

    return Scaffold(
      backgroundColor: Colors.white,
      // 관상 탭과 동일 규격 AppBar — 타이틀은 테마의 SongMyung appBarTitle.
      // 탭 라벨(교감)과 동일 표기 — 탭≡AppBar 타이틀 규칙.
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('케미'),
            // 궁합 탭과 동일한 잔액 chip (공용 CoinChip) — tap = 설정 탭.
            if (auth != null) ...[
              const SizedBox(width: AppSpacing.md),
              CoinChip(
                coins: auth.coins,
                onTap: () =>
                    ref.read(selectedTabProvider.notifier).selectTab(3),
              ),
            ],
          ],
        ),
        // 다른 사람 관상보기 pill 은 관상 탭 AppBar 로 이관 (2026-07-10).
        actions: [
          // [케미 그룹 시작] — 궁합 [상대방 관상 추가] pill 과 동일한
          // outlined stadium 레시피 (§2.5). 내 관상 등록 후에만 노출.
          if (hasMyFace)
            Center(
              child: GestureDetector(
                onTap: _createTeam,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.textPrimary),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '케미 그룹 시작',
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          // 궁합 탭과 동일 형태의 info 버튼 + 다이얼로그.
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
            tooltip: '그룹 케미에 대하여',
            onPressed: () => _showInfoDialog(context),
          ),
        ],
        // 관상 탭과 동일 속성의 TabBar (labelColor·indicator·라벨 개수 표기).
        bottom: hasMyFace
            ? TabBar(
                controller: _tabController,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textHint,
                indicatorColor: AppColors.textPrimary,
                tabs: [
                  Tab(text: '내가 만든 케미 그룹 (${owned.length})'),
                  Tab(text: '초대받은 케미 그룹 (${invited.length})'),
                ],
              )
            : null,
      ),
      body: SafeArea(
        child: hasMyFace
            ? TabBarView(
                controller: _tabController,
                children: [
                  _groupTab(owned, _ownedEmpty, topGap, bottomGap),
                  _groupTab(invited, _invitedEmpty, topGap, bottomGap),
                ],
              )
            // 내 관상 미등록 — 탭 없이 sticky 섹션 헤더로 두 그룹을 한 스크롤에.
            : _groupScroll(
                [
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickySectionHeader(title: '내가 만든 그룹'),
                  ),
                  ..._sectionSlivers(owned, _ownedEmpty),
                  // 초대받은 방 — P3 원격 합류 방이 들어온다.
                  const SliverPersistentHeader(
                    pinned: true,
                    delegate: _StickySectionHeader(title: '초대받은 그룹'),
                  ),
                  ..._sectionSlivers(invited, _invitedEmpty),
                ],
                topGap,
                bottomGap,
              ),
      ),
    );
  }

  /// 당겨서 새로고침이 붙은 그룹 스크롤 — 탭 본문과 미등록 단일 스크롤 공용.
  Widget _groupScroll(List<Widget> slivers, double topGap, double bottomGap) {
    return RefreshIndicator(
      onRefresh: _refreshGroups,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: SizedBox(height: topGap)),
          ...slivers,
          // 다른 사람 관상 보기는 AppBar 우상단 버튼(카메라/앨범)으로 일원화 —
          // 하단 중복 보조 컨테이너 제거.
          SliverToBoxAdapter(child: SizedBox(height: bottomGap)),
        ],
      ),
    );
  }

  // §3.8 공용 빈 상태 — 탭 본문(세로 중앙)과 미등록 섹션이 공유.
  static const _ownedEmpty = EmotionEmptyState(
    asset: 'assets/images/emotion-laugh.png',
    message: '내가 만든 케미 그룹이 없소이다.',
  );
  static const _invitedEmpty = EmotionEmptyState(
    asset: 'assets/images/emotion-shrug.png',
    message: '초대받은 그룹이 없습니다',
  );

  /// 탭 본문 — 빈 리스트는 관상 빈 탭과 동일하게 SliverFillRemaining 으로
  /// 화면 세로 중앙 정렬.
  Widget _groupTab(
    List<TeamRoom> rooms,
    EmotionEmptyState empty,
    double topGap,
    double bottomGap,
  ) {
    if (rooms.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshGroups,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverFillRemaining(hasScrollBody: false, child: empty),
          ],
        ),
      );
    }
    return _groupScroll([_roomListSliver(rooms)], topGap, bottomGap);
  }

  /// 미등록 모드의 섹션 sliver — sticky 헤더 아래 빈 상태 또는 카드 리스트.
  List<Widget> _sectionSlivers(List<TeamRoom> rooms, EmotionEmptyState empty) {
    if (rooms.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: empty,
          ),
        ),
      ];
    }
    return [_roomListSliver(rooms)];
  }

  Widget _roomListSliver(List<TeamRoom> rooms) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, 0),
      sliver: SliverList.builder(
        itemCount: rooms.length,
        itemBuilder: (_, i) => _TeamCard(
          key: ValueKey(rooms[i].id),
          room: rooms[i],
          onTap: () => _openRoom(rooms[i]),
        ),
      ),
    );
  }

  /// 내 관상 등록 — 공용 플로우 (nudge 배너와 동일 경로).
  Future<void> _createMyFace() => startMyFaceCapture(context, ref);

  /// [진실의 방 만들기] — 내 관상 선행 조건 게이트 (A5):
  /// 미설정이면 먼저 [내 관상 만들기] 플로우, 완료 후 생성 페이지로 복귀.
  Future<void> _createTeam() async {
    var myFace = _findMyFace();
    if (myFace == null) {
      await _createMyFace();
      if (!mounted) return;
      myFace = _findMyFace();
      if (myFace == null) return;
    }
    final ownerId = myFace.supabaseId;
    if (ownerId == null) return;
    final room =
        await showTeamCreatePage(context, ref, ownerReportId: ownerId);
    if (!mounted || room == null) return;
    _openRoom(room);
  }

  FaceReadingReport? _findMyFace() {
    for (final r in ref.read(historyProvider)) {
      if (r.isMyFace) return r;
    }
    return null;
  }

  void _openRoom(TeamRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamRoomScreen(roomId: room.id)),
    );
  }

  /// 당겨서 새로고침 — push 된 그룹의 합류자·마감을 서버에서 끌어온다.
  /// 로컬 전용 그룹은 fetch 가 null 이라 no-op.
  Future<void> _refreshGroups() async {
    final ids = ref.read(teamsProvider).map((r) => r.id).toList();
    for (final id in ids) {
      try {
        await ref.read(teamsProvider.notifier).refreshFromServer(id);
      } catch (_) {
        // 개별 실패는 무시 — 나머지 그룹은 계속 갱신.
      }
    }
  }

  /// 교감도 안내 — 궁합 탭 info 다이얼로그와 동일한 형태 (AlertDialog · 흰 배경
  /// · radius 16 · 섹션 헤딩 + 본문 · [닫기]).
  void _showInfoDialog(BuildContext context) {
    const bands = [
      CompatLabel.cheonjakjihap,
      CompatLabel.geumseulsanghwa,
      CompatLabel.mahapgaseong,
      CompatLabel.hyeonggeuknanjo,
    ];
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('그룹 케미에 대하여', style: AppText.modalTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '그룹(3~12명) 멤버 전원의 얼굴 측정값으로 두 사람씩 모든 짝의 '
                '케미를 계산해 한 장의 표로 보여줍니다. 짝별 계산 기준은 궁합 '
                '분석과 동일합니다.',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('등급', style: AppText.sectionTitle),
              const SizedBox(height: AppSpacing.sm),
              for (final l in bands)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    '${l.bandEmoji} ${l.bandLabel}',
                    style: AppText.body,
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              const Text('진행 방식', style: AppText.sectionTitle),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '그룹을 만들고 직접촬영 또는 카톡 초대로 멤버를 등록합니다. '
                '전원이 등록되면 그룹 케미가 발표됩니다. 3명 이상 모이면 '
                '기다리지 않고 먼저 발표할 수 있습니다.',
                style: AppText.body,
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('무료와 코인', style: AppText.sectionTitle),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '그룹 만들기·멤버 등록·등급 표시는 무료입니다. 짝별 정확한 '
                '점수와 상세 풀이는 1코인으로 열 수 있습니다.',
                style: AppText.body,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '닫기',
              style: AppText.body.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// 홈 섹션 sticky 헤더 — 스크롤해도 상단에 고정 (내가 만든 방 / 초대받은 방).
class _StickySectionHeader extends SliverPersistentHeaderDelegate {
  static const double _height = 40;

  final String title;

  const _StickySectionHeader({required this.title});

  @override
  double get maxExtent => _height;

  @override
  double get minExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
      alignment: Alignment.centerLeft,
      child: Text(
        title,
        style: AppText.caption.copyWith(
          fontWeight: FontWeight.w600,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickySectionHeader oldDelegate) =>
      oldDelegate.title != title;
}

/// 홈 ② 팀 카드 — §3.2 리스트 아이템 토큰. 발표(마감) 후엔 🏆 베스트 페어
/// 프리뷰 한 줄 (A5). 매트릭스는 capture-only 라 저장하지 않으므로 프리뷰는
/// 방 updatedAt 키로 메모이즈해 홈 rebuild 마다 재계산하지 않는다.
class _TeamCard extends ConsumerStatefulWidget {
  final TeamRoom room;
  final VoidCallback onTap;

  const _TeamCard({super.key, required this.room, required this.onTap});

  @override
  ConsumerState<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends ConsumerState<_TeamCard> {
  static final Map<String, String> _bestPreviewCache = {};

  String? _bestPreview;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final card = Material(
      color: AppColors.surface,
      // 궁합 카드와 동일한 1px border (§0.0.1 같은 역할 = 같은 chrome).
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 좌측 상태 아바타 — 모집중 / 모집끝 아이콘으로 구분.
                  _statusAvatar(room.isClosed),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 우상단 더보기 버튼과 안 겹치도록 첫 줄 우측 여백.
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.lg),
                          child: Text(
                            room.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppText.subTitle.copyWith(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${room.scannedCount}/${room.members.length}명 등록',
                          style: AppText.caption
                              .copyWith(color: AppColors.textSecondary),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        // 3번째 줄 고정 — 마감 방은 케미 등급별 쌍 수, 모집중
                        // 방은 발표까지 남은 스캔 수. 두 상태의 카드 높이를 맞춘다.
                        Text(
                          room.isClosed
                              ? (_bestPreview ?? '발표 완료')
                              : _recruitHint(room),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.caption.copyWith(
                            color: AppColors.textHint,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 우상단 더보기 — 삭제 메뉴. 카드 모서리에 바짝 붙인 절대 배치.
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: PopupMenuButton<String>(
                tooltip: '더보기',
                padding: EdgeInsets.zero,
                position: PopupMenuPosition.under,
                constraints: const BoxConstraints(),
                icon: const FaIcon(
                  FontAwesomeIcons.ellipsisVertical,
                  size: 16,
                  color: AppColors.textHint,
                ),
                onSelected: (value) {
                  if (value == 'delete') _confirmDelete(room);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      '삭제',
                      style: AppText.body.copyWith(
                        color: AppColors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      // 그림자는 ClipRRect 바깥(여기)에 — 클립 안에 두면 리본 카드에서 잘린다.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        // 마감 카드 좌상단 대각선 "발표" 리본 — 새 색 없이 gold 바탕 + 흰 텍스트.
        // 카드 radius 로 ClipRRect 해 리본 끝이 모서리에 맞춰 잘린다.
        // UI 카피는 "발표" 통일 — "마감" 은 코드·스키마 내부 용어로만.
        child: room.isClosed
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Banner(
                  message: '발표',
                  location: BannerLocation.topStart,
                  color: AppColors.gold,
                  textStyle: AppText.hint.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                  child: card,
                ),
              )
            : card,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _computeBestPreview();
  }

  void _computeBestPreview() {
    final room = widget.room;
    if (!room.isClosed) return;
    final key = '${room.id}:${room.updatedAt.millisecondsSinceEpoch}';
    final cached = _bestPreviewCache[key];
    if (cached != null) {
      _bestPreview = cached;
      return;
    }
    final members = ref.read(teamsProvider.notifier).scannedReports(room);
    if (members.length < 2) return;
    final matrix = computeTeamMatrix(members);
    final runnerUp = matrix.surprises.length;
    final preview = runnerUp > 0
        ? '베스트 케미 ${matrix.bests.length}쌍, 버금가는 케미 $runnerUp쌍'
        : '베스트 케미 ${matrix.bests.length}쌍';
    _bestPreviewCache[key] = preview;
    _bestPreview = preview;
  }

  /// 방 삭제 — 되돌릴 수 없어 확인 다이얼로그 후 제거.
  Future<void> _confirmDelete(TeamRoom room) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('그룹을 삭제할까요?', style: AppText.subTitle),
        content: Text(
          '‘${room.title}’ 그룹이 사라지고 되돌릴 수 없어요.',
          style: AppText.body.copyWith(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('취소',
                style: AppText.body.copyWith(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('삭제',
                style: AppText.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(teamsProvider.notifier).delete(room.id);
  }

  /// 모집중 방의 3번째 줄 — 발표(전원 등록 자동 마감)까지 남은 수. 3명 부분
  /// 공개 로직 폐기로 카운트가 빈 슬롯 수와 항상 일치한다.
  String _recruitHint(TeamRoom room) {
    return '${room.members.length - room.scannedCount}명 더 등록하면 그룹 케미 발표 가능';
  }

  /// 좌측 상태 아바타 — 모집중과 모집끝 모두 동일한 peopleGroup 아이콘.
  /// 모집끝은 톤만 gold 계열(goldSoft 바탕 + gold 아이콘)로 구분한다.
  Widget _statusAvatar(bool isClosed) {
    const double size = 44;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isClosed ? AppColors.goldSoft : Colors.white,
        border: Border.all(
          color: isClosed ? AppColors.gold : AppColors.border,
        ),
      ),
      child: Center(
        child: FaIcon(
          FontAwesomeIcons.peopleGroup,
          size: 16,
          color: isClosed ? AppColors.gold : AppColors.textSecondary,
        ),
      ),
    );
  }
}
