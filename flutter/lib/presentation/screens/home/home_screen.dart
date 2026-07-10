import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/config/router.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/team_room.dart';
import 'package:facely/domain/services/team_matrix.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/screens/team/team_create_page.dart';
import 'package:facely/presentation/screens/team/team_room_screen.dart';
import 'package:facely/presentation/widgets/coin_chip.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'album_capture_page.dart';
import 'face_mesh_page.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 720;
    final imageHeight = compact ? 160.0 : 200.0;
    final topGap = compact ? AppSpacing.sm : AppSpacing.xl;
    final bottomGap = compact ? AppSpacing.lg : AppSpacing.huge;

    // 팀 카드의 alias·썸네일이 history 변화에 반응하도록 watch 유지.
    ref.watch(historyProvider);
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
            const Text('교감'),
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
        actions: [
          PopupMenuButton<String>(
            tooltip: '다른 사람 관상보기',
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            onSelected: (value) {
              if (value == 'camera') {
                _openCamera();
              } else if (value == 'album') {
                _openAlbum();
              }
            },
            itemBuilder: (ctx) => const [
              PopupMenuItem<String>(
                value: 'camera',
                child: Row(
                  children: [
                    FaIcon(FontAwesomeIcons.camera,
                        size: 16, color: AppColors.textPrimary),
                    SizedBox(width: AppSpacing.md),
                    Text('카메라로 촬영', style: AppText.body),
                  ],
                ),
              ),
              PopupMenuItem<String>(
                value: 'album',
                child: Row(
                  children: [
                    FaIcon(FontAwesomeIcons.image,
                        size: 16, color: AppColors.textPrimary),
                    SizedBox(width: AppSpacing.md),
                    Text('앨범에서 선택', style: AppText.body),
                  ],
                ),
              ),
            ],
            // 설정 [충전하기]·궁합 등록 pill 과 동일 outlined stadium 레시피.
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    border: Border.all(color: AppColors.textPrimary),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '다른 사람 관상보기',
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshGroups,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
            SliverToBoxAdapter(child: SizedBox(height: topGap)),
            // 내가 만든 방 — sticky 섹션 헤더.
            const SliverPersistentHeader(
              pinned: true,
              delegate: _StickySectionHeader(title: '내가 만든 그룹'),
            ),
            if (owned.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl),
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      Image.asset(
                        'assets/images/team-chemistry-map.png',
                        height: imageHeight,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '첫 교감도를 만들어 보세요',
                        style: AppText.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, 0),
                sliver: SliverList.builder(
                  itemCount: owned.length,
                  itemBuilder: (_, i) => _TeamCard(
                    key: ValueKey(owned[i].id),
                    room: owned[i],
                    onTap: () => _openRoom(owned[i]),
                  ),
                ),
              ),
            // ③ 생성 CTA — 내가 만든 방 섹션 바로 아래.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl, AppSpacing.sm, AppSpacing.xxl,
                    AppSpacing.xl),
                // 본문 CTA 는 흰색+1px border — 검정 invert 는 오버레이(스낵바) 전용.
                child: SecondaryButton(
                  label: '그룹 케미 알아보기',
                  onPressed: _createTeam,
                ),
              ),
            ),
            // 초대받은 방 — sticky 섹션 헤더. P3 원격 합류 방이 들어온다.
            const SliverPersistentHeader(
              pinned: true,
              delegate: _StickySectionHeader(title: '초대받은 그룹'),
            ),
            if (invited.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxl),
                  child: Column(
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      // nudge 스낵바의 emotion-photo(84) 와 동일 크기 — 같은
                      // emotion 일러스트 패밀리는 같은 스케일로.
                      Image.asset(
                        'assets/images/emotion-shrug.png',
                        width: 84,
                        height: 84,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '초대받은 그룹이 없습니다',
                        style: AppText.caption.copyWith(
                          color: AppColors.textHint,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.xxl, AppSpacing.md, AppSpacing.xxl, 0),
                sliver: SliverList.builder(
                  itemCount: invited.length,
                  itemBuilder: (_, i) => _TeamCard(
                    key: ValueKey(invited[i].id),
                    room: invited[i],
                    onTap: () => _openRoom(invited[i]),
                  ),
                ),
              ),
            // 다른 사람 관상 보기는 AppBar 우상단 버튼(카메라/앨범)으로 일원화 —
            // 하단 중복 보조 컨테이너 제거.
            SliverToBoxAdapter(child: SizedBox(height: bottomGap)),
            ],
          ),
        ),
      ),
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

  /// 앨범 path — 카메라와 동일한 fullSize sheet 에 AlbumCapturePage 를 띄움.
  Future<void> _openAlbum() async {
    AnalyticsService.instance.logAlbumOpen();
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn) return;
      if (!mounted) return;
    }
    final result = await _showAlbumSheet();
    if (!mounted || result == null) return;
    await _pushDemographicConfirm(result);
  }

  /// 카메라 path — fullSize sheet 안에 FaceMeshPage 가 검정 AppBar
  /// "얼굴 정면" / "얼굴 측면" 으로 동작.
  Future<void> _openCamera() async {
    AnalyticsService.instance.logCameraOpen();
    final size = MediaQuery.of(context).size;
    final result = await showModalBottomSheet<CaptureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height,
      ),
      builder: (_) => const FaceMeshPage(),
    );
    if (!mounted || result == null) return;
    await _pushDemographicConfirm(result);
  }

  void _openRoom(TeamRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamRoomScreen(roomId: room.id)),
    );
  }

  Future<void> _pushDemographicConfirm(
    CaptureResult result, {
    bool asMyFace = false,
  }) async {
    await context.push(
      '/capture/confirm',
      extra: CaptureExtras(
        capture: result,
        metadataFuture: result.metadataFuture,
        asMyFace: asMyFace,
      ),
    );
  }

  Future<CaptureResult?> _showAlbumSheet() {
    final size = MediaQuery.of(context).size;
    return showModalBottomSheet<CaptureResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height,
      ),
      builder: (_) => const AlbumCapturePage(),
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
      borderRadius: BorderRadius.circular(AppRadius.lg),
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
                              .copyWith(color: AppColors.textHint),
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
                            color: AppColors.textSecondary,
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
        // 마감 카드 좌상단 대각선 "완료" 리본 — 새 색 없이 gold 바탕 + 흰 텍스트.
        // 카드 radius 로 ClipRRect 해 리본 끝이 모서리에 맞춰 잘린다.
        child: room.isClosed
            ? ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Banner(
                  message: '마감',
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

  @override
  void initState() {
    super.initState();
    _computeBestPreview();
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

  /// 모집중 방의 3번째 줄 — 발표(자동 마감)까지 남은 스캔 수를 사실 그대로.
  String _recruitHint(TeamRoom room) {
    if (room.members.length < TeamRoom.kMinMembers) {
      return '최소 ${TeamRoom.kMinMembers}명부터 발표';
    }
    return '${room.members.length - room.scannedCount}명 더 등록하면 발표';
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
}
