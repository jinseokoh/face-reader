import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/enums/age_group.dart';
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
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ReportPage(report: report),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}

class _HistoryItem extends StatelessWidget {
  final FaceReadingReport report;
  final VoidCallback onTap;

  const _HistoryItem({required this.report, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final faceAspect = report.metrics['faceAspectRatio']!;
    String faceShape;
    if (faceAspect.zScore > 1.0) {
      faceShape = '세로로 긴 얼굴형';
    } else if (faceAspect.zScore < -1.0) {
      faceShape = '가로로 넓은 얼굴형';
    } else {
      faceShape = '표준 얼굴형';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
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
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(faceShape,
                              style: TextStyle(
                                  fontFamily: '',
                                  color: AppTheme.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Text(
                                timeago.format(report.timestamp, locale: 'ko'),
                                style: TextStyle(
                                    fontFamily: '',
                                    color: AppTheme.textHint,
                                    fontSize: 13)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('${report.ethnicity.labelKo} / ${report.ageGroup.labelKo} / ${report.gender.labelKo}',
                          style: TextStyle(
                              fontFamily: '',
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
    );
  }
}
