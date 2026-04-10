import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:top_snackbar_flutter/custom_snack_bar.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/presentation/providers/history_provider.dart';
import 'package:face_reader/presentation/screens/home/report_page.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('히스토리'),
      ),
      body: history.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.history, color: AppTheme.border, size: 64),
                  const SizedBox(height: 16),
                  Text('분석 기록이 없습니다',
                      style: TextStyle(
                          color: AppTheme.textHint, fontSize: 16)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final report = history[index];
                return _HistoryItem(
                  report: report,
                  index: index,
                );
              },
            ),
    );
  }
}

class _HistoryItem extends ConsumerWidget {
  final FaceReadingReport report;
  final int index;

  const _HistoryItem({required this.report, required this.index});

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
              onPressed: (_) => _setMyFace(context, ref),
              backgroundColor: Colors.green.shade600,
              foregroundColor: Colors.white,
              borderRadius: BorderRadius.circular(14),
              padding: EdgeInsets.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.face),
                  const SizedBox(height: 4),
                  const Text('내 얼굴', style: TextStyle(fontSize: 12)),
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
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        report.source == AnalysisSource.camera
                            ? Icons.camera_alt
                            : Icons.photo_library,
                        color: AppTheme.textSecondary,
                        size: 36,
                      ),
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

  String _faceShape() {
    final faceAspect = report.metrics['faceAspectRatio']!;
    if (faceAspect.zScore > 1.0) return '세로로 긴 얼굴형';
    if (faceAspect.zScore < -1.0) return '가로로 넓은 얼굴형';
    return '표준 얼굴형';
  }

  void _delete(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).remove(index);
    showTopSnackBar(
      Overlay.of(context),
      const CustomSnackBar.success(message: '삭제되었습니다'),
    );
  }

  void _setMyFace(BuildContext context, WidgetRef ref) {
    ref.read(historyProvider.notifier).setMyFace(index);
    showTopSnackBar(
      Overlay.of(context),
      const CustomSnackBar.success(message: '내 얼굴로 설정되었습니다'),
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
}
