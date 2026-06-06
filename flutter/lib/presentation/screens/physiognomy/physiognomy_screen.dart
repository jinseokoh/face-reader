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
import 'package:facely/presentation/widgets/empty_state_placeholder.dart';
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

class _HeaderAvatar extends StatelessWidget {
  final FaceReadingReport? myFace;

  const _HeaderAvatar({required this.myFace});

  @override
  Widget build(BuildContext context) {
    // §3.7 — 다크 hero 의 84px 절반.
    const size = 42.0;
    Widget inner = const _HeaderAvatarPlaceholder();
    final file = ThumbnailPaths.resolveFileSync(myFace?.thumbnailPath);
    if (file != null && file.existsSync()) {
      inner = Image.file(file, width: size, height: size, fit: BoxFit.cover);
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.gold, width: 1.5),
      ),
      child: ClipOval(child: inner),
    );
  }
}

class _HeaderAvatarPlaceholder extends StatelessWidget {
  const _HeaderAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: const Center(
        child: FaIcon(
          FontAwesomeIcons.userPlus,
          size: 18,
          color: AppColors.textHint,
        ),
      ),
    );
  }
}

/// 내 관상 프로필 — sliver header integrated 형태.
/// DESIGN.md §3.7 (Integrated sliver header — 옅은 톤) 준수:
///   - background: AppColors.background (white) + bottom 1px border
///   - borderRadius: 0 (chrome 의 일부, 카드 chrome 없음)
///   - avatar: 42px (§3.4 다크 hero 의 84px 절반)
///   - eyebrow: gold / title: textPrimary / caption: textHint
class _MyProfileHeader extends StatelessWidget {
  final FaceReadingReport? myFace;

  const _MyProfileHeader({required this.myFace});

