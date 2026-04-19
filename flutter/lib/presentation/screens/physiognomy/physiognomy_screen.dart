import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/presentation/providers/compat_albums_provider.dart';
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

class PhysiognomyScreen extends ConsumerStatefulWidget {
  const PhysiognomyScreen({super.key});

  @override
  ConsumerState<PhysiognomyScreen> createState() => _PhysiognomyScreenState();
}

class _PhysiognomyItem extends ConsumerWidget {
  final FaceReadingReport report;
  final int index;
  final AnalysisSource source;

  const _PhysiognomyItem({required this.report, required this.index, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final displayName = report.alias ?? _faceShape();

    // 내 얼굴이 history 어딘가에 설정되어 있어야만 궁합 보기 옵션을 노출.
    // 그리고 내 얼굴 항목 자체에는 궁합 보기 노출 안 함 (자기 자신과 페어링 불가).
    final hasMyFace = ref.watch(historyProvider).any(
        (r) => r.source == AnalysisSource.camera && r.isMyFace);
    final canShowCompat = hasMyFace && !report.isMyFace;

    // Slidable actions:
    //  - Camera tab + 내 얼굴 자체: 내 얼굴(재설정), 삭제
    //  - Camera tab + 다른 selfie + 내 얼굴 설정됨: 내 얼굴, 궁합 보기, 삭제
    //  - Camera tab + 다른 selfie + 내 얼굴 미설정: 내 얼굴, 삭제
    //  - Album tab + 내 얼굴 설정됨: 궁합 보기, 삭제
    //  - Album tab + 내 얼굴 미설정: 삭제만
    final actions = <Widget>[];
    if (source == AnalysisSource.camera) {
      actions.add(_slidableAction(
        icon: Icons.face,
        label: '내 관상',
        bg: Colors.green.shade600,
        onPressed: () => _setMyFace(context, ref),
      ));
    }
    if (canShowCompat) {
      actions.add(_slidableAction(
        icon: Icons.favorite,
        label: '궁합 보기',
        bg: Colors.indigo.shade600,
        onPressed: () => _openCompatibility(context, ref),
      ));
    }
    actions.add(_slidableAction(
      icon: Icons.delete,
      label: '삭제',
      bg: Colors.red.shade600,
      onPressed: () => _delete(context, ref),
    ));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(report.supabaseId ?? index),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: actions,
        ),
        child: Stack(
          children: [
            Material(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ReportPage(report: report),
                  ),
                ),
                onLongPress: () => _showBottomMenu(context, ref),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _buildLeadingIcon(),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _showAliasDialog(
                                        context, ref, displayName),
                                    child: Text(
                                      displayName,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(
                                      left: 8, right: 10),
                                  child: Text(
                                      timeago.format(report.timestamp,
                                          locale: 'ko'),
                                      style: TextStyle(
                                          color: AppTheme.textHint,
                                          fontSize: 13)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                                '${report.ethnicity.labelKo} · ${report.ageGroup.labelKo} ${report.gender.labelKo}',
                                style: TextStyle(
                                    color: AppTheme.textHint,
                                    fontSize: 13)),
                            const SizedBox(height: 6),
                            _buildArchetypeBadges(),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: AppTheme.textHint),
                    ],
                  ),
                ),
              ),
            ),
            if (report.isMyFace)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.green.shade600,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomRight: Radius.circular(10),
                    ),
                  ),
                  child: const Text('내 관상',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: TextStyle(
              color: fg, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      );
    }

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        chip(primary,
            bg: AppTheme.textPrimary.withValues(alpha: 0.08),
            fg: AppTheme.textPrimary),
        chip('· $secondary',
            bg: Colors.transparent, fg: AppTheme.textSecondary),
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
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            file,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
          ),
        );
      }
    }
    return Icon(
      report.source == AnalysisSource.camera
          ? (report.gender == Gender.female ? Icons.face_3 : Icons.face_6)
          : Icons.photo_library,
      color: AppTheme.textSecondary,
      size: 36,
    );
  }

  void _confirmDeleteWithCompatWarning(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('삭제 확인'),
        content: const Text(
            '이 인물과의 궁합 분석 항목도 함께 사라집니다. 정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: TextStyle(color: AppTheme.textHint)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _doDelete(context, ref);
            },
            child: Text('삭제', style: TextStyle(color: Colors.red.shade600)),
          ),
        ],
      ),
    );
  }

  void _delete(BuildContext context, WidgetRef ref) {
    // For any item (camera or album) already opted into compat: warn that the
    // compat row will also disappear.
    final uuid = report.supabaseId;
    if (uuid != null && ref.read(compatAlbumsProvider).contains(uuid)) {
      _confirmDeleteWithCompatWarning(context, ref);
      return;
    }
    _doDelete(context, ref);
  }

  void _doDelete(BuildContext context, WidgetRef ref) {
    // Purge any compat opt-in entry tied to this report's uuid (orphan
    // prevention) — applies to both camera and album sources.
    final uuid = report.supabaseId;
    if (uuid != null) {
      ref.read(compatAlbumsProvider.notifier).remove(uuid);
    }
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
      const labelMap = {
        'Heart': '하트형',
        'Oblong': '세로로 긴 얼굴형',
        'Oval': '계란형',
        'Round': '둥근 얼굴형',
        'Square': '각진 얼굴형',
      };
      final korean = labelMap[mlLabel] ?? mlLabel;
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

  void _openCompatibility(BuildContext context, WidgetRef ref) {
    final albumUuid = report.supabaseId;
    if (albumUuid == null) return;
    // Prerequisite: 카메라 탭에서 "내 얼굴"이 설정되어 있어야 궁합 화면이 렌더링됨.
    // 없으면 compatAlbums에 추가해도 궁합 탭은 "내 얼굴 먼저..." gate 메시지로
    // 막혀서 사용자에겐 "아무 일도 안 일어난" 것처럼 보임 → prerequisite 안내.
    final hasMyFace = ref.read(historyProvider).any(
        (r) => r.source == AnalysisSource.camera && r.isMyFace);
    if (!hasMyFace) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.info(
            message: '먼저 카메라 탭에서 내 얼굴을 분석하고 "내 얼굴"로 설정해주세요'),
      );
      return;
    }
    final already = ref.read(compatAlbumsProvider).contains(albumUuid);
    if (already) {
      showTopSnackBar(
        Overlay.of(context),
        CompactSnackBar.info(message: '이미 궁합 항목에 있습니다'),
      );
      return;
    }
    ref.read(compatAlbumsProvider.notifier).add(albumUuid);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '궁합 항목에 추가되었습니다'),
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
      BuildContext context, WidgetRef ref, String currentName) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('이름 변경'),
        content: TextField(
          controller: controller,
          maxLength: 64,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '이름을 입력하세요',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: TextStyle(color: AppTheme.textHint)),
          ),
          TextButton(
            onPressed: () {
              ref
                  .read(historyProvider.notifier)
                  .updateAlias(index, controller.text.trim());
              Navigator.pop(ctx);
            },
            child: Text('저장',
                style: TextStyle(color: AppTheme.textPrimary)),
          ),
        ],
      ),
    );
  }

  void _showBottomMenu(BuildContext context, WidgetRef ref) {
    final hasMyFace = ref.read(historyProvider).any(
        (r) => r.source == AnalysisSource.camera && r.isMyFace);
    final canShowCompat = hasMyFace && !report.isMyFace;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (source == AnalysisSource.camera)
              ListTile(
                leading: Icon(Icons.face, color: Colors.green.shade600),
                title: const Text('내 관상'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setMyFace(context, ref);
                },
              ),
            if (canShowCompat)
              ListTile(
                leading: Icon(Icons.favorite, color: Colors.indigo.shade600),
                title: const Text('궁합 보기'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCompatibility(context, ref);
                },
              ),
            ListTile(
              leading: Icon(Icons.delete, color: Colors.red.shade600),
              title: const Text('삭제'),
              onTap: () {
                Navigator.pop(ctx);
                _delete(context, ref);
              },
            ),
          ],
        ),
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
      borderRadius: BorderRadius.circular(14),
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
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
          labelColor: AppTheme.textPrimary,
          unselectedLabelColor: AppTheme.textHint,
          indicatorColor: AppTheme.textPrimary,
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
    // Sync user swipes back into the provider so external updates
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

    final child = filtered.isEmpty
        ? LayoutBuilder(
            builder: (ctx, constraints) => SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history, color: AppTheme.border, size: 64),
                      const SizedBox(height: 16),
                      Text('분석 기록이 없습니다',
                          style: TextStyle(
                              color: AppTheme.textHint, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('아래로 당겨 새 공식으로 재계산',
                          style: TextStyle(
                              color: AppTheme.textHint, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final (originalIndex, report) = filtered[index];
              return _PhysiognomyItem(
                report: report,
                index: originalIndex,
                source: source,
              );
            },
          );

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(),
      color: AppTheme.textPrimary,
      child: child,
    );
  }

  /// Pull-to-refresh: Hive capture 은 그대로, 해석만 현재 엔진(weight matrix ·
  /// rule · quantile) 으로 재계산. 새 공식이 기존 리포트에 즉시 반영된다.
  Future<void> _handleRefresh() async {
    ref.read(historyProvider.notifier).reloadFromHive();
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
