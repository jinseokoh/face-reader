import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(report.supabaseId ?? index),
        endActionPane: ActionPane(
          motion: const DrawerMotion(),
          children: [
            CustomSlidableAction(
              onPressed: (_) => source == AnalysisSource.camera
                  ? _setMyFace(context, ref)
                  : _openCompatibility(context),
              backgroundColor: source == AnalysisSource.camera
                  ? Colors.green.shade600
                  : Colors.indigo.shade600,
              foregroundColor: Colors.white,
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(source == AnalysisSource.camera ? Icons.face : Icons.favorite),
                  const SizedBox(height: 4),
                  Text(source == AnalysisSource.camera ? '내 얼굴' : '궁합',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
            CustomSlidableAction(
              onPressed: (_) => _delete(context, ref),
              backgroundColor: Colors.red.shade600,
              foregroundColor: Colors.white,
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.delete),
                  const SizedBox(height: 4),
                  const Text('삭제', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
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
                                GestureDetector(
                                  onTap: () =>
                                      _showAliasDialog(context, ref, displayName),
                                  child: Text(displayName,
                                      style: TextStyle(
                                          color: AppTheme.textPrimary,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                ),
                                Padding(
                                  padding: const EdgeInsets.only(right: 10),
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
                                '${report.ethnicity.labelKo} · ${report.ageGroup.labelKo} · ${report.gender.labelKo}',
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
                  child: const Text('내 얼굴',
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

  void _delete(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).remove(index);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '삭제되었습니다'),
    );
  }

  String _faceShape() {
    final faceAspect = report.metrics['faceAspectRatio']!;
    if (faceAspect.zScore > 1.0) return '세로로 긴 얼굴형';
    if (faceAspect.zScore < -1.0) return '가로로 넓은 얼굴형';
    return '표준 얼굴형';
  }

  void _openCompatibility(BuildContext context) {
    // TODO: 궁합 기능 구현
  }

  void _setMyFace(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).setMyFace(index);
    showTopSnackBar(
      Overlay.of(context),
      CompactSnackBar.success(message: '내 얼굴로 설정되었습니다'),
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
                title: const Text('내 얼굴'),
                onTap: () {
                  Navigator.pop(ctx);
                  _setMyFace(context, ref);
                },
              )
            else
              ListTile(
                leading: Icon(Icons.favorite, color: Colors.indigo.shade600),
                title: const Text('궁합'),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCompatibility(context);
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
}

class _PhysiognomyScreenState extends ConsumerState<PhysiognomyScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  Widget build(BuildContext context) {
    final historyTab = ref.watch(historyTabProvider);
    if (_tabController.index != historyTab) {
      _tabController.index = historyTab;
    }
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
    _tabController = TabController(length: 2, vsync: this);
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
