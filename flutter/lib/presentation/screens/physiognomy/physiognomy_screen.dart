import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:facely/presentation/widgets/other_face_scan_pill.dart';
import 'package:facely/presentation/widgets/physiognomy_info_dialog.dart';
import 'package:facely/presentation/widgets/source_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

// 화면-국지 팔레트 — DESIGN.md §2.4 (file-local 격리).
// 본 화면은 AppColors 의 gold / goldDim / goldSoft / surface / border / textHint
// 만으로 충분 — file-local 컬러 상수 없음. 프로필 헤더는 DESIGN.md §3.7
// (Integrated sliver header) 에 따라 AppColors 만 사용.

class PhysiognomyScreen extends ConsumerStatefulWidget {
  const PhysiognomyScreen({super.key});

  @override
  ConsumerState<PhysiognomyScreen> createState() => _PhysiognomyScreenState();
}

class _PhysiognomyItem extends ConsumerWidget {
  final FaceReadingReport report;
  final int index;
  final AnalysisSource source;

  const _PhysiognomyItem({
    required this.report,
    required this.index,
    required this.source,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName =
        report.alias ??
        (report.source == AnalysisSource.received
            ? '공유받은 카드'
            : report.faceShape.korean);
    final isMyFace = report.isMyFace;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Stack(
        key: ValueKey(report.supabaseId ?? index),
        children: [
          Material(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              onTap: () => context.push(
                '/r/${report.supabaseId ?? 'local'}',
                extra: report,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Padding(
                // 우측 huge(32) — 우상단 absolute-positioned 3-dot 메뉴 자리 확보.
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.md,
                  AppSpacing.huge,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 상단: 아바타 + 데모그래픽/별칭 (아바타 옆 영역).
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLeadingIcon(),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      // 헤더 §3.7 과 동일 포맷: 연령대 성별 인종 (가운데점 X).
                                      '${report.ageGroup.labelKo} '
                                      '${report.gender.labelKo} '
                                      '${report.ethnicity.labelKo}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.sectionTitle.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  if (isMyFace) ...[
                                    const SizedBox(width: AppSpacing.sm),
                                    // SourceBadge 와 동일 chrome 의 outlined
                                    // badge — 정체성(내 관상)만 gold 톤.
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        border: Border.all(
                                          color: AppColors.gold,
                                        ),
                                        borderRadius: BorderRadius.circular(
                                          AppRadius.sm,
                                        ),
                                      ),
                                      child: Text(
                                        '내 관상',
                                        style: AppText.hint.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.gold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              // 헤더 caption 자리: source badge + 별칭/얼굴형.
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SourceBadge(source: report.source),
                                  const SizedBox(width: AppSpacing.xs),
                                  Flexible(
                                    child: Text(
                                      displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: AppText.caption.copyWith(
                                        color: AppColors.textHint,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    const Divider(
                      height: 1,
                      thickness: 0.5,
                      color: AppColors.border,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    // 카드 full-width 하단 바: 생성시간(좌) ↔ archetype 뱃지(우),
                    // 수직 중앙. 아바타 폭까지 써서 1줄에 담아 wrapping 방지.
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          timeago.format(report.timestamp, locale: 'ko'),
                          style: AppText.hint,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(child: _buildArchetypeBadges()),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 우상단 absolute-positioned 3-dot 메뉴 — 모서리에 최대한 붙임.
          Positioned(
            top: 0,
            right: 0,
            child: PopupMenuButton<String>(
              tooltip: '메뉴',
              padding: EdgeInsets.zero,
              iconSize: 18,
              icon: const FaIcon(
                FontAwesomeIcons.ellipsisVertical,
                color: AppColors.textHint,
                size: 16,
              ),
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              onSelected: (value) {
                if (value == 'rename') {
                  _showAliasDialog(context, ref, displayName);
                } else if (value == 'setMyFace') {
                  _setMyFace(context, ref);
                } else if (value == 'clearMyFace') {
                  _clearMyFace(context, ref);
                } else if (value == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
              itemBuilder: (ctx) => [
                // 받은(북마크) 카드는 남의 얼굴 — 내 관상으로 설정 불가.
                if (report.source != AnalysisSource.received)
                  PopupMenuItem<String>(
                    value: isMyFace ? 'clearMyFace' : 'setMyFace',
                    child: Text(
                      isMyFace ? '내 관상으로 설정 취소' : '내 관상으로 설정',
                      style: AppText.body,
                    ),
                  ),
                const PopupMenuItem<String>(
                  value: 'rename',
                  child: Text('제목 변경', style: AppText.body),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: Text(
                    '삭제',
                    style: AppText.body.copyWith(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Archetype 시각 검증용 뱃지 — primary / secondary / specialArchetype.
  /// 사용자가 "쏠림현상 있는지" 눈으로 바로 판단할 수 있도록 list item 에 직접 노출.
  Widget _buildArchetypeBadges() {
    final primary = report.archetype.primaryLabel;
    final secondary = report.archetype.secondaryLabel;
    final special = report.archetype.specialArchetype;

    Widget chip(String text, {required Color bg, required Color fg}) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: Text(
          text,
          style: AppText.hint.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      );
    }

    return Wrap(
      alignment: WrapAlignment.end,
      runAlignment: WrapAlignment.center,
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        chip(
          primary,
          bg: AppColors.textPrimary.withValues(alpha: 0.08),
          fg: AppColors.textPrimary,
        ),
        chip(
          '$secondary 기질',
          bg: Colors.transparent,
          fg: AppColors.textSecondary,
        ),
        if (special != null)
          chip(special, bg: Colors.indigo.shade50, fg: Colors.indigo.shade700),
      ],
    );
  }

  Widget _buildLeadingIcon() {
    // §3.7 — 내 관상 프로필 헤더 avatar 42px 와 동일 사이즈.
    // 아바타는 전 탭 공통 circle (rounded square 금지 — 통일감).
    const size = 42.0;
    final file = ThumbnailPaths.resolveFileSync(report.thumbnailPath);
    if (file != null && file.existsSync()) {
      return ClipOval(
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.border,
        shape: BoxShape.circle,
      ),
      child: FaIcon(
        switch (report.source) {
          AnalysisSource.camera => FontAwesomeIcons.faceSmile,
          AnalysisSource.album => FontAwesomeIcons.images,
          AnalysisSource.received => FontAwesomeIcons.shareNodes,
        },
        color: AppColors.textSecondary,
        size: 18,
      ),
    );
  }

  void _clearMyFace(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).clearMyFace();
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '내 관상 지정을 취소했습니다'),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    final demographic =
        '${report.ageGroup.labelKo} '
        '${report.gender.labelKo} '
        '${report.ethnicity.labelKo}';
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: Text('$demographic 기록을 삭제할까요?', style: AppText.modalTitle),
        content: const Text('이 작업은 되돌릴 수 없습니다.', style: AppText.body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: AppText.body.copyWith(color: AppColors.textHint),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              ref.read(historyProvider.notifier).remove(index);
              showTopSnackBar(
                Overlay.of(context),
                CompactSnackBar.success(message: '삭제되었습니다'),
              );
            },
            child: Text('삭제',
                style: AppText.body.copyWith(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  void _setMyFace(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).setMyFace(index);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '내 관상을 지정했습니다'),
    );
  }

  void _showAliasDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('이름 변경', style: AppText.modalTitle),
        content: TextField(
          controller: controller,
          maxLength: 64,
          autofocus: true,
          decoration: const InputDecoration(hintText: '이름을 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: AppText.body.copyWith(color: AppColors.textHint),
            ),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(historyProvider.notifier)
                  .updateAlias(index, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text(
              '저장',
              style: AppText.body.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhysiognomyScreenState extends ConsumerState<PhysiognomyScreen>
    with SingleTickerProviderStateMixin {
  // 북마크(받은 카드) 유무에 따라 탭 수가 2↔3 으로 바뀌므로 nullable + 동적 재생성.
  TabController? _tabController;
  _SortOrder _sortOrder = _SortOrder.newest;

  // 카메라/앨범 default 탭 — 내 관상이 있으면 내 관상이 사는 탭에서 시작.
  // 최초 1회만: 이후엔 사용자의 명시적 선택과 분석 후 이동(info_confirm)이
  // 우선이라 다시 강제하지 않는다.
  bool _appliedMyFaceDefault = false;

  @override
  Widget build(BuildContext context) {
    // Only react to actual provider changes (e.g. external selectTab calls
    // from album_preview after analysis). Avoid forcing on every rebuild.
    final history = ref.watch(historyProvider);
    // 북마크(받은 카드) 존재 시에만 3번째 탭 — 없으면 2탭. 개수 변화 시 재생성.
    final hasBookmarks =
        history.any((r) => r.source == AnalysisSource.received);
    _syncTabController(hasBookmarks ? 3 : 2);
    final tabController = _tabController!;

    ref.listen<int>(historyTabProvider, (prev, next) {
      if (next < tabController.length && tabController.index != next) {
        tabController.animateTo(next);
      }
    });

    // myFace 는 source 와 무관한 single-pick — 리스트 빈 상태 분기에서
    // 두 탭이 공유. _buildList 내부에서 따로 계산하지 않는다.
    FaceReadingReport? myFace;
    for (final r in history) {
      if (r.isMyFace) {
        myFace = r;
        break;
      }
    }
    final hasMyFace = myFace != null;

    // 내 관상이 앨범 소스면 default 를 앨범 탭으로 (히스토리 hydrate 후 1회).
    // provider 가 아직 초기값(0)일 때만 — 이미 다른 흐름이 탭을 정했으면 존중.
    if (!_appliedMyFaceDefault && myFace != null) {
      _appliedMyFaceDefault = true;
      if (myFace.source == AnalysisSource.album &&
          ref.read(historyTabProvider) == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(historyTabProvider.notifier).selectTab(1);
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
            sliver: SliverAppBar(
              pinned: true,
              // 내 관상 프로필 슬롯 제거 (2026-06-12) — 등록 상태는 nudge 배너
              // 유무가 전달하고, 리스트 카드의 gold '내 관상' 배지가 식별을
              // 맡는다. 헤더는 타이틀 + TabBar 만.
              title: const Text('관상'),
              actions: [
                // 상대방 관상 추가 — 궁합 탭과 공유하는 공용 pill.
                const OtherFaceScanPill(),
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
                  onPressed: () => _showInfoDialog(context),
                ),
              ],
              // 궁합 탭과 동일 규칙 — 내부 탭은 내 관상 등록 후에만 나타난다.
              // 미등록 상태에선 탭 없이 단일 리스트 (카드별 SourceBadge 가
              // 소스를 전달). 탭 라벨엔 개수 노출 (스크롤 없이 존재 여부 인지).
              bottom: hasMyFace
                  ? TabBar(
                      controller: tabController,
                      labelColor: AppColors.textPrimary,
                      unselectedLabelColor: AppColors.textHint,
                      indicatorColor: AppColors.textPrimary,
                      tabs: [
                        Tab(
                          text: '카메라 '
                              '(${history.where((r) => r.source == AnalysisSource.camera).length})',
                        ),
                        Tab(
                          text: '앨범 '
                              '(${history.where((r) => r.source == AnalysisSource.album).length})',
                        ),
                        if (hasBookmarks)
                          Tab(
                            text: '공유받음 '
                                '(${history.where((r) => r.source == AnalysisSource.received).length})',
                          ),
                      ],
                    )
                  : null,
            ),
          ),
        ],
        body: hasMyFace
            ? TabBarView(
                controller: tabController,
                children: [
                  _buildList(history, const [AnalysisSource.camera], hasMyFace),
                  _buildList(history, const [AnalysisSource.album], hasMyFace),
                  if (hasBookmarks)
                    _buildList(
                        history, const [AnalysisSource.received], hasMyFace),
                ],
              )
            : _buildList(
                history,
                const [
                  AnalysisSource.camera,
                  AnalysisSource.album,
                  AnalysisSource.received,
                ],
                hasMyFace,
              ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final history = ref.read(historyProvider);
    final hasBookmarks =
        history.any((r) => r.source == AnalysisSource.received);
    _syncTabController(hasBookmarks ? 3 : 2);
  }

  /// 한 tab 의 내용을 그린다. sources 는 그 tab 에서 보일 source list.
  ///   • 카메라 탭: [camera]
  ///   • 앨범 탭: [album, received] — 둘 다 section 으로 나란히 노출. count
  ///     0 인 source 는 section 자체 hidden (dead-space 없음).
  /// 모든 source 가 비어있으면 단일 empty state.
  Widget _buildList(
    List<FaceReadingReport> history,
    List<AnalysisSource> sources,
    bool hasMyFace,
  ) {
    final groups = <(AnalysisSource, List<(int, FaceReadingReport)>)>[];
    for (final s in sources) {
      final filtered = <(int, FaceReadingReport)>[];
      for (var i = 0; i < history.length; i++) {
        if (history[i].source == s) filtered.add((i, history[i]));
      }
      if (filtered.isEmpty) continue;
      filtered.sort((a, b) {
        final at = a.$2.timestamp;
        final bt = b.$2.timestamp;
        return _sortOrder == _SortOrder.newest
            ? bt.compareTo(at)
            : at.compareTo(bt);
      });
      groups.add((s, filtered));
    }
    final allEmpty = groups.isEmpty;

    return Builder(
      builder: (context) => RefreshIndicator(
        onRefresh: _handleRefresh,
        color: AppColors.textPrimary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // NestedScrollView 의 outer SliverOverlapAbsorber 와 짝.
            // 인너 스크롤이 헤더 collapse 를 정확히 트리거하도록 보장.
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            if (allEmpty)
              // §3.8 일러스트 빈 상태 — 궁합 탭과 동일한 공용 EmotionEmptyState.
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmotionEmptyState(
                  asset: 'assets/images/emotion-anger.png',
                  message: '아직 관상을 등록하지 않았다니!',
                ),
              )
            else ...[
              for (var gi = 0; gi < groups.length; gi++) ...[
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    gi == 0 ? AppSpacing.lg : AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.md,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _RecentListHeader(
                      order: _sortOrder,
                      onChanged: (v) => setState(() => _sortOrder = v),
                      // sort popup 은 첫 section 에만 — 한 tab 당 1개.
                      showSortToggle: gi == 0,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  sliver: SliverList.builder(
                    itemCount: groups[gi].$2.length,
                    itemBuilder: (ctx, i) {
                      final (origIdx, report) = groups[gi].$2[i];
                      return _PhysiognomyItem(
                        report: report,
                        index: origIdx,
                        source: groups[gi].$1,
                      );
                    },
                  ),
                ),
              ],
              if (!hasMyFace)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    AppSpacing.xxl,
                  ),
                  sliver: SliverToBoxAdapter(child: _ProfileHintCard()),
                )
              else
                const SliverPadding(
                  padding: EdgeInsets.only(bottom: AppSpacing.lg),
                  sliver: SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// Pull-to-refresh: Hive capture 은 그대로, 해석만 현재 엔진(weight matrix ·
  /// rule · quantile) 으로 재계산. 새 공식이 기존 리포트에 즉시 반영된다.
  Future<void> _handleRefresh() async {
    // ignore: avoid_print
    print('[PhysiognomyScreen] pull-to-refresh START');
    final before = ref.read(historyProvider).length;
    await ref.read(historyProvider.notifier).reloadFromHive();
    final after = ref.read(historyProvider).length;
    // ignore: avoid_print
    print(
      '[PhysiognomyScreen] pull-to-refresh reloadFromHive returned: '
      'state before=$before → after=$after',
    );
    // 사용자 명시: snackbar 의미가 모호 — console log 로만 대체.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    // ignore: avoid_print
    print('[PhysiognomyScreen] reloadFromHive → 재계산 완료');
  }

  void _showInfoDialog(BuildContext context) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'info',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (ctx, anim, secondAnim, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        );
      },
      pageBuilder: (ctx, anim, secondAnim) {
        final maxH = MediaQuery.of(ctx).size.height * 0.8;
        return Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: PhysiognomyInfoDialog(maxHeight: maxH),
          ),
        );
      },
    );
  }

  /// 탭 개수가 바뀔 때만 컨트롤러를 재생성 — 매 build 재생성 방지.
  void _syncTabController(int length) {
    final existing = _tabController;
    if (existing != null && existing.length == length) return;
    final int prevIndex = existing?.index ?? ref.read(historyTabProvider);
    existing?.dispose();
    final c = TabController(
      length: length,
      vsync: this,
      initialIndex: prevIndex.clamp(0, length - 1),
    );
    c.addListener(() {
      if (!c.indexIsChanging &&
          ref.read(historyTabProvider) != c.index) {
        ref.read(historyTabProvider.notifier).selectTab(c.index);
      }
    });
    _tabController = c;
  }
}

/// 내 관상 미설정 안내 — 공용 EmotionEmptyState (§3.8) 재사용.
/// 아이템이 있는 리스트 하단에서 "등록 또는 기존 사진으로 변경" 경로를 안내.
class _ProfileHintCard extends StatelessWidget {
  const _ProfileHintCard();

  @override
  Widget build(BuildContext context) {
    return const EmotionEmptyState(
      asset: 'assets/images/emotion-sad.png',
      message: '점3개 (더보기 메뉴) 버튼을 누르면 이미 등록한\n'
          '사진을 내 관상으로 변경할 수 도 있습니다. ',
    );
  }
}

/// 탭 리스트 상단 정렬 셀렉터 — 섹션 라벨·개수는 탭 라벨이 담당하므로
/// (같은 정보 중복 금지, 궁합 탭과 동일 패턴) 우측 정렬 selector 만.
class _RecentListHeader extends StatelessWidget {
  final _SortOrder order;
  final ValueChanged<_SortOrder> onChanged;
  final bool showSortToggle;

  const _RecentListHeader({
    required this.order,
    required this.onChanged,
    this.showSortToggle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showSortToggle)
          PopupMenuButton<_SortOrder>(
            tooltip: '정렬',
            initialValue: order,
            padding: EdgeInsets.zero,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            onSelected: onChanged,
            itemBuilder: (ctx) => _SortOrder.values
                .map(
                  (o) => PopupMenuItem<_SortOrder>(
                    value: o,
                    child: Text(o.label, style: AppText.body),
                  ),
                )
                .toList(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  order.label,
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
                const SizedBox(width: AppSpacing.sm),
                const FaIcon(
                  FontAwesomeIcons.chevronDown,
                  size: 12,
                  color: AppColors.textHint,
                ),
              ],
            ),
          ),
      ],
    );
  }
}

enum _SortOrder {
  newest('최신순'),
  oldest('오래된순');

  final String label;
  const _SortOrder(this.label);
}
