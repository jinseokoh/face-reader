import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:face_reader/presentation/screens/home/report_page.dart';
import 'package:face_reader/presentation/widgets/compact_snack_bar.dart';
import 'package:face_reader/presentation/widgets/physiognomy_info_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

// 화면-국지 팔레트 — DESIGN.md §2.4 (file-local 격리).
// 본 화면은 AppColors 의 gold / goldDim / goldSoft / surface / border / textHint
// 만으로 충분 — file-local 컬러 상수 없음. 프로필 헤더는 DESIGN.md §3.7
// (Integrated sliver header) 에 따라 AppColors 만 사용.

String _faceShapeLabelKo(String? mlLabel) {
  const labelMap = {
    'Heart': '하트형',
    'Oblong': '세로로 긴 얼굴형',
    'Oval': '계란형',
    'Round': '둥근 얼굴형',
    'Square': '각진 얼굴형',
  };
  if (mlLabel == null) return '내 얼굴';
  return labelMap[mlLabel] ?? mlLabel;
}

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
    final displayName = report.alias ?? _faceShape();
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportPage(report: report),
                  ),
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
                  child: Row(
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
                                    displayName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.sectionTitle.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isMyFace) ...[
                                  const SizedBox(width: AppSpacing.xs),
                                  const Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: AppColors.gold,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${report.ethnicity.labelKo} · '
                              '${report.ageGroup.labelKo} ${report.gender.labelKo}',
                              style: AppText.caption.copyWith(
                                color: AppColors.textHint,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(child: _buildArchetypeBadges()),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  timeago.format(report.timestamp,
                                      locale: 'ko'),
                                  style: AppText.hint,
                                ),
                              ],
                            ),
                          ],
                        ),
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
                icon: const Icon(Icons.more_vert,
                    color: AppColors.textHint),
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                onSelected: (value) {
                  if (value == 'rename') {
                    _showAliasDialog(context, ref, displayName);
                  } else if (value == 'setMyFace') {
                    _setMyFace(context, ref);
                  } else if (value == 'delete') {
                    _confirmDelete(context, ref, displayName);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem<String>(
                    value: 'setMyFace',
                    child: Text('내 프로필로 설정', style: AppText.body),
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
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        chip(primary,
            bg: AppColors.textPrimary.withValues(alpha: 0.08),
            fg: AppColors.textPrimary),
        chip('· $secondary',
            bg: Colors.transparent, fg: AppColors.textSecondary),
        if (special != null)
          chip(special,
              bg: Colors.indigo.shade50, fg: Colors.indigo.shade700),
      ],
    );
  }

  Widget _buildLeadingIcon() {
    // §3.7 — 내 관상 프로필 헤더 avatar 42px 와 동일 사이즈.
    const size = 42.0;
    if (report.thumbnailPath != null) {
      final file = File(report.thumbnailPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.file(
            file,
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(
        report.source == AnalysisSource.camera
            ? (report.gender == Gender.female ? Icons.face_3 : Icons.face_6)
            : Icons.photo_library,
        color: AppColors.textSecondary,
        size: 22,
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, WidgetRef ref, String displayName) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('삭제하시겠습니까?', style: AppText.modalTitle),
        content: Text(
          '"$displayName" 기록이 영구 삭제됩니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
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
            child: const Text('삭제',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }

  /// 얼굴형 분류 — 우선순위:
  ///   1) TFLite 28-feature MLP (76.9% test acc, Kaggle niten19 N=5000)
  ///      → report.faceShapeLabel ∈ {Heart, Oblong, Oval, Round, Square}
  ///   2) 실패 시 legacy 2-stage LDA fallback (22장 학습, 3-class)
  ///
  /// Legacy LDA 주석 (fallback 경로):
  ///   Stage 1: faceTaperRatio > 0.78 → 가로로 넓은 얼굴형
  ///   Stage 2: LDA linear combination of aspect/gonial/upper → long vs standard
  String _faceShape() {
    // Preferred path: ML classifier output stamped at analysis time.
    final mlLabel = report.faceShapeLabel;
    if (mlLabel != null) {
      final korean = _faceShapeLabelKo(mlLabel);
      final conf = report.faceShapeConfidence;
      debugPrint('══════════ [FACE SHAPE — ML] ══════════');
      debugPrint('  label=$mlLabel ($korean) '
          'confidence=${conf?.toStringAsFixed(3) ?? "n/a"}');
      debugPrint('═══════════════════════════════════════');
      return korean;
    }
    return _faceShapeLegacyLda();
  }

  /// Legacy 3-class LDA fallback. Used only when the ML classifier did not run
  /// (old Hive reports, asset load failure, missing metric). Preserved as a
  /// safety net during ML rollout.
  String _faceShapeLegacyLda() {
    // 구버전 Report(히스토리)는 새 메트릭이 없으므로 null-safe.
    final aspect = report.metrics['faceAspectRatio'];
    final taper = report.metrics['faceTaperRatio'];
    final gonial = report.metrics['gonialAngle'];
    final upper = report.metrics['upperFaceRatio'];

    final aspectRaw = aspect?.rawValue ?? 0.0;
    final taperRaw = taper?.rawValue ?? 0.0;
    final gonialRaw = gonial?.rawValue ?? 0.0;
    final upperRaw = upper?.rawValue ?? 0.0;

    // Stage 1: wide 탐지 (학습셋 기반 single-threshold rule).
    // Python 학습 threshold=0.7985 였으나, device single-frame 노이즈로
    // 동일인 프레임 간 taper 편차 ±0.04 관측 → 0.78로 완화 (device 검증).
    const double kWideTaperThreshold = 0.78;

    // Stage 2: long vs standard (unstandardized LDA coefficients on raw values).
    // 학습셋 분리: long range=[+1.28, +11.55], standard range=[-11.37, -1.19].
    // Intercept -222.52(Python) → -245 (Flutter aspect 체계 편향 +0.13 보상,
    // 150.88 × 0.13 ≈ 20 만큼 아래로 shift).
    const double kS2AspectCoef = 150.8780;
    const double kS2GonialCoef = -0.4313;
    const double kS2UpperCoef = 309.9574;
    const double kS2Intercept = -245.0;

    final String label;
    final String reason;
    final double stage2 = kS2AspectCoef * aspectRaw +
        kS2GonialCoef * gonialRaw +
        kS2UpperCoef * upperRaw +
        kS2Intercept;

    if (taperRaw > kWideTaperThreshold) {
      label = '가로로 넓은 얼굴형';
      reason = 'faceTaperRatio=${taperRaw.toStringAsFixed(4)} > '
          '$kWideTaperThreshold (stage 1)';
    } else if (stage2 > 0) {
      label = '세로로 긴 얼굴형';
      reason = 'stage2=${stage2.toStringAsFixed(2)} > 0 (stage 2 — long)';
    } else {
      label = '표준 얼굴형';
      reason = 'stage2=${stage2.toStringAsFixed(2)} ≤ 0 (stage 2 — standard)';
    }

    String rawStr(dynamic m, {int digits = 4}) =>
        m == null ? '(missing)' : (m.rawValue as double).toStringAsFixed(digits);

    debugPrint('══════════ [FACE SHAPE] ══════════');
    debugPrint(
        '  gender=${report.gender.name} ethnicity=${report.ethnicity.name}');
    debugPrint('  faceAspectRatio:   raw=${rawStr(aspect)}');
    debugPrint(
        '  faceTaperRatio:    raw=${rawStr(taper)}  (stage1 threshold=$kWideTaperThreshold)');
    debugPrint('  gonialAngle:       raw=${rawStr(gonial, digits: 2)}');
    debugPrint('  upperFaceRatio:    raw=${rawStr(upper)}');
    debugPrint('  stage2Score = ${stage2.toStringAsFixed(3)} '
        '(+=long, −=standard; neutral if stage1 fires)');
    debugPrint('  decision: $reason → "$label"');
    debugPrint('═══════════════════════════════════');
    return label;
  }

  void _setMyFace(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).setMyFace(index);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '내 관상을 지정했습니다'),
    );
  }

  void _showAliasDialog(
      BuildContext context, WidgetRef ref, String currentName) {
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
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(historyProvider.notifier)
                  .updateAlias(index, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('저장',
                style: TextStyle(color: AppColors.textPrimary)),
          ),
        ],
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
        : '나의 얼굴을 아래 리스트에서 선택해 주세요';
    final captionText = isSet
        ? (mf.alias ?? _faceShapeLabelKo(mf.faceShapeLabel))
        : '선택해야 다른 사람과의 궁합을 볼 수 있어요';

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
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
                Text(
                  '내 관상 프로필',
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  titleText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.subTitle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  captionText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.hint,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final FaceReadingReport? myFace;

  const _HeaderAvatar({required this.myFace});

  @override
  Widget build(BuildContext context) {
    // §3.7 — 다크 hero 의 84px 절반.
    const size = 42.0;
    Widget inner = const _HeaderAvatarPlaceholder();
    final thumb = myFace?.thumbnailPath;
    if (thumb != null) {
      final file = File(thumb);
      if (file.existsSync()) {
        inner = Image.file(file, width: size, height: size, fit: BoxFit.cover);
      }
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
        child: Icon(Icons.person, size: 22, color: AppColors.textHint),
      ),
    );
  }
}

enum _SortOrder {
  newest('최신순'),
  oldest('오래된순');

  const _SortOrder(this.label);
  final String label;
}

class _RecentListHeader extends StatelessWidget {
  final _SortOrder order;
  final ValueChanged<_SortOrder> onChanged;

  const _RecentListHeader({required this.order, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          '최근 분석한 사진',
          style: AppText.sectionTitle.copyWith(fontWeight: FontWeight.w700),
        ),
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
              const Icon(Icons.keyboard_arrow_down,
                  size: 16, color: AppColors.textHint),
            ],
          ),
        ),
      ],
    );
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
          const Icon(Icons.lightbulb_outline, color: AppColors.gold, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              '내 프로필을 설정하면 다른 사진들과의\n궁합, 관계 분석을 볼 수 있어요',
              style: AppText.caption.copyWith(
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

class _PhysiognomyScreenState extends ConsumerState<PhysiognomyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  _SortOrder _sortOrder = _SortOrder.newest;

  @override
  Widget build(BuildContext context) {
    // Only react to actual provider changes (e.g. external selectTab calls
    // from album_preview after analysis). Avoid forcing on every rebuild.
    ref.listen<int>(historyTabProvider, (prev, next) {
      if (_tabController.index != next) {
        _tabController.animateTo(next);
      }
    });
    final history = ref.watch(historyProvider);

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
              expandedHeight: kToolbarHeight + 92 + kTextTabBarHeight,
              title: const Text('관상'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.info_outline),
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
                controller: _tabController,
                labelColor: AppColors.textPrimary,
                unselectedLabelColor: AppColors.textHint,
                indicatorColor: AppColors.textPrimary,
                tabs: const [
                  Tab(text: '카메라'),
                  Tab(text: '앨범'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildList(history, AnalysisSource.camera, hasMyFace),
            _buildList(history, AnalysisSource.album, hasMyFace),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: ref.read(historyTabProvider),
    );
    // Sync tab changes back into the provider so external updates
    // (e.g. alias rename rebuild) don't reset the tab.
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging &&
          ref.read(historyTabProvider) != _tabController.index) {
        ref
            .read(historyTabProvider.notifier)
            .selectTab(_tabController.index);
      }
    });
  }

  Widget _buildList(
      List<FaceReadingReport> history, AnalysisSource source, bool hasMyFace) {
    final filtered = <(int, FaceReadingReport)>[];
    for (var i = 0; i < history.length; i++) {
      if (history[i].source == source) filtered.add((i, history[i]));
    }
    filtered.sort((a, b) {
      final at = a.$2.timestamp;
      final bt = b.$2.timestamp;
      return _sortOrder == _SortOrder.newest
          ? bt.compareTo(at)
          : at.compareTo(bt);
    });

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
            if (filtered.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.huge),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.history,
                            color: AppColors.border, size: 64),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          '분석 기록이 없습니다',
                          style: AppText.sectionTitle.copyWith(
                            fontWeight: FontWeight.w400,
                            color: AppColors.textHint,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        const Text(
                          '아래로 당겨 새 공식으로 재계산',
                          style: AppText.hint,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                    AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                sliver: SliverToBoxAdapter(
                  child: _RecentListHeader(
                    order: _sortOrder,
                    onChanged: (v) => setState(() => _sortOrder = v),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                sliver: SliverList.builder(
                  itemCount: filtered.length,
                  itemBuilder: (ctx, i) {
                    final (origIdx, report) = filtered[i];
                    return _PhysiognomyItem(
                      report: report,
                      index: origIdx,
                      source: source,
                    );
                  },
                ),
              ),
              if (!hasMyFace)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.xs,
                      AppSpacing.lg, AppSpacing.xxl),
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
    print('[PhysiognomyScreen] pull-to-refresh reloadFromHive returned: '
        'state before=$before → after=$after');
    // 시각적 feedback 을 위해 최소 latency 유지.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '새 공식으로 재계산 완료'),
    );
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
}
