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
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;


class ReportPage extends ConsumerStatefulWidget {
  final FaceReadingReport report;

  const ReportPage({super.key, required this.report});

  @override
  ConsumerState<ReportPage> createState() => _ReportPageState();
}

// ─── Expandable Attribute Bar (tappable → shows contributors) ───
class _ExpandableAttributeBar extends StatefulWidget {
  final Attribute attribute;
  final double score;
  final AttributeEvidence? evidence;

  const _ExpandableAttributeBar({
    required this.attribute,
    required this.score,
    this.evidence,
  });

  @override
  State<_ExpandableAttributeBar> createState() =>
      _ExpandableAttributeBarState();
}

class _ExpandableAttributeBarState extends State<_ExpandableAttributeBar> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final fraction = (widget.score / 10.0).clamp(0.0, 1.0);

    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: Text(widget.attribute.labelKo,
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
                child: Text(widget.score.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                        color: _Palette.darkBrown,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ),
              Icon(
                _expanded
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down,
                color: _Palette.amber,
                size: 18,
              ),
            ],
          ),
        ),
        if (_expanded && widget.evidence != null)
          _buildContributorList(widget.evidence!),
      ],
    );
  }

  Widget _buildContributorList(AttributeEvidence evidence) {
    final top = evidence.contributors.take(5).toList();
    if (top.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(left: 80, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final c in top)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 120,
                    child: Text(
                      _contributorLabel(c.id),
                      style: TextStyle(
                          color: _Palette.warmBrown,
                          fontSize: 13),
                    ),
                  ),
                  Text(
                    '${c.value >= 0 ? '+' : ''}${c.value.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: c.value >= 0
                          ? _Palette.olive
                          : _Palette.warmBrown,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _contributorLabel(String id) {
    if (id.startsWith('node:')) {
      final nodeId = id.substring(5);
      return _nodeLabels[nodeId] ?? nodeId;
    }
    if (id == 'distinctiveness') return '특이성 보정';
    return _ruleLabels[id] ?? id;
  }
}

const _nodeLabels = <String, String>{
  'face': '얼굴 전체',
  'forehead': '이마',
  'glabella': '미간 (印堂)',
  'eyebrow': '눈썹',
  'eye': '눈',
  'nose': '코',
  'cheekbone': '광대 (태산·화산)',
  'ear': '귀',
  'philtrum': '인중',
  'mouth': '입',
  'chin': '턱',
};

// Stage rule IDs mapped to their classical 관상 meaning.
// Keep this in sync with `attribute_derivation.dart` rule comments.
const _ruleLabels = <String, String>{
  // Stage 2 — Zone (삼정)
  'Z-01': '삼정 균형',
  'Z-02': '상정 우세',
  'Z-03': '중정 우세',
  'Z-04': '하정 우세',
  'Z-05': '상-하 대립',
  'Z-06': '하-상 대립',
  'Z-07': '전면 강세',
  'Z-08': '전면 약세',
  'Z-09': '상정 강조',
  'Z-10': '하정 강조',
  'Z-11': '중정 폭 넓음',
  'Z-12': '하정 길이 긺',
  'Z-13': '하정 길이 짧음',
  // Stage 3 — Organ (오관)
  'O-EB1': '눈·눈썹 동조 강',
  'O-EB2': '눈 강 / 눈썹 약',
  'O-EB3': '눈썹 강 / 눈 약',
  'O-NM1': '코·입 동조 강',
  'O-NM2': '코 강 / 입 약',
  'O-NM3': '입 강 / 코 약',
  'O-NC': '코·턱 결합 (숭산+항산)',
  'O-EM': '눈·입 결합',
  'O-FB': '이마·눈썹 결합',
  'O-CK': '광대 강 (태산 융기)',
  'O-CB': '광대 약',
  'O-CKN': '광대+코 (중정 전면)',
  'O-CKC': '광대+턱 (말년 위엄)',
  'O-CKF': '광대+이마 (관록)',
  'O-PH1': '인중 짧음',
  'O-PH2': '인중 긺',
  'O-CH': '턱 강',
  'O-DC1': '코 등선 볼록',
  'O-DC2': '코 등선 오목',
  'O-NF1': '비전두각 완만',
  'O-NF2': '비전두각 꺾임',
  // Stage 4 — Palace (십이궁)
  'P-01': '재백궁+전택궁',
  'P-02': '관록궁+천이궁',
  'P-03': '복덕궁 조화',
  'P-04': '형제궁 (눈썹)',
  'P-05': '남녀궁',
  'P-06': '처첩궁 (눈꼬리)',
  'P-07': '질액궁 (산근)',
  'P-08': '천이궁 (이마)',
  'P-09': '명궁 (印堂 넓음)',
  'P-09B': '명궁 (印堂 좁음)',
  // Stage 5 — Age
  'A-01': '하정 이완 (50+)',
  'A-02': '상정 보존 (50+)',
  'A-03': '입꼬리 유지 (50+)',
  'A-04': '전반 이완 (50+)',
  // Stage 5 — Lateral
  'L-AQ': '매부리코',
  'L-SN': '들창코',
  'L-EL': 'E-line 전돌',
};

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

// ─── Compact z-score bar for node tree ───
class _NodeZBar extends StatelessWidget {
  final double z;
  const _NodeZBar({required this.z});

  @override
  Widget build(BuildContext context) {
    final clamped = z.clamp(-2.0, 2.0);
    final position = (clamped + 2.0) / 4.0;
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final center = width / 2;
          final markerX = position * width;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 1,
                left: 0,
                right: 0,
                child: Container(
                  height: 4,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: _Palette.shell,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: center - 0.5,
                child: Container(width: 1, height: 6, color: _Palette.amber),
              ),
              Positioned(
                top: 0,
                left: (markerX - 3).clamp(0, width - 6),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _Palette.darkBrown,
                    shape: BoxShape.circle,
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

class _ReportPageState extends ConsumerState<ReportPage> {
  bool _showMetrics = false;

  FaceReadingReport get report => widget.report;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('관상 분석'),
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
      child: Row(
        children: [
          Expanded(
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
          ),
          Builder(builder: (_) {
            final imageUrl = 'https://jicaenyzunjdlcxcdbfb.supabase.co/storage/v1/object/public/images/archetypes/${report.gender.name}.${arch.primary.name}.png';
            debugPrint('[Archetype] loading image: $imageUrl');
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: 120,
                height: 150,
                fit: BoxFit.cover,
                placeholder: (_, url) => Container(
                  width: 120,
                  height: 150,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                  ),
                ),
                errorWidget: (_, url, e) {
                  debugPrint('[Archetype] image error: $e url=$url');
                  return Container(
                    width: 120,
                    height: 150,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.image_not_supported,
                          color: Colors.white54, size: 32),
                    ),
                  );
                },
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 10 Attribute Scores (expandable with contributors) ───
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
              child: _ExpandableAttributeBar(
                attribute: e.key,
                score: e.value,
                evidence: report.attributes[e.key],
              ),
            )),
        const SizedBox(height: 16),
        _buildNodeScoreSection(),
      ],
    );
  }

  // ─── 14-node tree scores (transparency) ───
  Widget _buildNodeScoreSection() {
    if (report.nodeScores.isEmpty) return const SizedBox.shrink();

    const nodeOrder = [
      'face', 'upper', 'forehead', 'glabella', 'eyebrow',
      'middle', 'eye', 'nose', 'cheekbone', 'ear',
      'lower', 'philtrum', 'mouth', 'chin',
    ];
    const nodeLabels = {
      'face': '얼굴',
      'upper': '  상정',
      'forehead': '    이마',
      'glabella': '    미간',
      'eyebrow': '    눈썹',
      'middle': '  중정',
      'eye': '    눈',
      'nose': '    코',
      'cheekbone': '    광대',
      'ear': '    귀',
      'lower': '  하정',
      'philtrum': '    인중',
      'mouth': '    입',
      'chin': '    턱',
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _Palette.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _Palette.shell),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('부위별 균형 (14-node tree)',
              style: TextStyle(
                  color: _Palette.darkBrown,
                  fontSize: 16,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          for (final nodeId in nodeOrder)
            if (report.nodeScores.containsKey(nodeId))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        nodeLabels[nodeId] ?? nodeId,
                        style: TextStyle(
                          color: _Palette.darkBrown,
                          fontSize: 14,
                          fontWeight: nodeId == 'face' ||
                                  nodeId == 'upper' ||
                                  nodeId == 'middle' ||
                                  nodeId == 'lower'
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _NodeZBar(
                        z: report.nodeScores[nodeId]!.rollUpMeanZ,
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 44,
                      child: Text(
                        report.nodeScores[nodeId]!.rollUpMeanZ
                            .toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: _Palette.darkBrown,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
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

Widget _buildLateralCategory() {
    final lm = report.lateralMetrics;
    if (lm == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('측면(3/4)',
            style: TextStyle(
                color: _Palette.warmBrown,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...lateralMetricInfoList.map((info) {
          final metric = lm[info.id];
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
    final hasLateral = report.lateralMetrics != null;

    return Column(
      children: [
        for (final (title, cat) in categories) ...[
          _buildMetricCategory(title, cat),
          const SizedBox(height: 12),
        ],
        if (hasLateral) ...[
          _buildLateralCategory(),
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
            Text(
                'AI 관상 측정값 (${17 + (report.lateralMetrics?.length ?? 0)} Metrics)',
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
              color: AppTheme.textPrimary,
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

// ─── Save ───
  String _generateText() {
    final time = report.timestamp;
    final timeStr =
        '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    final assembled = assembleReport(report);

    final buf = StringBuffer();
    buf.writeln('=== 관상 분석 ===');
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
    buf.writeln();

    final totalMetrics =
        report.metrics.length + (report.lateralMetrics?.length ?? 0);
    buf.writeln('--- AI 관상 측정값 ($totalMetrics Metrics) ---');

    final categories = [
      ('얼굴', 'face'),
      ('눈', 'eyes'),
      ('코', 'nose'),
      ('입', 'mouth'),
    ];
    for (final (title, cat) in categories) {
      final infos = metricInfoList.where((m) => m.category == cat).toList();
      if (infos.isEmpty) continue;
      buf.writeln('[$title]');
      for (final info in infos) {
        final metric = report.metrics[info.id];
        if (metric == null) continue;
        buf.writeln(
            '  ${info.nameKo} (${info.nameEn}): score=${metric.metricScore}, z=${metric.zScore.toStringAsFixed(2)}');
      }
      buf.writeln();
    }

    final lm = report.lateralMetrics;
    if (lm != null && lm.isNotEmpty) {
      buf.writeln('[측면(3/4)]');
      for (final info in lateralMetricInfoList) {
        final metric = lm[info.id];
        if (metric == null) continue;
        buf.writeln(
            '  ${info.nameKo} (${info.nameEn}): score=${metric.metricScore}, z=${metric.zScore.toStringAsFixed(2)}');
      }
      buf.writeln();
    }

    buf.writeln('--- 참고 자료 ---');
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
    for (var i = 0; i < references.length; i++) {
      buf.writeln('${i + 1}. ${references[i]}');
    }

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

  Future<void> _showSaveOptions(BuildContext context) async {
    if (!ref.read(authProvider.notifier).isLoggedIn) {
      final loggedIn = await showLoginBottomSheet(context, ref);
      if (!loggedIn || !context.mounted) return;
    }
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
                          color: AppTheme.textPrimary)),
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
                          color: AppTheme.textPrimary)),
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
                      style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold)),
                );
              } else if (line.startsWith('---')) {
                return pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
                  child: pw.Text(line.replaceAll('-', '').trim(),
                      style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                );
              } else if (line.trim().isEmpty) {
                return pw.SizedBox(height: 6);
              } else {
                return pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 1),
                  child: pw.Text(line, style: const pw.TextStyle(fontSize: 11)),
                );
              }
            }).toList();
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
      // Same report → same filename → overwrite previous file
      final reportUuid = report.supabaseId ??
          report.timestamp.millisecondsSinceEpoch.toString();
      final filename = 'face-$reportUuid.pdf';
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
