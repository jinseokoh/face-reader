import 'dart:developer' as dev;
import 'dart:io';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/report_assembler.dart';
import 'package:face_reader/presentation/providers/di_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'metaphor_page.dart';

class ReportPage extends ConsumerStatefulWidget {
  final FaceReadingReport report;

  const ReportPage({super.key, required this.report});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

// ─── Attribute Bar ───
class _AttributeBar extends StatelessWidget {
  final Attribute attribute;
  final double score;

  const _AttributeBar({required this.attribute, required this.score});

  @override
  Widget build(BuildContext context) {
    final fraction = (score / 10.0).clamp(0.0, 1.0);

    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(attribute.labelKo,
              style: TextStyle(
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
          child: Text(score.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: _Palette.darkBrown,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}

// ─── Metric Row (compact) ───
class _MetricRow extends StatelessWidget {
  final String nameKo;
  final String nameEn;
  final double zScore;
  final int metricScore;

  const _MetricRow({
    required this.nameKo,
    required this.nameEn,
    required this.zScore,
    required this.metricScore,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nameKo,
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600)),
                    Text(nameEn,
                        style: TextStyle(
                            color: AppTheme.textHint, fontSize: 12)),
                  ],
                ),
              ),
              _ScoreBadge(score: metricScore),
            ],
          ),
          const SizedBox(height: 8),
          _MiniGauge(zScore: zScore),
        ],
      ),
    );
  }
}

// ─── Mini Gauge (tortoise gradient) ───
class _MiniGauge extends StatelessWidget {
  final double zScore;

  const _MiniGauge({required this.zScore});

