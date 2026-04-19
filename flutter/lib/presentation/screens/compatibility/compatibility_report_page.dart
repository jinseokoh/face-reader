import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/domain/models/compatibility_result.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─── Tortoise palette (관상 report_page와 동일) ───
class _Palette {
  static const darkBrown = Color(0xFF5C4033);
  static const warmBrown = Color(0xFF7B5B3A);
  static const amber = Color(0xFF9B7B4F);
  static const sand = Color(0xFFBFA67A);
  static const olive = Color(0xFF8B9A6B);
  static const lightOlive = Color(0xFFA8B590);
  static const cream = Color(0xFFF5EFE0);
  static const shell = Color(0xFFEDE5D5);

  static const gradient = LinearGradient(
    colors: [darkBrown, warmBrown, amber, sand, olive, lightOlive],
    stops: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
  );
}

class CompatibilityReportPage extends StatelessWidget {
  final CompatibilityResult result;
  final String albumName;
  final String albumUuid;
  final String? thumbnailPath;

  const CompatibilityReportPage({
    super.key,
    required this.result,
    required this.albumName,
    required this.albumUuid,
    this.thumbnailPath,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('궁합 분석'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: '저장',
            onPressed: () => _showSaveOptions(context),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: '카카오 공유',
            onPressed: () => _shareViaKakao(context),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildScoreHeader(),
          const SizedBox(height: 16),
          _buildArchetypeCard(),
          const SizedBox(height: 20),
          _buildCategorySection(),
          if (result.specialNote != null) ...[
            const SizedBox(height: 20),
            _buildSpecialNote(),
          ],
          const SizedBox(height: 20),
          _buildSummarySection(),
        ],
      ),
    );
  }

  // ─── Score Header ───
  Widget _buildScoreHeader() {
    final score = result.score.round();
    final label = _resolveLabel(score);

    final container = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_Palette.cream, Colors.white],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        children: [
          Text(
            '$score',
            style: const TextStyle(
              fontFamily: 'SongMyung',
              fontSize: 56,
              fontWeight: FontWeight.w600,
              color: _Palette.darkBrown,
            ),
          ),
          const SizedBox(height: 4),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'SongMyung',
                  fontSize: 18,
                  color: _Palette.warmBrown,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          // Score bar — same style as attribute bars in report_page
          Container(
            height: 14,
            decoration: BoxDecoration(
              color: _Palette.shell,
              borderRadius: BorderRadius.circular(7),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: (result.score / 100).clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  gradient: _Palette.gradient,
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    // Album thumbnail at top-left, same 40×40 size as physiognomy list items.
    final thumbWidget = _buildThumbnail();
    if (thumbWidget == null) return container;
    // StackFit.passthrough — pass the parent's (ListView) tight cross-axis
    // width constraint through to the inner Container so it stays full-width.
    // Default StackFit.loose collapses Container to its child's intrinsic width.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        container,
        Positioned(
          top: 12,
          left: 12,
          child: thumbWidget,
        ),
      ],
    );
  }

  Widget? _buildThumbnail() {
    final path = thumbnailPath;
    if (path == null) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
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

  // ─── Archetype Card ───
  Widget _buildArchetypeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_Palette.darkBrown, _Palette.warmBrown],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _archetypeChip('나', result.myArchetype),
              const Icon(Icons.favorite, color: _Palette.sand, size: 24),
              _archetypeChip('상대방', result.albumArchetype),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '원형 궁합 ${result.archetypeScore.round()}점',
            style: const TextStyle(
                color: _Palette.sand,
                fontSize: 14,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _archetypeChip(String who, String archetype) {
    return Column(
      children: [
        Text(who,
            style: const TextStyle(
                color: _Palette.sand,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: Text(archetype,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  // ─── Category Bars ───
  Widget _buildCategorySection() {
    final sorted = result.categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('분야별 궁합',
            style: TextStyle(
                color: _Palette.darkBrown,
                fontSize: 19,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...sorted.map((e) => _buildCategoryBar(e.key, e.value)),
      ],
    );
  }

  Widget _buildCategoryBar(String attrName, double score) {
    final label = _attrLabel(attrName);
    final fraction = (score / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: _Palette.shell,
                borderRadius: BorderRadius.circular(7),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: fraction,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: _Palette.gradient,
                    borderRadius: BorderRadius.circular(7),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(score.round().toString(),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    color: _Palette.darkBrown,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ─── Special Note ───
  Widget _buildSpecialNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _Palette.darkBrown.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome, color: _Palette.amber, size: 16),
                const SizedBox(width: 6),
                const Text('특별 관상 궁합',
                    style: TextStyle(
                        color: _Palette.darkBrown,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(result.specialNote!,
              style: const TextStyle(
                color: _Palette.warmBrown,
                fontSize: 16,
                height: 1.7,
              )),
        ],
      ),
    );
  }

  // ─── Summary Sections ───
  Widget _buildSummarySection() {
    final sections = _parseSummarySections(result.summary);

    if (sections.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _Palette.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _Palette.shell),
        ),
        child: Text(result.summary,
            style: const TextStyle(
              color: _Palette.warmBrown,
              fontSize: 16,
              height: 1.7,
            )),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('궁합 해석',
              style: TextStyle(
                  color: _Palette.darkBrown,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ...sections.asMap().entries.map((entry) {
            final i = entry.key;
            final section = entry.value;
            return _buildReadingBlock(section, isFirst: i == 0);
          }),
        ],
      ),
    );
  }

  Widget _buildReadingBlock(_SummarySection section, {required bool isFirst}) {
    return Padding(
      padding: EdgeInsets.only(top: isFirst ? 0 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _Palette.darkBrown.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(section.title,
                style: const TextStyle(
                    color: _Palette.darkBrown,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 8),
          Text(section.body,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 16,
                  height: 1.7)),
        ],
      ),
    );
  }

  List<_SummarySection> _parseSummarySections(String summary) {
    final sections = <_SummarySection>[];
    final lines = summary.split('\n');
    String? currentTitle;
    final bodyLines = <String>[];

    for (final line in lines) {
      if (line.startsWith('## ')) {
        if (currentTitle != null && bodyLines.isNotEmpty) {
          sections.add(_SummarySection(
            title: currentTitle,
            body: bodyLines.join('\n').trim(),
          ));
        }
        currentTitle = line.substring(3).trim();
        bodyLines.clear();
      } else if (currentTitle != null) {
        bodyLines.add(line);
      }
    }
    if (currentTitle != null && bodyLines.isNotEmpty) {
      sections.add(_SummarySection(
        title: currentTitle,
        body: bodyLines.join('\n').trim(),
      ));
    }

    return sections;
  }

  /// Percentile-based label thresholds calibrated via Monte Carlo on 20,000
  /// CORRELATED-METRIC pairs (test/compat_calibration_test.dart). Real Korean
  /// adult faces have strong metric correlations (e.g. thick brow ↔ strong jaw),
  /// so independent random sampling underestimates how often two real users
  /// will simultaneously hit high compat. The Monte Carlo now uses template-
  /// based correlated face generation to better mirror real users.
  ///
  /// Empirically-verified distribution (2026-04-19 v2.6 zone-parity + rule cap,
  /// 20,000 pairs, MC p90/p60/p30):
  ///   ≥ 83 → 천생연분  (10%)
  ///   ≥ 73 → 좋은 궁합 (30%)
  ///   ≥ 65 → 보통       (30%)
  ///   else → 어려운 궁합 (30%)
  ///
  /// 재보정 절차: flutter test test/compat_calibration_test.dart 실행 → 출력된
  /// _resolveLabel thresholds 를 그대로 아래에 붙여 넣고, compat_label_fairness
  /// 가 green 인지 확인.
  String _resolveLabel(int score) {
    if (score >= 83) return '천생연분';
    if (score >= 73) return '좋은 궁합';
    if (score >= 65) return '보통';
    return '어려운 궁합';
  }

  String _attrLabel(String name) {
    const labels = {
      'wealth': '재물운',
      'leadership': '리더십',
      'intelligence': '통찰력',
      'sociability': '사회성',
      'emotionality': '감정성',
      'stability': '안정성',
      'sensuality': '바람기',
      'trustworthiness': '신뢰성',
      'attractiveness': '매력도',
      'libido': '관능도',
    };
    return labels[name] ?? name;
  }

  // ─── Save / Share ───────────────────────────────────────────

  String _generateText() {
    final ts = result.evaluatedAt;
    final tsStr =
        '${ts.year}.${ts.month.toString().padLeft(2, '0')}.${ts.day.toString().padLeft(2, '0')} '
        '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}';

    final buf = StringBuffer();
    buf.writeln('=== 궁합 분석 ===');
    buf.writeln('날짜: $tsStr');
    buf.writeln('나(${result.myArchetype}) ↔ 상대방(${result.albumArchetype})');
    buf.writeln('종합 점수: ${result.score.round()}점');
    buf.writeln();

    buf.writeln('--- 분야별 궁합 ---');
    final sorted = result.categoryScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      buf.writeln('${_attrLabel(e.key)}: ${e.value.round()}');
    }
    buf.writeln();

    if (result.specialNote != null) {
      buf.writeln('--- 특별 관상 궁합 ---');
      buf.writeln(result.specialNote);
      buf.writeln();
    }

    buf.writeln('--- 궁합 해석 ---');
    buf.writeln(result.summary);

    return buf.toString();
  }

  Future<void> _shareViaKakao(BuildContext context) async {
    try {
      final score = result.score.round();
      final template = FeedTemplate(
        content: Content(
          title: '궁합 분석 결과 — $score점',
          description:
              '나(${result.myArchetype})와 상대방(${result.albumArchetype})의 궁합 점수는 $score점입니다.',
          imageUrl: Uri.parse(
              'https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/assets/share-thumbnail.png'),
          link: Link(
            webUrl: Uri.parse('https://face.whatsupkorea.com'),
            mobileWebUrl: Uri.parse('https://face.whatsupkorea.com'),
          ),
        ),
      );
      await ShareClient.instance.shareDefault(template: template);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('공유 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }

  void _showSaveOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                  leading: Icon(Icons.copy, color: AppTheme.textSecondary),
                  title: Text('클립보드에 복사',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: _generateText()));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('클립보드에 복사되었습니다')),
                    );
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.picture_as_pdf, color: AppTheme.textSecondary),
                  title: Text('PDF로 저장',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _saveToPdf(context);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _saveToPdf(BuildContext context) async {
    try {
      final regularData =
          await rootBundle.load('assets/fonts/NotoSerifKR-Regular.ttf');
      final boldData =
          await rootBundle.load('assets/fonts/NotoSerifKR-Bold.ttf');
      final regularTtf = pw.Font.ttf(regularData);
      final boldTtf = pw.Font.ttf(boldData);
      // NotoSerifKR covers Korean + Latin punctuation (·).
      // Register both Regular AND Bold slots — bold-styled titles need a real
      // bold variant; otherwise pw.FontWeight.bold falls back to Helvetica
      // which lacks Korean glyphs and renders titles as tofu boxes.
      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(base: regularTtf, bold: boldTtf),
      );

      final text = _generateText();
      final lines = text.split('\n');

      pdfDoc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
            return lines.map((line) {
              if (line.startsWith('===')) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 8),
                  child: pw.Text(line.replaceAll('=', '').trim(),
                      style: pw.TextStyle(
                          fontSize: 22, fontWeight: pw.FontWeight.bold)),
                );
              } else if (line.startsWith('---')) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
                  child: pw.Text(line.replaceAll('-', '').trim(),
                      style: pw.TextStyle(
                          fontSize: 16, fontWeight: pw.FontWeight.bold)),
                );
              } else if (line.startsWith('## ')) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 10, bottom: 4),
                  child: pw.Text(line.substring(3).trim(),
                      style: pw.TextStyle(
                          fontSize: 14, fontWeight: pw.FontWeight.bold)),
                );
              } else if (line.trim().isEmpty) {
                return pw.SizedBox(height: 6);
              } else {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1),
                  child: pw.Text(line,
                      style: const pw.TextStyle(fontSize: 11)),
                );
              }
            }).toList();
          },
        ),
      );

      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      // Same album person → same filename → overwrite previous file
      final filename = 'compatibility-$albumUuid.pdf';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(await pdfDoc.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 저장 완료: $filename')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('PDF 저장 실패: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}

class _SummarySection {
  final String title;
  final String body;
  const _SummarySection({required this.title, required this.body});
}
