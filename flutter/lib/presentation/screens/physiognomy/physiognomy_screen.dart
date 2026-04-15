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

  /// 얼굴형 분류 — 4축 composite score 기반
  ///
  /// 초기엔 `faceAspectRatio` 단독 → 측정 노이즈 하나로 분류가 뒤집혔음.
  /// 이후 `taper`, `gonial` 추가 → 그래도 bone 기반이라 이수지처럼
  /// "볼살/턱살로 퍼진 둥근 얼굴"이 표준형으로 오분류됨.
  ///
  /// 결정적 개선: **`lowerFaceFullness`** 추가 (피부 외곽선에서 측정).
  /// 골격이 아니라 실제 얼굴 contour의 하단부 폭을 평균내므로 볼살·턱살·jowl
  /// 이 있으면 즉시 반영됨 → 이수지/IU 구분의 가장 강한 신호가 됨.
  ///
  ///   widthScore =
  ///      1.0·(-aspectZ)     (세로-가로 bounding-box 비율)
  ///    + 1.0·taperZ         (bone gonion 기반 테이퍼)
  ///    + 2.0·lowerFullnessZ (피부 외곽선 기반 하단 풍만도 — 가장 강한 신호)
  ///    + 0.5·gonialZ        (하악각 — 약한 보조신호)
  ///
  /// Threshold ±2.5 는 "다축 합치" 요건.
  String _faceShape() {
    // 구버전 Report(히스토리)는 새 메트릭이 없으므로 모두 null-safe 하게 읽음.
    final aspect = report.metrics['faceAspectRatio'];
    final taper = report.metrics['faceTaperRatio'];
    final fullness = report.metrics['lowerFaceFullness'];
    final gonial = report.metrics['gonialAngle'];

    final aspectZ = aspect?.zScore ?? 0.0;
    final taperZ = taper?.zScore ?? 0.0;
    final fullnessZ = fullness?.zScore ?? 0.0;
    final gonialZ = gonial?.zScore ?? 0.0;

    // widthScore: 높을수록 가로로 넓은 (round), 낮을수록 세로로 긴 (long)
    final contribAspect = -aspectZ * 1.0;
    final contribTaper = taperZ * 1.0;
    final contribFullness = fullnessZ * 2.0; // 결정적 축 — 피부 외곽선 기반
    final contribGonial = gonialZ * 0.5;
    final widthScore =
        contribAspect + contribTaper + contribFullness + contribGonial;

    const double threshold = 2.5;
    final String label;
    final String reason;
    if (widthScore > threshold) {
      label = '가로로 넓은 얼굴형';
      reason =
          'widthScore=${widthScore.toStringAsFixed(2)} > +$threshold (다축 합치)';
    } else if (widthScore < -threshold) {
      label = '세로로 긴 얼굴형';
      reason =
          'widthScore=${widthScore.toStringAsFixed(2)} < -$threshold (다축 합치)';
    } else {
      label = '표준 얼굴형';
      reason = '|widthScore|=${widthScore.abs().toStringAsFixed(2)} ≤ $threshold';
    }

    String rawStr(dynamic m, {int digits = 4}) =>
        m == null ? '(missing)' : (m.rawValue as double).toStringAsFixed(digits);

    debugPrint('══════════ [FACE SHAPE] ══════════');
    debugPrint(
        '  gender=${report.gender.name} ethnicity=${report.ethnicity.name}');
    debugPrint(
        '  faceAspectRatio:   raw=${rawStr(aspect)} z=${aspectZ.toStringAsFixed(4)}  contrib=${contribAspect.toStringAsFixed(3)}');
    debugPrint(
        '  faceTaperRatio:    raw=${rawStr(taper)} z=${taperZ.toStringAsFixed(4)}  contrib=${contribTaper.toStringAsFixed(3)}');
    debugPrint(
        '  lowerFaceFullness: raw=${rawStr(fullness)} z=${fullnessZ.toStringAsFixed(4)}  contrib=${contribFullness.toStringAsFixed(3)}  ★');
    debugPrint(
        '  gonialAngle:       raw=${rawStr(gonial, digits: 2)}  z=${gonialZ.toStringAsFixed(4)}  contrib=${contribGonial.toStringAsFixed(3)}');
    debugPrint(
        '  widthScore = ${widthScore.toStringAsFixed(3)}  (+=가로 -=세로)');
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

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, color: AppTheme.border, size: 64),
            const SizedBox(height: 16),
            Text('분석 기록이 없습니다',
                style: TextStyle(color: AppTheme.textHint, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
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
