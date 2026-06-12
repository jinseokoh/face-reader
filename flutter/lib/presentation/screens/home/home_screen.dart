import 'package:face_engine/data/enums/face_shape.dart';
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
import 'package:facely/presentation/screens/team/team_create_sheet.dart';
import 'package:facely/presentation/screens/team/team_room_screen.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';
import 'package:facely/presentation/widgets/my_face_header.dart';
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

class _HomeActionCard extends StatefulWidget {
  final String label;
  final FaIconData icon;
  final VoidCallback? onPressed;
  final bool reverse;

  const _HomeActionCard({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.reverse = false,
  });

  @override
  State<_HomeActionCard> createState() => _HomeActionCardState();
}

class _HomeActionCardState extends State<_HomeActionCard>
    with SingleTickerProviderStateMixin {
  static const _swingAmplitude = 0.05; // ≈ 2.9°
  late final AnimationController _controller;
  late final Animation<double> _rotation;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: AnimatedBuilder(
        animation: _rotation,
        builder: (_, child) => Transform.rotate(
          angle: _rotation.value,
          child: child,
        ),
        child: Material(
          color: Colors.white,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            side: BorderSide(color: AppColors.border, width: 1),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FaIcon(widget.icon, size: 28, color: AppColors.textPrimary),
                const SizedBox(height: AppSpacing.md),
                Text(
                  widget.label,
                  style: AppText.subTitle.copyWith(color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat(reverse: true);
    final begin = widget.reverse ? _swingAmplitude : -_swingAmplitude;
    final end = widget.reverse ? -_swingAmplitude : _swingAmplitude;
    _rotation = Tween<double>(begin: begin, end: end)
        .chain(CurveTween(curve: Curves.easeInOut))
        .animate(_controller);
  }
}

/// 홈 ② 팀 카드 — §3.2 리스트 아이템 토큰. 발표(마감) 후엔 🏆 베스트 페어
/// 프리뷰 한 줄 (A5). 매트릭스는 capture-only 라 저장하지 않으므로 프리뷰는
/// 방 updatedAt 키로 메모이즈해 홈 rebuild 마다 재계산하지 않는다.
class _TeamCard extends ConsumerStatefulWidget {
  final TeamRoom room;
  final VoidCallback onTap;

  const _TeamCard({required this.room, required this.onTap});

  @override
  ConsumerState<_TeamCard> createState() => _TeamCardState();
}

class _TeamCardState extends ConsumerState<_TeamCard> {
  static final Map<String, String> _bestPreviewCache = {};

  String? _bestPreview;

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
    final members = ref.read(teamsProvider.notifier).resolveMembers(room);
    if (members.length < 2) return;
    final matrix = computeTeamMatrix(members);
    String nameOf(FaceReadingReport r) => r.alias ?? r.faceShape.korean;
    final preview =
        '🏆 ${nameOf(matrix.best.a)} ×× ${nameOf(matrix.best.b)} '
        '${matrix.best.total.round()}';
    _bestPreviewCache[key] = preview;
    _bestPreview = preview;
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final count = room.memberReportIds.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
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
                      room.isClosed ? '발표 ✓' : '모집 중',
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: room.isClosed
                            ? AppColors.gold
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '$count/${TeamRoom.kMaxMembers}명 참여',
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
                if (_bestPreview != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _bestPreview!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 720;
    final imageHeight = compact ? 160.0 : 200.0;
    final topGap = compact ? AppSpacing.sm : AppSpacing.xl;
    final bottomGap = compact ? AppSpacing.lg : AppSpacing.huge;

    final history = ref.watch(historyProvider);
    FaceReadingReport? myFace;
    for (final r in history) {
      if (r.isMyFace) {
        myFace = r;
        break;
      }
    }
    final teams = ref.watch(teamsProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (ctx, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ① 내 관상 컴팩트 헤더 — DESIGN.md §3.7 chrome (관상 탭
                    // 헤더와 동일 공용 위젯). 미설정 시 탭 = 셀카 등록 플로우.
                    MyFaceHeader(
                      myFace: myFace,
                      unsetCaption: '탭하면 셀카 한 장으로 등록됩니다.',
                      onTap: () {
                        final mf = myFace;
                        if (mf == null) {
                          _createMyFace();
                          return;
                        }
                        context.push(
                          '/r/${mf.supabaseId ?? 'local'}',
                          extra: mf,
                        );
                      },
                    ),
                    SizedBox(height: topGap),
                    // ② 팀 케미 맵 영역 — 있으면 카드 리스트, 없으면 기본 배경
                    // (team-chemistry-map.png) + 첫 팀 안내 (A5).
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl),
                      child: teams.isEmpty
                          ? Column(
                              children: [
                                Image.asset(
                                  'assets/images/team-chemistry-map.png',
                                  height: imageHeight,
                                  fit: BoxFit.contain,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  '첫 팀 케미 맵을 만들어 보세요',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textHint,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '진행 중인 팀 케미 맵',
                                  style: AppText.caption.copyWith(
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.md),
                                for (final room in teams)
                                  _TeamCard(
                                    room: room,
                                    onTap: () => _openRoom(room),
                                  ),
                              ],
                            ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    // ③ 생성 CTA (A5).
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl),
                      child: ElevatedButton(
                        onPressed: _createTeam,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.textPrimary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              vertical: AppSpacing.lg),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        child: const Text(
                          '＋ 팀 케미 맵 만들기',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const Spacer(),
                    // ④ 다른 사람 관상 보기 — 보조 영역 (현행 2버튼 유지).
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xxl),
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius:
                              BorderRadius.circular(AppRadius.xl),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '다른 사람 관상 보기',
                              style: AppText.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Row(
                              children: [
                                Expanded(
                                  child: _HomeActionCard(
                                    label: '카메라로 촬영',
                                    icon: FontAwesomeIcons.camera,
                                    onPressed: _openCamera,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: _HomeActionCard(
                                    label: '앨범에서 선택',
                                    icon: FontAwesomeIcons.image,
                                    onPressed: _openAlbum,
                                    reverse: true,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: bottomGap),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openRoom(TeamRoom room) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TeamRoomScreen(roomId: room.id)),
    );
  }

  /// [＋ 팀 케미 맵 만들기] — 내 관상 선행 조건 게이트 (A5):
  /// 미설정이면 먼저 [내 관상 만들기] 플로우, 완료 후 생성 시트로 복귀.
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
    final room = await showTeamCreateSheet(context, ref, ownerReportId: ownerId);
    if (!mounted || room == null) return;
    _openRoom(room);
  }

  FaceReadingReport? _findMyFace() {
    for (final r in ref.read(historyProvider)) {
      if (r.isMyFace) return r;
    }
    return null;
  }

  /// [내 관상 만들기] — 전면 카메라 즉시 오픈 (PIVOT A5 ①). 카메라 좌하단
  /// 앨범 아이콘으로 보정해 둔 사진 등록 경로 제공, 선택 다이얼로그 없음.
  /// 분석 완료 시 InfoConfirm 이 isMyFace 로 등록하고 홈에 남는다.
  Future<void> _createMyFace() async {
    AnalyticsService.instance.logCameraOpen();
    final size = MediaQuery.of(context).size;
    final result = await showModalBottomSheet<Object>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints.tightFor(
        width: size.width,
        height: size.height,
      ),
      builder: (_) => const FaceMeshPage(albumShortcut: true),
    );
    if (!mounted || result == null) return;
    if (result is FaceMeshAlbumRequest) {
      // 앨범 경로는 기존 _openAlbum 과 동일하게 로그인 게이트 적용.
      if (!ref.read(authProvider.notifier).isLoggedIn) {
        final loggedIn = await showLoginBottomSheet(context, ref);
        if (!loggedIn) return;
        if (!mounted) return;
      }
      final albumResult = await _showAlbumSheet();
      if (!mounted || albumResult == null) return;
      await _pushDemographicConfirm(albumResult, asMyFace: true);
      return;
    }
    if (result is CaptureResult) {
      await _pushDemographicConfirm(result, asMyFace: true);
    }
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
}