  @override
  Widget build(BuildContext context) {
    final mf = myFace;
    final isSet = mf != null;
    final titleText = isSet
        ? '${mf.ageGroup.labelKo} ${mf.gender.labelKo} '
              '${mf.ethnicity.labelKo}'
        : '내 관상을 설정해주세요.';
    final captionText = isSet
        ? (mf.alias ?? mf.faceShape.korean)
        : '더보기 메뉴를 통해 설정 가능합니다.';
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _HeaderAvatar(myFace: myFace),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FaIcon(
                      FontAwesomeIcons.circleCheck,
                      size: 12,
                      color: AppColors.gold,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      '내 관상',
                      style: AppText.caption.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.sectionTitle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                // §0.0.1 title↔subtitle gap = AppSpacing.xs (list item 과 동일).
                const SizedBox(height: AppSpacing.xs),
                Text(
                  captionText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
            ? '카톡으로 전달받은 카드'
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
                                    const SizedBox(width: AppSpacing.xs),
                                    const FaIcon(
                                      FontAwesomeIcons.circleCheck,
                                      size: 12,
                                      color: AppColors.gold,
                                    ),
                                    const SizedBox(width: AppSpacing.xs),
                                    Text(
                                      '내 관상',
                                      style: AppText.caption.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.gold,
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
    const size = 42.0;
    final file = ThumbnailPaths.resolveFileSync(report.thumbnailPath);
    if (file != null && file.existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
            child: const Text(
              '취소',
              style: TextStyle(color: AppColors.textHint),
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
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
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
            child: const Text(
              '취소',
              style: TextStyle(color: AppColors.textHint),
            ),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(historyProvider.notifier)
                  .updateAlias(index, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text(
              '저장',
              style: TextStyle(color: AppColors.textPrimary),
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

    // myFace 는 source 와 무관한 single-pick — SliverAppBar 헤더 1곳에서
    // 두 탭이 공유. _buildList 내부에서 따로 계산하지 않는다.
    FaceReadingReport? myFace;
    for (final r in history) {
      if (r.isMyFace) {
        myFace = r;
        break;
      }
    }
    final hasMyFace = myFace != null;

    return Scaffold(
      backgroundColor: Colors.white,
      body: NestedScrollView(
        headerSliverBuilder: (ctx, innerBoxIsScrolled) => [
          SliverOverlapAbsorber(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
            sliver: SliverAppBar(
              pinned: true,
              // expandedHeight 는 SliverAppBar 의 total max extent — toolbar +
              // flexibleSpace + bottom(TabBar) 모두 포함. 따라서 프로필 영역만이
              // 아니라 TabBar 높이(kTextTabBarHeight=46)까지 더해야 한다.
              // 안 그러면 background 가 TabBar 아래로 클리핑되어 label 끼리 겹침.
              //
              // 프로필 슬롯 102px — Android 는 94 로도 충분했으나 iPhone 의
              // safe-area·FlexibleSpaceBar 계산 차이로 inner Column 이 2.5px
              // overflow. 양 플랫폼 동일 layout 유지를 위해 8px 여유 추가.
              expandedHeight: kToolbarHeight + 102 + kTextTabBarHeight,
              title: const Text('관상'),
              actions: [
                IconButton(
                  icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
                  onPressed: () => _showInfoDialog(context),
                ),
              ],
              // DESIGN.md §3.7 — expanded 상태에서만 프로필 보임,
              // 스크롤 시 background 가 fade 되며 condensed 상태에서는 title 만 남음.
              // background 는 expandedHeight 전체에 깔리므로 위로 toolbar,
              // 아래로 TabBar 만큼 padding 빼서 프로필이 두 chrome 사이에만 배치되게.
              flexibleSpace: FlexibleSpaceBar(
                collapseMode: CollapseMode.parallax,
                background: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(
                      top: kToolbarHeight,
                      bottom: kTextTabBarHeight,
                    ),
                    child: _MyProfileHeader(myFace: myFace),
                  ),
                ),
              ),
              bottom: TabBar(
                controller: tabController,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textHint,
                indicatorColor: AppColors.textPrimary,
                tabs: [
                  const Tab(text: '카메라'),
                  const Tab(text: '앨범'),
                  if (hasBookmarks) const Tab(text: '북마크'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: tabController,
          children: [
            _buildList(history, const [AnalysisSource.camera], hasMyFace),
            _buildList(history, const [AnalysisSource.album], hasMyFace),
            if (hasBookmarks)
              _buildList(history, const [AnalysisSource.received], hasMyFace),
          ],
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
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyStatePlaceholder(
                  icon: FontAwesomeIcons.clockRotateLeft,
                  title: '분석 기록이 없습니다',
                  detail: '홈 탭 이동 후 관상을 분석해 보세요',
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
                      source: groups[gi].$1,
                      count: groups[gi].$2.length,
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

class _ProfileHintCard extends StatelessWidget {
  const _ProfileHintCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const FaIcon(
            FontAwesomeIcons.lightbulb,
            color: AppColors.gold,
            size: 18,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '더보기 메뉴 (점3개) 버튼을 누르고, 내 관상을 설정하면 다른 사람과 나와의 궁합을 분석해 볼 수 있어요',
              style: AppText.caption.copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('💕', style: AppText.hint.copyWith(fontSize: 22)),
        ],
      ),
    );
  }
}

class _RecentListHeader extends StatelessWidget {
  final _SortOrder order;
  final ValueChanged<_SortOrder> onChanged;
  final AnalysisSource source;
  final int count;
  final bool showSortToggle;

  const _RecentListHeader({
    required this.order,
    required this.onChanged,
    required this.source,
    required this.count,
    this.showSortToggle = true,
  });

  String get _label => switch (source) {
    AnalysisSource.camera => '카메라로 분석한 관상',
    AnalysisSource.album => '앨범사진으로 분석한 관상',
    AnalysisSource.received => '받은 카드',
  };

  @override
  Widget build(BuildContext context) {
    // received section 에만 count 노출 — viral funnel UX: 받은 카드 갯수를
    // 사용자가 한 눈에 인지하도록.
    final text = source == AnalysisSource.received
        ? '$_label ($count)'
        : _label;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          text,
          style: AppText.sectionTitle.copyWith(fontWeight: FontWeight.w700),
        ),
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
