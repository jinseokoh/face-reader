import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/widgets/cdn_thumbnail.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';
import 'package:facely/presentation/widgets/credits_empty_state.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:facely/presentation/widgets/face_scan_pill.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/physiognomy_info_dialog.dart';
import 'package:facely/presentation/widgets/sort_selector.dart';
import 'package:facely/presentation/widgets/source_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

const List<String> _kCreditsAlbum = [
  ..._kCreditsIntro,
  '관상을 앨범으로 등록하면',
  '이곳에 저장됩니다.',
];

const List<String> _kCreditsBookmark = [
  ..._kCreditsIntro,
  '공유받은 상대방의 관상 카드를',
  '북마크하면 이곳에 저장됩니다.',
];

const List<String> _kCreditsCamera = [
  ..._kCreditsIntro,
  '관상을 카메라로 등록하면',
  '이곳에 저장됩니다.',
];

/// 미등록 첫 화면의 크레딧 문구 — 빈 여백을 채운다.
/// 줄바꿈은 이 목록 그대로 유지된다 ([CreditsEmptyState]).
///
/// 세 탭이 공유하는 앞부분. 뒤에 탭별 두 줄이 붙는다 — 크레딧이 그 탭에
/// 무엇이 쌓이는지로 끝나야 빈 화면이 안내 역할을 한다.
const List<String> _kCreditsIntro = [
  '관상은 미래의 운명을',
  '단정짓는 점술이 아니라,',
  '내 삶의 모습을 살피고',
  '그 안에 비친 나 자신을',
  '돌아보게 하는 전통적',
  '오랜 지혜입니다.\n',
];

const String _kEmptyAfterMyFace = '계속해서 다른 사람의 관상도 볼 수 있어요.';
/// 크레딧 뒤 일러스트 아래 문구. 카메라·앨범은 내 관상 등록 전후로 가리키는
/// 곳이 다르다 — 등록 전엔 나를, 등록 후엔 상대를 추가하라고 말한다.
const String _kEmptyBeforeMyFace = '내 관상 부터 볼 수 있어요.';

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
            // 내 관상 카드는 '내 관상' gold pill 과 같은 가족의 chrome —
            // goldSoft 옅은 tint 바탕 + gold 1px border 로 리스트에서 즉시
            // 구분 (원색 goldSoft 는 카드 면적에선 과함 — alpha 로 눌러쓴다).
            color: isMyFace
                ? AppColors.goldSoft.withValues(alpha: 0.35)
                : AppColors.surface,
            // 궁합 카드와 동일한 1px border (§0.0.1 같은 역할 = 같은 chrome).
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              side: BorderSide(
                color: isMyFace ? AppColors.gold : AppColors.border,
              ),
            ),
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
                } else if (value == 'recapture') {
                  startMyFaceCapture(context, ref);
                } else if (value == 'delete') {
                  _confirmDelete(context, ref);
                }
              },
              // 내 관상 지정/해제 메뉴 없음 — 로컬 전용 지정/해제는 서버
              // is_my_face 와 어긋나던 funnel 이라 제거. 교체는 [다시 찍기]
              // (고정 row 덮어쓰기 — 서버 row·케미 슬롯·공유 링크 유지).
              itemBuilder: (ctx) => [
                if (isMyFace)
                  const PopupMenuItem<String>(
                    value: 'recapture',
                    child: Text('내 관상 다시 찍기', style: AppText.body),
                  ),
                const PopupMenuItem<String>(
                  value: 'rename',
                  child: Text('별칭 변경', style: AppText.body),
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
    // 1순위 로컬 파일 → 2순위 CDN(thumbnailKey) → 소스 아이콘 fallback.
    // 공유받은 카드·로그인 rehydrate 복원 카드는 thumbnailPath=null 이지만
    // thumbnailKey 가 있어 CDN 으로 실제 얼굴을 띄운다 (궁합 아바타와 동일).
    // border 는 source 규칙 (sourceBorderColor — 카메라 gold / 앨범 lightGray).
    const size = AppAvatar.md;
    Widget inner = _sourceIconAvatar(report, size);
    final file = ThumbnailPaths.cacheFileSync(report.thumbnailKey);
    final cdn = ThumbnailPaths.cdnUrl(report.thumbnailKey);
    if (file != null && file.existsSync()) {
      inner = Image.file(file, width: size, height: size, fit: BoxFit.cover);
    } else if (cdn != null) {
      inner = cdnThumbnail(
        url: cdn,
        size: size,
        fallback: _sourceIconAvatar(report, size),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: sourceBorderColor(report.source), width: 1.5),
      ),
      child: ClipOval(child: inner),
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
            child: Text(
              '삭제',
              style: AppText.body.copyWith(color: AppColors.danger),
            ),
          ),
        ],
      ),
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
        title: const Text('별칭 변경', style: AppText.modalTitle),
        content: TextField(
          controller: controller,
          maxLength: 64,
          autofocus: true,
          decoration: const InputDecoration(hintText: '별칭을 입력하세요'),
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

  Widget _sourceIconAvatar(FaceReadingReport report, double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: AppColors.border,
        shape: BoxShape.circle,
      ),
      // FaIcon 은 원본 Icon 에서 SizedBox·Center 를 걷어낸 위젯이라, 크기가
      // 정해진 부모의 tight 제약을 그대로 받으면 글리프가 좌상단에 그려진다.
      // 원형 아바타 폴백은 Center 로 감싸는 것이 전 탭 공통 (team_reveal 동일).
      child: Center(
        child: FaIcon(
          switch (report.source) {
            AnalysisSource.camera => FontAwesomeIcons.faceSmile,
            AnalysisSource.album => FontAwesomeIcons.images,
            AnalysisSource.received => FontAwesomeIcons.shareNodes,
          },
          color: AppColors.textSecondary,
          size: 18,
        ),
      ),
    );
  }
}

