import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'face_analysis.dart';
import 'face_reference_data.dart';

class ReportPage extends StatelessWidget {
  final FaceAnalysisReport report;

  const ReportPage({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('얼굴 분석 리포트'),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: '저장',
            onPressed: () => _showSaveOptions(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context),
          const SizedBox(height: 16),
          _buildSummaryCard(context),
          const SizedBox(height: 20),
          _buildCategorySection(context, '얼굴 비율', Icons.face, 'face'),
          const SizedBox(height: 16),
          _buildCategorySection(context, '눈', Icons.remove_red_eye, 'eyes'),
          const SizedBox(height: 16),
          _buildCategorySection(context, '코', Icons.air, 'nose'),
          const SizedBox(height: 16),
          _buildCategorySection(context, '입', Icons.mood, 'mouth'),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  String _generateText() {
    final time = report.timestamp;
    final timeStr =
        '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    buf.writeln('=== 얼굴 분석 리포트 ===');
    buf.writeln('날짜: $timeStr');
    buf.writeln('기준: ${report.ethnicity.labelKo}');
    buf.writeln();

    final categories = [
      ('얼굴 비율', 'face'),
      ('눈', 'eyes'),
      ('코', 'nose'),
      ('입', 'mouth'),
    ];

    for (final (title, cat) in categories) {
      buf.writeln('--- $title ---');
      for (final m in report.byCategory(cat)) {
        final valStr = m.id == 'mouthCornerAngle'
            ? '${m.value.toStringAsFixed(1)}°'
            : m.value.toStringAsFixed(3);
        final refStr = m.id == 'mouthCornerAngle'
            ? '${m.refMean.toStringAsFixed(1)}° (±${m.refSd.toStringAsFixed(1)}°)'
            : '${m.refMean.toStringAsFixed(3)} (±${m.refSd.toStringAsFixed(3)})';
        buf.writeln('${m.nameKo} (${m.nameEn})');
        buf.writeln('  측정값: $valStr | 평균: $refStr');
        buf.writeln('  Z-score: ${m.zScore.toStringAsFixed(2)} → ${m.verdict}');
        buf.writeln();
      }
    }

    return buf.toString();
  }

  void _showSaveOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF16213E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.tealAccent),
                  title: const Text('클립보드에 복사', style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _generateText()));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('클립보드에 복사되었습니다')),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.save, color: Colors.tealAccent),
                  title: const Text('파일로 저장', style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveToFile(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveToFile(BuildContext context) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final time = report.timestamp;
      final filename = 'face_report_'
          '${time.year}${time.month.toString().padLeft(2, '0')}${time.day.toString().padLeft(2, '0')}_'
          '${time.hour.toString().padLeft(2, '0')}${time.minute.toString().padLeft(2, '0')}${time.second.toString().padLeft(2, '0')}'
          '.txt';
      final file = File('${dir.path}/$filename');
      await file.writeAsString(_generateText());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 완료: $filename')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패: $e')),
        );
      }
    }
  }

  Widget _buildHeader(BuildContext context) {
    final time = report.timestamp;
    final timeStr =
        '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Text(
          timeStr,
          style: const TextStyle(color: Colors.white54, fontSize: 13),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.teal.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.5)),
          ),
          child: Text(
            report.ethnicity.labelKo,
            style: const TextStyle(color: Colors.tealAccent, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final faceAspect = report.metrics.firstWhere((m) => m.id == 'faceAspectRatio');
    final upperRatio = report.metrics.firstWhere((m) => m.id == 'upperFaceRatio');
    final midRatio = report.metrics.firstWhere((m) => m.id == 'midFaceRatio');
    final lowerRatio = report.metrics.firstWhere((m) => m.id == 'lowerFaceRatio');

    String faceShape;
    if (faceAspect.zScore > 1.0) {
      faceShape = '세로로 긴 얼굴형';
    } else if (faceAspect.zScore < -1.0) {
      faceShape = '가로로 넓은 얼굴형';
    } else {
      faceShape = '표준 얼굴형';
    }

    // Find the most prominent third
    final thirds = [
      ('이마', upperRatio.zScore),
      ('중안면', midRatio.zScore),
      ('하안면', lowerRatio.zScore),
    ];
    thirds.sort((a, b) => b.$2.abs().compareTo(a.$2.abs()));
    final prominent = thirds.first;
    String thirdNote = '';
    if (prominent.$2.abs() > 0.5) {
      thirdNote = prominent.$2 > 0 ? '${prominent.$1}이 상대적으로 긴 편' : '${prominent.$1}이 상대적으로 짧은 편';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3460), Color(0xFF16213E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '종합 요약',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.face_2, color: Colors.tealAccent, size: 28),
              const SizedBox(width: 12),
              Text(
                faceShape,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ],
          ),
          if (thirdNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              thirdNote,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    String title,
    IconData icon,
    String category,
  ) {
    final metrics = report.byCategory(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.tealAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...metrics.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _MetricCard(metric: m),
            )),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final MetricAnalysis metric;

  const _MetricCard({required this.metric});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      metric.nameKo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      metric.nameEn,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _verdictColor(metric.zScore).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  metric.verdict,
                  style: TextStyle(
                    color: _verdictColor(metric.zScore),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Z-score gauge
          _ZScoreGauge(zScore: metric.zScore),
          const SizedBox(height: 8),
          // Values row
          Row(
            children: [
              Text(
                '측정값: ${_formatValue(metric)}',
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '평균: ${_formatRef(metric)}',
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatValue(MetricAnalysis m) {
    if (m.id == 'mouthCornerAngle') return '${m.value.toStringAsFixed(1)}°';
    return m.value.toStringAsFixed(3);
  }

  String _formatRef(MetricAnalysis m) {
    if (m.id == 'mouthCornerAngle') {
      return '${m.refMean.toStringAsFixed(1)}° (±${m.refSd.toStringAsFixed(1)}°)';
    }
    return '${m.refMean.toStringAsFixed(3)} (±${m.refSd.toStringAsFixed(3)})';
  }

  Color _verdictColor(double z) {
    final abs = z.abs();
    if (abs < 0.5) return Colors.greenAccent;
    if (abs < 1.0) return Colors.lightBlueAccent;
    if (abs < 2.0) return Colors.orangeAccent;
    return Colors.redAccent;
  }
}

class _ZScoreGauge extends StatelessWidget {
  final double zScore;

  const _ZScoreGauge({required this.zScore});

  @override
  Widget build(BuildContext context) {
    // Clamp to -3..+3 for display
    final clamped = zScore.clamp(-3.0, 3.0);
    // Map to 0..1 (center = 0.5)
    final position = (clamped + 3.0) / 6.0;

    return SizedBox(
      height: 28,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final center = width / 2;
          final markerX = position * width;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Background track
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    gradient: const LinearGradient(
                      colors: [
                        Color(0xFF2196F3),
                        Color(0xFF4CAF50),
                        Color(0xFF4CAF50),
                        Color(0xFFFF9800),
                      ],
                      stops: [0.0, 0.35, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
              // Center line (mean)
              Positioned(
                top: 6,
                left: center - 0.5,
                child: Container(
                  width: 1,
                  height: 16,
                  color: Colors.white54,
                ),
              ),
              // SD markers (-1, +1)
              Positioned(
                top: 8,
                left: width / 6 * 2 - 0.5,
                child: Container(width: 1, height: 12, color: Colors.white24),
              ),
              Positioned(
                top: 8,
                left: width / 6 * 4 - 0.5,
                child: Container(width: 1, height: 12, color: Colors.white24),
              ),
              // Marker (measured value)
              Positioned(
                top: 4,
                left: markerX - 8,
                child: Container(
                  width: 16,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Color(0xFF1A1A2E),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
              ),
              // Labels
              const Positioned(
                top: 0,
                left: 0,
                child: Text('-', style: TextStyle(color: Colors.white24, fontSize: 10)),
              ),
              const Positioned(
                top: 0,
                right: 0,
                child: Text('+', style: TextStyle(color: Colors.white24, fontSize: 10)),
              ),
            ],
          );
        },
      ),
    );
  }
}
