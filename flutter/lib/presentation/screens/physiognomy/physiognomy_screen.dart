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
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:top_snackbar_flutter/top_snack_bar.dart';

// 화면-국지 팔레트 — DESIGN.md §2.4 (file-local 격리).
// AppColors 에 이미 있는 gold / goldDim / goldSoft 는 직접 참조하고,
// 이 화면에서만 쓰는 다크 hero / 알약 / 뱃지 / placeholder 톤만 여기 둔다.
const _kHeroBgTop = Color(0xFF2A2418);
const _kHeroBgBottom = Color(0xFF1F1812);
const _kBtnFgIdle = Color(0xFF5C4A26);
const _kBtnBgActive = Color(0xFFE8D7B0);
const _kBtnFgActive = Color(0xFF3D2F18);
const _kRecBadgeBg = Color(0xFFB8956A);
const _kAvatarFill = Color(0xFF1A1410);
const _kAvatarIcon = Color(0xFF6E6354);

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
  final bool isTopRecommended;

  const _PhysiognomyItem({
    required this.report,
    required this.index,
    required this.source,
    this.isTopRecommended = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = report.alias ?? _faceShape();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Slidable(
        key: ValueKey(report.supabaseId ?? index),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            _slidableAction(
              icon: Icons.delete,
              label: '삭제',
              bg: Colors.red.shade600,
              onPressed: () => _delete(context, ref),
            ),
          ],
        ),
        child: Stack(
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
                  padding: const EdgeInsets.all(AppSpacing.md),
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
                            GestureDetector(
                              onTap: () => _showAliasDialog(
                                  context, ref, displayName),
                              child: Text(
                                displayName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.sectionTitle
                                    .copyWith(fontWeight: FontWeight.w700),
                              ),
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
                            _buildArchetypeBadges(),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _buildRightColumn(context, ref, displayName),
                    ],
                  ),
                ),
              ),
            ),
            if (isTopRecommended)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: const BoxDecoration(
                    color: _kRecBadgeBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg),
                      bottomRight: Radius.circular(AppRadius.md),
                    ),
                  ),
                  child: Text(
                    '추천',
                    style: AppText.hint.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightColumn(
      BuildContext context, WidgetRef ref, String displayName) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              timeago.format(report.timestamp, locale: 'ko'),
              style: AppText.hint,
            ),
            InkWell(
              onTap: () => _showAliasDialog(context, ref, displayName),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(AppSpacing.xs),
                child: Icon(Icons.more_vert,
                    size: 18, color: AppColors.textHint),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _ProfileSetButton(
          isActive: report.isMyFace,
          onTap: report.isMyFace ? null : () => _setMyFace(context, ref),
        ),
      ],
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
    if (report.thumbnailPath != null) {
      final file = File(report.thumbnailPath!);
      if (file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.file(
            file,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(
        report.source == AnalysisSource.camera
            ? (report.gender == Gender.female ? Icons.face_3 : Icons.face_6)
            : Icons.photo_library,
        color: AppColors.textSecondary,
        size: 32,
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).remove(index);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '삭제되었습니다'),
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

  Widget _slidableAction({
    required IconData icon,
    required String label,
    required Color bg,
    required VoidCallback onPressed,
  }) {
    return CustomSlidableAction(
      onPressed: (_) => onPressed(),
      backgroundColor: bg,
      foregroundColor: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: AppText.hint.copyWith(color: Colors.white)),
        ],
      ),
    );
  }
}

/// 알약 형태의 명시적 "내 프로필로 설정" / "내 프로필" tappable label.
/// Material+InkWell 조합으로, 버튼 위젯 family 가 아닌 surface element.
class _ProfileSetButton extends StatelessWidget {
  final bool isActive;
  final VoidCallback? onTap;

  const _ProfileSetButton({required this.isActive, this.onTap});

  @override
  Widget build(BuildContext context) {
    final bg = isActive ? _kBtnBgActive : AppColors.goldSoft;
    final fg = isActive ? _kBtnFgActive : _kBtnFgIdle;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isActive) ...[
                Icon(Icons.check, size: 14, color: fg),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                isActive ? '내 프로필' : '내 프로필로\n설정',
                textAlign: TextAlign.center,
                style: AppText.hint.copyWith(
                  fontWeight: FontWeight.w600,
                  color: fg,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyProfileHeroCard extends StatelessWidget {
  final FaceReadingReport? myFace;

  const _MyProfileHeroCard({required this.myFace});

  @override
  Widget build(BuildContext context) {
    final mf = myFace;
    final isSet = mf != null;
    // State B 타이틀: "30대 여성 동아시아인" — 나이대 · 성별 · 인종 순.
    // 분류된 얼굴형(또는 사용자 별칭)은 subtitle 로 한 단계 내림.
    final titleText = isSet
        ? '${mf.ageGroup.labelKo} ${mf.gender.labelKo} '
            '${mf.ethnicity.labelKo}'
        : '나의 얼굴을 아래 리스트에서\n선택해 주세요.';
    final captionText = isSet
        ? (mf.alias ?? _faceShapeLabelKo(mf.faceShapeLabel))
        : '선택해야 다른 사람과의 궁합을 볼 수 있어요';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_kHeroBgTop, _kHeroBgBottom],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '내 관상 프로필 ✨',
                  style: AppText.caption.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.gold,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  titleText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.modalTitle.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  captionText,
                  style: AppText.hint.copyWith(color: AppColors.goldDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          _HeroAvatar(myFace: myFace),
        ],
      ),
    );
  }
}

class _HeroAvatar extends StatelessWidget {
  final FaceReadingReport? myFace;

  const _HeroAvatar({required this.myFace});

  @override
  Widget build(BuildContext context) {
    const size = 84.0;
    Widget inner = const _HeroAvatarPlaceholder();
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

class _HeroAvatarPlaceholder extends StatelessWidget {
  const _HeroAvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _kAvatarFill,
      child: const Center(
        child: Icon(Icons.person, size: 48, color: _kAvatarIcon),
      ),
    );
  }
}

class _RecentListHeader extends StatelessWidget {
  const _RecentListHeader();

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
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '최신순',
              style: AppText.caption.copyWith(color: AppColors.textHint),
            ),
            const Icon(Icons.keyboard_arrow_down,
                size: 16, color: AppColors.textHint),
          ],
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

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('관상'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showInfoDialog(context),
          ),
        ],
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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildList(history, AnalysisSource.camera),
          _buildList(history, AnalysisSource.album),
        ],
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

  Widget _buildList(List<FaceReadingReport> history, AnalysisSource source) {
    final filtered = <(int, FaceReadingReport)>[];
    for (var i = 0; i < history.length; i++) {
      if (history[i].source == source) filtered.add((i, history[i]));
    }
    // myFace 는 source 와 무관한 single-pick — 두 탭의 hero 카드 모두에 동일 반영.
    FaceReadingReport? myFace;
    for (final r in history) {
      if (r.isMyFace) {
        myFace = r;
        break;
      }
    }
    final hasMyFace = myFace != null;

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: AppColors.textPrimary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            sliver:
                SliverToBoxAdapter(child: _MyProfileHeroCard(myFace: myFace)),
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
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.xxl, AppSpacing.lg, AppSpacing.md),
              sliver: SliverToBoxAdapter(child: _RecentListHeader()),
            ),
            SliverPadding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              sliver: SliverList.builder(
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final (origIdx, report) = filtered[i];
                  return _PhysiognomyItem(
                    report: report,
                    index: origIdx,
                    source: source,
                    isTopRecommended: i == 0,
                  );
                },
              ),
            ),
            if (!hasMyFace)
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.xxl),
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