class _PhysiognomyScreenState extends ConsumerState<PhysiognomyScreen>
    with SingleTickerProviderStateMixin {
  // 카메라/앨범/공유받음 3탭 고정 (2026-07-12 — 북마크 유무 2↔3 동적 폐기).
  TabController? _tabController;
  _SortOrder _sortOrder = _SortOrder.newest;

  // 최초 노출 시 1회 — 개수가 가장 많은 내부 탭을 기본 선택 (궁합·케미와
  // 동일 규칙, 빈 탭부터 보여주지 않기). 이후엔 사용자의 명시적 선택과
  // 분석 후 이동(info_confirm)이 우선이라 다시 강제하지 않는다.
  bool _appliedInitialTab = false;

  @override
  Widget build(BuildContext context) {
    // Only react to actual provider changes (e.g. external selectTab calls
    // from album_preview after analysis). Avoid forcing on every rebuild.
    final history = ref.watch(historyProvider);
    // 카메라/앨범/공유받음 3탭 고정 — 공유받음 0개여도 노출 (2↔3 동적 재생성
    // 폐기. 구조는 고정, 빈 탭은 (0) 카운트 + 빈 상태가 기능을 학습시킨다).
    _syncTabController(3);
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

    // 최초 노출 기본 탭 = 개수가 가장 많은 소스 (동률은 앞 탭). 히스토리
    // hydrate 후 1회, provider 가 아직 초기값(0)일 때만 — 이미 다른 흐름이
    // 탭을 정했으면 존중.
    if (!_appliedInitialTab && hasMyFace) {
      _appliedInitialTab = true;
      final counts = [
        history.where((r) => r.source == AnalysisSource.camera).length,
        history.where((r) => r.source == AnalysisSource.album).length,
        history.where((r) => r.source == AnalysisSource.received).length,
      ];
      var best = 0;
      for (var i = 1; i < counts.length; i++) {
        if (counts[i] > counts[best]) best = i;
      }
      if (best != 0 && ref.read(historyTabProvider) == 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(historyTabProvider.notifier).selectTab(best);
          }
        });
      }
    }

    // 헤더는 어차피 고정(pinned)이므로 궁합·케미 탭과 동일한 일반 AppBar +
    // TabBarView 구조 — 탭별 RefreshIndicator 가 그대로 동작한다
    // (NestedScrollView 는 최상단 당김을 outer 가 흡수해 refresh 불가).
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        // 내 관상 프로필 슬롯 제거 (2026-06-12) — 등록 상태는 AppBar
        // pill 라벨이 전달하고, 리스트 카드의 gold '내 관상' 배지가
        // 식별을 맡는다. 헤더는 타이틀 + TabBar 만.
        title: const Text('관상'),
        actions: [
          // 미등록 = 내 관상 보기 / 등록 후 = 관상 보기.
          const FaceScanPill(),
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.circleInfo, size: 20),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
        // 궁합 탭과 동일 규칙 — 내부 탭은 내 관상 등록 후에만 나타난다.
        // 미등록 상태에선 탭 없이 단일 리스트 (카드별 SourceBadge 가
        // 소스를 전달). 탭 라벨엔 개수 노출 (스크롤 없이 존재 여부 인지).
        // 탭 구조는 내 관상 등록 여부와 무관하게 고정 — 케미 탭과 같은 원칙.
        // 등록 전후로 레이아웃이 통째로 바뀌면 사용자가 화면을 두 번 배우고,
        // 미등록이어도 북마크는 담을 수 있어 "내용은 있는데 탭은 없는" 상태가
        // 생긴다. 빈 탭은 감추는 대신 그 탭에 무엇이 쌓이는지 가르친다.
        bottom: TabBar(
          controller: tabController,
          labelColor: AppColors.textPrimary,
          unselectedLabelColor: AppColors.textHint,
          indicatorColor: AppColors.textPrimary,
          tabs: [
            Tab(
              text:
                  '카메라 '
                  '(${history.where((r) => r.source == AnalysisSource.camera).length})',
            ),
            Tab(
              text:
                  '앨범 '
                  '(${history.where((r) => r.source == AnalysisSource.album).length})',
            ),
            // 탭 이름은 '북마크' — 공유받은 카드 중 북마크로 담은
            // 것만 오는 보관함이라 동작·아이콘과 일치. 카드의
            // SourceBadge '공유받음' 은 출처 표기라 그대로.
            Tab(
              text:
                  '북마크 '
                  '(${history.where((r) => r.source == AnalysisSource.received).length})',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: tabController,
        children: [
          // 탭별 빈 상태 이미지 분리 — 케미 탭(laugh/shrug)과 같은 원칙:
          // 나란한 탭이 같은 그림이면 지루하다.
          _buildList(
            history,
            const [AnalysisSource.camera],
            tabIndex: 0,
            credits: _kCreditsCamera,
            description: '카메라로 찍은 사진으로 본 관상입니다.',
            emptyAsset: 'assets/images/emotion-namaste.png',
            emptyMessage: _kEmptyAfterMyFace,
            emptyMessageBefore: _kEmptyBeforeMyFace,
          ),
          _buildList(
            history,
            const [AnalysisSource.album],
            tabIndex: 1,
            credits: _kCreditsAlbum,
            description: '앨범 사진으로 본 관상입니다.',
            emptyAsset: 'assets/images/emotion-namaste.png',
            emptyMessage: _kEmptyAfterMyFace,
            emptyMessageBefore: _kEmptyBeforeMyFace,
          ),
          // 공유받음 — 상시 노출 (0개 포함). 빈 상태가 "공유받기" 라는 기능의
          // 존재를 학습시킨다 (구조 고정 원칙).
          _buildList(
            history,
            const [AnalysisSource.received],
            tabIndex: 2,
            credits: _kCreditsBookmark,
            description: '공유받아 북마크한 관상입니다.',
            emptyAsset: 'assets/images/emotion-namaste.png',
            emptyMessage: '전달받은 궁합은 이 곳에 북마크해 둘 수 있어요.',
          ),
        ],
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
    _syncTabController(3);
  }

  /// 한 tab 의 내용을 그린다. sources 는 그 tab 에서 보일 source list
  /// (카메라/앨범/공유받음 각 1개, 미등록 상태의 단일 리스트만 3개 합침).
  /// 모든 source 가 비어있으면 단일 empty state.
  Widget _buildList(
    List<FaceReadingReport> history,
    List<AnalysisSource> sources, {
    required int tabIndex,
    required List<String> credits,
    required String description,
    required String emptyAsset,
    required String emptyMessage,

    /// 내 관상 등록 **전**에 쓸 문구. null 이면 [emptyMessage] 를 그대로 쓴다
    /// (북마크 탭처럼 등록 여부와 무관한 경우).
    String? emptyMessageBefore,
  }) {
    // 리스트 하단의 등록 유도 카드 조건. 세 탭이 같은 history 를 보므로 여기서
    // 계산한다 — 호출부가 넘기면 세 곳이 같은 값을 되풀이할 뿐이다.
    final hasMyFace = history.any((r) => r.isMyFace);
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

    // 궁합·케미 탭과 동일 — 탭마다 RefreshIndicator 직결 (빈 탭도
    // AlwaysScrollableScrollPhysics 로 당김 가능).
    final scroll = RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.textPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (allEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              // 등록 후 세 탭의 빈 상태는 §3.8 일러스트 + 안내 한 줄이 즉시
              // 뜬다. 문구가 "버튼을 누르고 고르세요" 라는 행동 안내라,
              // 앞에 크레딧이 다 흘러갈 때까지 기다리면 안내가 안 된다.
              //
              // 미등록 첫 화면만 2단 연출 — 크레딧이 올라간 뒤 일러스트가
              // 떠오른다. 연출은 관상 탭이 실제로 열린 순간에 시작해야
              // 한다. 탭 셸이 IndexedStack 이라 이 화면은 앱을 켤 때 이미
              // 만들어져 있어, 만들어진 시점을 시작 신호로 쓸 수 없다.
              // 빈 탭은 2단 연출 — 크레딧이 올라간 뒤 일러스트와 안내가 뜬다.
              // 크레딧은 그 탭에 무엇이 쌓이는지로 끝나고, 뒤이어 뜨는 문구가
              // 그걸 어떻게 채우는지 말한다.
              //
              // 연출은 그 탭이 실제로 보이는 순간 시작해야 한다. 탭 셸이
              // IndexedStack 이고 TabBarView 도 이웃 탭을 미리 만들어 두므로
              // 만들어진 시점은 시작 신호가 될 수 없다 — 관상 탭이 선택됐고
              // 그 안에서 이 서브탭이 선택된 경우만 true 다.
              child: Consumer(
                builder: (ctx, ref, _) => CreditsEmptyState(
                  lines: credits,
                  asset: emptyAsset,
                  message: hasMyFace
                      ? emptyMessage
                      : (emptyMessageBefore ?? emptyMessage),
                  active:
                      ref.watch(selectedTabProvider) == kPhysiognomyTabIndex &&
                      ref.watch(historyTabProvider) == tabIndex,
                ),
              ),
            )
          else ...[
            for (var gi = 0; gi < groups.length; gi++)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  gi == 0 ? 0 : AppSpacing.xl,
                  AppSpacing.lg,
                  0,
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
    );
    if (allEmpty) return scroll;

    // 정렬 selector 는 스크롤 밖 고정(sticky) 바 — 아이템이 많아 스크롤이
    // 생겨도 항상 보인다 (궁합·케미 탭과 동일 패턴). 빈 탭엔 노출하지 않는다.
    return Column(
      children: [
        Padding(
          // selector 위 lg(16)/아래 md(12) — 기존 리스트 헤더와 동일 리듬.
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: SortSelector<_SortOrder>(
            value: _sortOrder,
            values: _SortOrder.values,
            labelOf: (o) => o.label,
            onChanged: (v) => setState(() => _sortOrder = v),
            description: description,
          ),
        ),
        Expanded(child: scroll),
      ],
    );
  }

  /// Pull-to-refresh: ① 서버 metrics 동기화 (교체·복원·삭제 반영, 비로그인
  /// 이면 skip) → ② 전체를 현재 엔진(weight matrix · rule · quantile) 으로
  /// 재계산. 새 공식과 다른 기기의 변경이 기존 리포트에 즉시 반영된다.
  Future<void> _handleRefresh() async {
    // ignore: avoid_print
    print('[PhysiognomyScreen] pull-to-refresh START');
    final before = ref.read(historyProvider).length;
    await ref.read(historyProvider.notifier).syncFromServer();
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
    showDialog<void>(
      context: context,
      builder: (ctx) => const PhysiognomyInfoDialog(),
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
      if (!c.indexIsChanging && ref.read(historyTabProvider) != c.index) {
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
      message: '내 관상 등록이 필요합니다.',
    );
  }
}

enum _SortOrder {
  newest('최신순'),
  oldest('오래된순');

  final String label;
  const _SortOrder(this.label);
}