  @override
  Widget build(BuildContext context) {
    final clamped = zScore.clamp(-3.0, 3.0);
    final position = (clamped + 3.0) / 6.0;

    return SizedBox(
      height: 12,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final center = width / 2;
          final markerX = position * width;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Track
              Positioned(
                top: 2,
                left: 0,
                right: 0,
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(3),
                    gradient: const LinearGradient(
                      colors: [
                        _Palette.lightOlive,
                        _Palette.shell,
                        _Palette.shell,
                        _Palette.sand,
                      ],
                      stops: [0.0, 0.35, 0.65, 1.0],
                    ),
                  ),
                ),
              ),
              // Center line
              Positioned(
                top: 0,
                left: center - 0.5,
                child: Container(
                    width: 1, height: 10, color: _Palette.amber),
              ),
              // Marker
              Positioned(
                top: 0,
                left: (markerX - 5).clamp(0, width - 10),
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _Palette.darkBrown,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─── Tortoise palette ───
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

class _ReportPageState extends ConsumerState<ReportPage> {
  bool _isLoadingMetaphor = false;
  bool _showMetrics = false;

  FaceReadingReport get report => widget.report;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('관상 분석 리포트'),
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
          _buildHeader(),
          const SizedBox(height: 16),
          _buildArchetypeCard(),
          const SizedBox(height: 20),
          _buildAttributeSection(),
          const SizedBox(height: 20),
          _buildReadingSection(),
          const SizedBox(height: 16),
          _buildMetaphorButton(),
          const SizedBox(height: 20),
          _buildMetricsToggle(),
          if (_showMetrics) ...[
            const SizedBox(height: 12),
            _buildMetricsDetail(),
          ],
        ],
      ),
    );
  }

  Widget _badge(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _Palette.sand.withValues(alpha: 0.5)),
      ),
      child: Text(text,
          style: TextStyle(
              color: _Palette.darkBrown,
              fontSize: 13,
              fontWeight: FontWeight.w600)),
    );
  }

  // ─── Archetype Card ───
  Widget _buildArchetypeCard() {
    final arch = report.archetype;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _Palette.darkBrown,
            _Palette.warmBrown,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('당신의 관상',
              style: TextStyle(
                  color: _Palette.sand, fontSize: 16, letterSpacing: 1)),
          const SizedBox(height: 8),
          Text(arch.primaryLabel,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${arch.secondaryLabel} 기질',
              style: TextStyle(
                  color: _Palette.sand, fontSize: 16)),
          if (arch.specialArchetype != null) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3)),
              ),
              child: Text(arch.specialArchetype!,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 10 Attribute Scores ───
  Widget _buildAttributeSection() {
    final sorted = report.attributeScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('관상 10대 속성',
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 19,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        ...sorted.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AttributeBar(
                  attribute: e.key, score: e.value),
            )),
      ],
    );
  }

  // ─── Header ───
  Widget _buildHeader() {
    final time = report.timestamp;
    final timeStr =
        '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Row(
      children: [
        Text(timeStr,
            style: TextStyle(color: AppTheme.textHint, fontSize: 16)),
        const Spacer(),
        _badge(report.gender.labelKo),
        const SizedBox(width: 6),
        _badge(report.ageGroup.labelKo),
        const SizedBox(width: 6),
        _badge(report.ethnicity.labelKo),
      ],
    );
  }

  // ─── Metaphor Button ───
  Widget _buildMetaphorButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: _isLoadingMetaphor ? null : _fetchMetaphor,
        style: ElevatedButton.styleFrom(
          backgroundColor: _Palette.darkBrown,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: _isLoadingMetaphor
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.auto_stories),
        label: Text(
          _isLoadingMetaphor ? '총평 생성 중...' : 'AI 총평 보기',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildMetricCategory(String title, String category) {
    final infos =
        metricInfoList.where((m) => m.category == category).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: TextStyle(
                color: _Palette.warmBrown,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...infos.map((info) {
          final metric = report.metrics[info.id];
          if (metric == null) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _MetricRow(
              nameKo: info.nameKo,
              nameEn: info.nameEn,
              zScore: metric.zScore,
              metricScore: metric.metricScore,
            ),
          );
        }),
      ],
    );
  }

  Widget _buildMetricsDetail() {
    final categories = [
      ('얼굴', 'face'),
      ('눈', 'eyes'),
      ('코', 'nose'),
      ('입', 'mouth'),
    ];

    return Column(
      children: [
        for (final (title, cat) in categories) ...[
          _buildMetricCategory(title, cat),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 8),
        _buildReferenceList(),
      ],
    );
  }

  // ─── Metrics Detail Toggle ───
  Widget _buildMetricsToggle() {
    return GestureDetector(
      onTap: () => setState(() => _showMetrics = !_showMetrics),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _Palette.cream,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Palette.shell),
        ),
        child: Row(
          children: [
            Icon(Icons.straighten,
                color: _Palette.warmBrown, size: 20),
            const SizedBox(width: 10),
            Text('AI 관상 측정값 (17 Metrics)',
                style: TextStyle(
                    color: _Palette.darkBrown,
                    fontSize: 16,
                    fontWeight: FontWeight.w600)),
            const Spacer(),
            Icon(
              _showMetrics
                  ? Icons.keyboard_arrow_up
                  : Icons.keyboard_arrow_down,
              color: _Palette.warmBrown,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReadingBlock(String section, {required bool isFirst}) {
    // First block is the archetype intro (no header)
    // Others start with "Header\nBody..."
    if (isFirst) {
      return Text(section.trim(),
          style: TextStyle(
              color: _Palette.warmBrown,
              fontSize: 16,
              height: 1.7));
    }

    final lines = section.split('\n');
    final header = lines.first.trim();
    final body = lines.skip(1).join('\n').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _Palette.darkBrown.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(header,
              style: TextStyle(
                  color: _Palette.darkBrown,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 8),
        Text(body,
            style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                height: 1.7)),
      ],
    );
  }

  // ─── Deterministic Reading (조립된 블록) ───
  Widget _buildReadingSection() {
    final assembled = assembleReport(report);
    final blocks = assembled.assembledText;
    if (blocks.isEmpty) return const SizedBox.shrink();

    // Split by ## headers to render sections
    final sections = blocks.split(RegExp(r'\n\n##\s*'));

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
          Text('관상 해석',
              style: TextStyle(
                  color: _Palette.darkBrown,
                  fontSize: 19,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 14),
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            _buildReadingBlock(sections[i], isFirst: i == 0),
          ],
        ],
      ),
    );
  }

  Widget _buildReferenceList() {
    const references = [
      '파카스 두개안면 계측학 (Farkas, 1994) — 2,500명 대상 166개 비율 인덱스',
      '눈 사이 거리 메타분석 (PMC9029890) — 67개 연구, 22,638명 분석',
      '신고전 비율 검증 연구 (PMC4369102) — 얼굴 3등분 비율 유효성 검증',
      '미국 국립산업안전보건원 안면 계측 데이터 (NIOSH) — 3,997명 18개 측정값',
      '구글 미디어파이프 얼굴 메시 — 468개 랜드마크 기반 측정',
      '동아시아 얼굴 인체측정 연구 — 얼굴 비율 통계 데이터',
      '컴퓨터 비전 안면 랜드마크 연구 — 얼굴 특징점 기반 정량 분석',
      '동양 관상학 고전 (마의상법, 신상전편) — 오관·삼정·십이궁 해석 체계',
      '안면 노화 인류학 (Mendelson & Wong, 2012) — 연조직 노화 변화 보정 근거',
      '얼굴 매력도 연구 (Rhodes, 2006) — 평균성·대칭성과 매력의 상관관계',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('참고 자료 리스트',
            style: TextStyle(
                color: _Palette.warmBrown,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (var i = 0; i < references.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 24,
                  child: Text('${i + 1}.',
                      style: TextStyle(
                          color: _Palette.amber,
                          fontSize: 16,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  child: Text(references[i],
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 16)),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _fetchMetaphor() async {
    setState(() => _isLoadingMetaphor = true);
    try {
      final repository = ref.read(metaphorRepositoryProvider);
      final text = await repository.getMetaphor(report);
      if (!mounted) return;
      MetaphorPage.show(context, text);
    } catch (e, stack) {
      dev.log(
        '[MetaphorError] $e\nStack: $stack',
        name: 'ReportPage',
        error: e,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingMetaphor = false);
    }
  }

  // ─── Save ───
  String _generateText() {
    final time = report.timestamp;
    final timeStr =
        '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final assembled = assembleReport(report);

    final buf = StringBuffer();
    buf.writeln('=== 관상 분석 리포트 ===');
    buf.writeln('날짜: $timeStr');
    buf.writeln(
        '${report.gender.labelKo} · ${report.ageGroup.labelKo} · ${report.ethnicity.labelKo}');
    buf.writeln();
    buf.writeln(
        '유형: ${report.archetype.primaryLabel} (${report.archetype.secondaryLabel} 기질)');
    if (report.archetype.specialArchetype != null) {
      buf.writeln('특수상: ${report.archetype.specialArchetype}');
    }
    buf.writeln();

    buf.writeln('--- 10대 속성 ---');
    final sorted = report.attributeScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in sorted) {
      buf.writeln('${e.key.labelKo}: ${e.value.toStringAsFixed(1)}');
    }
    buf.writeln();

    buf.writeln('--- 분석 ---');
    buf.writeln(assembled.assembledText);

    return buf.toString();
  }


  Future<void> _shareViaKakao(BuildContext context) async {
    try {
      // Ensure report is saved to Supabase first
      String? uuid = widget.report.supabaseId;
      if (uuid == null) {
        uuid = await SupabaseService().saveMetrics(widget.report);
        widget.report.supabaseId = uuid;
      }

      final link = 'https://face.whatsupkorea.com/report/$uuid';

      final template = FeedTemplate(
        content: Content(
          title: '관상 분석 결과',
          description: '나의 관상을 분석해 보세요!',
          imageUrl: Uri.parse('https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/assets/share-thumbnail.png'),
          link: Link(
            webUrl: Uri.parse(link),
            mobileWebUrl: Uri.parse(link),
          ),
        ),
        buttons: [
          Button(
            title: '결과 보기',
            link: Link(
              webUrl: Uri.parse(link),
              mobileWebUrl: Uri.parse(link),
            ),
          ),
        ],
      );

      await ShareClient.instance.shareDefault(template: template);
    } catch (e, st) {
      debugPrint('[KakaoShare] error: $e');
      debugPrint('[KakaoShare] stackTrace: $st');
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
                  leading:
                      Icon(Icons.copy, color: AppTheme.textSecondary),
                  title: Text('클립보드에 복사',
                      style: TextStyle(
                          fontFamily: '', color: AppTheme.textPrimary)),
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: _generateText()));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('클립보드에 복사되었습니다')),
                    );
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.picture_as_pdf, color: AppTheme.textSecondary),
                  title: Text('PDF로 저장',
                      style: TextStyle(
                          fontFamily: '', color: AppTheme.textPrimary)),
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
      final pdfDoc = pw.Document();
      final fontData = await rootBundle.load('assets/fonts/SongMyung-Regular.ttf');
      final ttf = pw.Font.ttf(fontData);
      final report = widget.report;
      final metricNameMap = {
        for (final info in metricInfoList) info.id: info.nameKo,
      };
      final time = report.timestamp;
      final timeStr =
          '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')} '
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

      pdfDoc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          build: (pw.Context ctx) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text('관상 분석 리포트',
                    style: pw.TextStyle(font: ttf, fontSize: 24)),
              ),
              pw.Text(timeStr, style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColors.grey600)),
              pw.SizedBox(height: 4),
              pw.Text(
                '${report.ethnicity.labelKo} · ${report.gender.labelKo} · ${report.ageGroup.labelKo}',
                style: pw.TextStyle(font: ttf, fontSize: 12),
              ),
              pw.SizedBox(height: 16),
              // Archetype
              pw.Header(
                level: 1,
                child: pw.Text('관상 유형', style: pw.TextStyle(font: ttf, fontSize: 18)),
              ),
              pw.Text(
                '${report.archetype.primaryLabel} (${report.archetype.secondaryLabel})',
                style: pw.TextStyle(font: ttf, fontSize: 14, fontWeight: pw.FontWeight.bold),
              ),
              if (report.archetype.specialArchetype != null)
                pw.Text(
                  '특수 관상: ${report.archetype.specialArchetype}',
                  style: pw.TextStyle(font: ttf, fontSize: 12, color: PdfColors.red800),
                ),
              pw.SizedBox(height: 16),
              // Attribute scores
              pw.Header(
                level: 1,
                child: pw.Text('속성 점수', style: pw.TextStyle(font: ttf, fontSize: 18)),
              ),
              ...report.attributeScores.entries.map((e) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(e.key.labelKo, style: pw.TextStyle(font: ttf, fontSize: 12)),
                        pw.Text('${e.value.toStringAsFixed(1)} / 10', style: pw.TextStyle(font: ttf, fontSize: 12)),
                      ],
                    ),
                  )),
              pw.SizedBox(height: 16),
              // Metrics
              pw.Header(
                level: 1,
                child: pw.Text('측정값', style: pw.TextStyle(font: ttf, fontSize: 18)),
              ),
              ...report.metrics.entries.map((e) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(metricNameMap[e.key] ?? e.key, style: pw.TextStyle(font: ttf, fontSize: 11)),
                        pw.Text(
                          '${e.value.rawValue.toStringAsFixed(3)} (z: ${e.value.zScore.toStringAsFixed(2)})',
                          style: pw.TextStyle(font: ttf, fontSize: 11),
                        ),
                      ],
                    ),
                  )),
              // Triggered rules
              if (report.triggeredRules.isNotEmpty) ...[
                pw.SizedBox(height: 16),
                pw.Header(
                  level: 1,
                  child: pw.Text('특수 규칙', style: pw.TextStyle(font: ttf, fontSize: 18)),
                ),
                ...report.triggeredRules.map((r) => pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 2),
                      child: pw.Text(r.id, style: pw.TextStyle(font: ttf, fontSize: 11)),
                    )),
              ],
            ];
          },
        ),
      );

      // Save to Downloads folder (accessible to user)
      Directory? dir;
      if (Platform.isAndroid) {
        dir = Directory('/storage/emulated/0/Download');
        if (!await dir.exists()) {
          dir = await getApplicationDocumentsDirectory();
        }
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      final filename = 'face_report_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(await pdfDoc.save());

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF 저장 완료: $filename')),
        );
      }
    } catch (e) {
      debugPrint('[PDF] error: $e');
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

// ─── Score Badge ───
class _ScoreBadge extends StatelessWidget {
  final int score;

  const _ScoreBadge({required this.score});

  @override
  Widget build(BuildContext context) {
    final label = _scoreLabel(score);
    final color = _scoreColor(score);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  String _scoreLabel(int s) {
    switch (s) {
      case 3:  return '매우 큼';
      case 2:  return '큼';
      case 1:  return '약간 큼';
      case 0:  return '평균';
      case -1: return '약간 작음';
      case -2: return '작음';
      case -3: return '매우 작음';
      default: return s > 0 ? '매우 큼' : '매우 작음';
    }
  }

  Color _scoreColor(int s) {
    return _Palette.darkBrown;
  }
}
