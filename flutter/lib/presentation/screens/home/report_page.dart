import 'dart:io';
import 'dart:math' as math;

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/data/constants/metric_text_blocks.dart';
import 'package:face_reader/data/constants/node_text_blocks.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/models/physiognomy_tree.dart';
import 'package:face_reader/domain/services/report_assembler.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart' hide Gender;
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
                        fontWeight: FontWeight.w400)),
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
                          ? const Color(0xFFC0392B)
                          : const Color(0xFF2C5AA0),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
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

// metric id → MetricInfo lookup (frontal + lateral merged) for per-metric
// 세부 측정값 해석. 각 metric 은 higherLabel/lowerLabel 을 지닌다 — z 부호로
// 골라 노출.
final Map<String, MetricInfo> _metricInfoById = {
  for (final info in metricInfoList) info.id: info,
  for (final info in lateralMetricInfoList) info.id: info,
};

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

// ─── Compact z-score bar for node tree (heat-colored by sign/magnitude) ───
class _NodeZBar extends StatelessWidget {
  final double z;
  const _NodeZBar({required this.z});

  static Color heatColor(double z) {
    // z ∈ [-2, +2] → color. Positive = warm brown spectrum; negative = olive.
    final mag = z.abs().clamp(0.0, 2.0) / 2.0;
    if (z >= 0) {
      // shell → amber → darkBrown
      return Color.lerp(_Palette.sand, _Palette.darkBrown, mag)!;
    } else {
      // shell → lightOlive → olive
      return Color.lerp(_Palette.sand, _Palette.olive, mag)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final clamped = z.clamp(-2.0, 2.0);
    final position = (clamped + 2.0) / 4.0;
    final markerColor = heatColor(z);
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
                    color: markerColor,
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

// ─── Node Bar (always-expanded: 관상학 해석 + metric z 리스트 전부 노출) ───
//
// 14-node tree 의 각 노드(root·zone·leaf) 는 z-band(high/mid/low) 에 맞는
// 전통 관상 해석 본문과 귀속된 metric 의 z-score 를 항상 펼쳐서 렌더한다.
// 본문 SSOT: `lib/data/constants/node_text_blocks.dart`.
class _NodeBar extends StatelessWidget {
  final String nodeId;
  final String label;
  final double z;
  final Gender gender;
  final Map<String, MetricResult> metrics;
  final Map<String, MetricResult>? lateralMetrics;
  final List<String> metricIds;
  final bool isZone;
  final bool isRoot;
  final bool supported;

  const _NodeBar({
    required this.nodeId,
    required this.label,
    required this.z,
    required this.gender,
    required this.metrics,
    this.lateralMetrics,
    required this.metricIds,
    this.isZone = false,
    this.isRoot = false,
    this.supported = true,
  });

  @override
  Widget build(BuildContext context) {
    final isLeaf = !isZone && !isRoot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 84,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: isLeaf ? Colors.transparent : _Palette.darkBrown,
                      borderRadius: BorderRadius.circular(4),
                      border: isLeaf
                          ? Border.all(color: _Palette.darkBrown, width: 1)
                          : null,
                    ),
                    child: Text(
                      label.trim(),
                      style: TextStyle(
                        color: isLeaf ? _Palette.darkBrown : _Palette.cream,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: _NodeZBar(z: z)),
              const SizedBox(width: 6),
              SizedBox(
                width: 48,
                child: Text(
                  '${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: z >= 0
                        ? const Color(0xFFC0392B)
                        : const Color(0xFF2C5AA0),
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildBody(),
      ],
    );
  }

  Widget _buildBody() {
    final block = nodeBlockForZ(nodeId, z);
    final body = block != null ? resolveNodeBody(block, gender) : '';

    final metricRows = <Widget>[];
    if (supported) {
      // count visible first so we can drop trailing padding on the last row.
      var visibleTotal = 0;
      for (final mid in metricIds) {
        if ((metrics[mid] ?? lateralMetrics?[mid]) != null) visibleTotal++;
      }
      var visibleIndex = 0;
      for (final mid in metricIds) {
        final m = metrics[mid] ?? lateralMetrics?[mid];
        if (m == null) continue;
        final isLastMetric = (++visibleIndex) == visibleTotal;
        final zm = m.zScore;
        final info = _metricInfoById[mid];
        final label =
            info?.nameKo ?? metricDisplayLabels[mid] ?? mid;
        // z 부호 → higherLabel/lowerLabel. |z| ≲ 0.35 는 평균권 → 중립 문구.
        final String interp;
        if (info == null) {
          interp = '';
        } else if (zm.abs() < 0.35) {
          interp = '평균 수준';
        } else {
          interp = zm >= 0 ? info.higherLabel : info.lowerLabel;
        }
        // metric-level 관상학 해석 본문 (metricBodyForZ).
        final String? metricBody = metricBodyForZ(mid, zm);
        final valueColor = zm >= 0
            ? const Color(0xFFC0392B) // warm red for +
            : const Color(0xFF2C5AA0); // cool blue for −
        metricRows.add(
          Padding(
            padding: EdgeInsets.only(bottom: isLastMetric ? 0 : 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          color: _Palette.darkBrown,
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${zm >= 0 ? '+' : ''}${zm.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: valueColor,
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
                if (interp.isNotEmpty && metricBody == null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 2),
                    child: Text(
                      interp,
                      style: TextStyle(
                        color: _Palette.warmBrown,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ),
                if (metricBody != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, left: 2, right: 2),
                    child: Text(
                      metricBody,
                      style: TextStyle(
                        color: _Palette.warmBrown,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    }

    // combo rules — 같은 노드 scope 내 trigger 된 조합 해석.
    final zMap = <String, double>{};
    for (final mid in metricIds) {
      final m = metrics[mid] ?? lateralMetrics?[mid];
      if (m != null) zMap[mid] = m.zScore;
    }
    final combos = triggeredCombos(metricIds, zMap);

    if (body.isEmpty && metricRows.isEmpty && combos.isEmpty) {
      return const SizedBox(height: 6);
    }

    // Spacing rhythm (통일):
    //   · 인접 섹션 사이 (body / 세부 측정값 / 부위 해석 조합): 14
    //   · 서브 타이틀 → 첫 항목: 8
    //   · 항목과 항목 사이: 8 (마지막 항목은 trailing 0)
    //   · 노드 외곽 bottom: 0 — 바깥쪽에서 통일된 inter-node 간격으로 제어.
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (body.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _Palette.shell.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                body,
                style: TextStyle(
                  color: _Palette.warmBrown,
                  fontSize: 15,
                  height: 1.65,
                ),
              ),
            ),
          if (metricRows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '세부 측정값',
              style: TextStyle(
                color: _Palette.darkBrown,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...metricRows,
          ],
          if (combos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              '부위 해석 조합',
              style: TextStyle(
                color: _Palette.darkBrown,
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 8),
            for (int ci = 0; ci < combos.length; ci++)
              Padding(
                padding:
                    EdgeInsets.only(bottom: ci == combos.length - 1 ? 0 : 8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _Palette.shell.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 2, right: 8),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 16,
                          color: _Palette.amber,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          combos[ci].body,
                          style: TextStyle(
                            color: _Palette.warmBrown,
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ─── 삼정 Radar (3-axis: 상정·중정·하정 rollUpMeanZ) ───
class _SamjeongRadar extends StatelessWidget {
  final double upper;
  final double middle;
  final double lower;

  const _SamjeongRadar({
    required this.upper,
    required this.middle,
    required this.lower,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1.3,
      child: CustomPaint(
        painter: _SamjeongRadarPainter(
          upper: upper,
          middle: middle,
          lower: lower,
        ),
      ),
    );
  }
}

class _SamjeongRadarPainter extends CustomPainter {
  final double upper;
  final double middle;
  final double lower;

  _SamjeongRadarPainter({
    required this.upper,
    required this.middle,
    required this.lower,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2 + 6);
    final maxR = math.min(size.width, size.height) * 0.38;

    // z ∈ [-2, +2] → radius [0, maxR]. Center = z=-2, outer = z=+2.
    double zToR(double z) {
      final clamped = z.clamp(-2.0, 2.0);
      return ((clamped + 2.0) / 4.0) * maxR;
    }

    // Axis angles: 상정 top (-π/2), 중정 bottom-right (+π/6), 하정 bottom-left (5π/6).
    const upperAngle = -math.pi / 2;
    const middleAngle = math.pi / 6;
    const lowerAngle = 5 * math.pi / 6;

    Offset pt(double angle, double r) =>
        center + Offset(math.cos(angle) * r, math.sin(angle) * r);

    // Grid rings at z = -2, -1, 0, 1, 2.
    final gridPaint = Paint()
      ..color = _Palette.sand.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final z in const [-2.0, -1.0, 0.0, 1.0, 2.0]) {
      final r = zToR(z);
      final path = Path()
        ..moveTo(pt(upperAngle, r).dx, pt(upperAngle, r).dy)
        ..lineTo(pt(middleAngle, r).dx, pt(middleAngle, r).dy)
        ..lineTo(pt(lowerAngle, r).dx, pt(lowerAngle, r).dy)
        ..close();
      canvas.drawPath(path, gridPaint);
    }

    // Axes.
    final axisPaint = Paint()
      ..color = _Palette.warmBrown.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    for (final a in const [upperAngle, middleAngle, lowerAngle]) {
      canvas.drawLine(center, pt(a, maxR), axisPaint);
    }

    // Neutral (z=0) ring highlight.
    final neutralPaint = Paint()
      ..color = _Palette.amber.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final neutralR = zToR(0.0);
    final neutralPath = Path()
      ..moveTo(pt(upperAngle, neutralR).dx, pt(upperAngle, neutralR).dy)
      ..lineTo(pt(middleAngle, neutralR).dx, pt(middleAngle, neutralR).dy)
      ..lineTo(pt(lowerAngle, neutralR).dx, pt(lowerAngle, neutralR).dy)
      ..close();
    canvas.drawPath(neutralPath, neutralPaint);

    // Data polygon.
    final dataU = pt(upperAngle, zToR(upper));
    final dataM = pt(middleAngle, zToR(middle));
    final dataL = pt(lowerAngle, zToR(lower));
    final dataPath = Path()
      ..moveTo(dataU.dx, dataU.dy)
      ..lineTo(dataM.dx, dataM.dy)
      ..lineTo(dataL.dx, dataL.dy)
      ..close();

    final fillPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xCC5C4033),
          Color(0x667B5B3A),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawPath(dataPath, fillPaint);

    final strokePaint = Paint()
      ..color = _Palette.darkBrown
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(dataPath, strokePaint);

    // Data dots.
    final dotPaint = Paint()..color = _Palette.darkBrown;
    for (final p in [dataU, dataM, dataL]) {
      canvas.drawCircle(p, 3.5, Paint()..color = Colors.white);
      canvas.drawCircle(p, 3, dotPaint);
    }

    // Axis labels (relative position outside ring).
    void drawLabel(double angle, String zone, double z) {
      final labelCenter = pt(angle, maxR + 22);
      final tp = TextPainter(
        text: TextSpan(
          children: [
            TextSpan(
              text: '$zone\n',
              style: const TextStyle(
                color: _Palette.darkBrown,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            TextSpan(
              text: '${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}',
              style: TextStyle(
                color: z >= 0
                    ? const Color(0xFFC0392B)
                    : const Color(0xFF2C5AA0),
                fontSize: 12,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(labelCenter.dx - tp.width / 2, labelCenter.dy - tp.height / 2),
      );
    }

    drawLabel(upperAngle, '상정', upper);
    drawLabel(middleAngle, '중정', middle);
    drawLabel(lowerAngle, '하정', lower);
  }

  @override
  bool shouldRepaint(covariant _SamjeongRadarPainter old) =>
      old.upper != upper || old.middle != middle || old.lower != lower;
}

class _ReportPageState extends ConsumerState<ReportPage> {
  bool _showNodeDetails = false;

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
          _buildNodeScoreSection(),
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
      ],
    );
  }

  // ─── 14-node tree scores (transparency) ───
  Widget _buildNodeScoreSection() {
    if (report.nodeScores.isEmpty) return const SizedBox.shrink();

    // 귀(ear) 는 정면 메시에서 측정되지 않는 unsupported 노드 — UI 에서 완전 제외.
    const nodeOrder = [
      'face', 'upper', 'forehead', 'glabella', 'eyebrow',
      'middle', 'eye', 'nose', 'cheekbone',
      'lower', 'philtrum', 'mouth', 'chin',
    ];
    const nodeLabels = {
      'face': '얼굴',
      'upper': '상정',
      'forehead': '이마',
      'glabella': '미간',
      'eyebrow': '눈썹',
      'middle': '중정',
      'eye': '눈',
      'nose': '코',
      'cheekbone': '광대',
      'lower': '하정',
      'philtrum': '인중',
      'mouth': '입',
      'chin': '턱',
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
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () =>
                setState(() => _showNodeDetails = !_showNodeDetails),
            child: Row(
              children: [
                Text('부위별 상세 해석',
                    style: TextStyle(
                        color: _Palette.darkBrown,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                Icon(
                  _showNodeDetails
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: _Palette.warmBrown,
                ),
              ],
            ),
          ),
          if (_showNodeDetails) ...[
            const SizedBox(height: 14),
            if (report.nodeScores.containsKey('upper') &&
                report.nodeScores.containsKey('middle') &&
                report.nodeScores.containsKey('lower'))
              _SamjeongRadar(
                upper: report.nodeScores['upper']!.rollUpMeanZ,
                middle: report.nodeScores['middle']!.rollUpMeanZ,
                lower: report.nodeScores['lower']!.rollUpMeanZ,
              ),
            // 모든 노드 사이에 통일된 14px 간격.
            for (final nodeId in nodeOrder)
              if (report.nodeScores.containsKey(nodeId)) ...[
                const SizedBox(height: 14),
                _NodeBar(
                  nodeId: nodeId,
                  label: nodeLabels[nodeId] ?? nodeId,
                  z: report.nodeScores[nodeId]!.rollUpMeanZ,
                  gender: report.gender,
                  metrics: report.metrics,
                  lateralMetrics: report.lateralMetrics,
                  metricIds: nodeById[nodeId]?.metricIds ?? const [],
                  isZone: nodeId == 'upper' ||
                      nodeId == 'middle' ||
                      nodeId == 'lower',
                  isRoot: nodeId == 'face',
                  supported: nodeId != 'ear',
                ),
              ],
          ],
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

// ─── Save ───
  //
  // Markers the PDF renderer understands:
  //   `=== 제목 ===`  → H1 (22pt bold)
  //   `--- 섹션 ---`  → H2 (16pt bold)
  //   `▶ 노드 …`      → node header (14pt bold, 좌측 바)
  //   `  · …`         → indented metric line (11pt)
  //   `  ◉ …`         → indented combo line (11pt)
  //   그 외            → body paragraph (11pt)
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

    buf.writeln('--- 관상 해석 ---');
    buf.writeln(assembled.assembledText);
    buf.writeln();

    // 부위별 상세 해석 — UI `_NodeBar` 와 동일한 본문/세부 측정값/조합.
    // nodeOrder / nodeLabels 는 `_buildNodeScoreSection` 과 일치.
    const nodeOrder = [
      'face', 'upper', 'forehead', 'glabella', 'eyebrow',
      'middle', 'eye', 'nose', 'cheekbone',
      'lower', 'philtrum', 'mouth', 'chin',
    ];
    const nodeLabels = {
      'face': '얼굴',
      'upper': '상정',
      'forehead': '이마',
      'glabella': '미간',
      'eyebrow': '눈썹',
      'middle': '중정',
      'eye': '눈',
      'nose': '코',
      'cheekbone': '광대',
      'lower': '하정',
      'philtrum': '인중',
      'mouth': '입',
      'chin': '턱',
    };

    buf.writeln('--- 부위별 상세 해석 ---');
    buf.writeln();

    // 삼정 요약 (radar 를 텍스트로 치환).
    final upperZ = report.nodeScores['upper']?.rollUpMeanZ;
    final middleZ = report.nodeScores['middle']?.rollUpMeanZ;
    final lowerZ = report.nodeScores['lower']?.rollUpMeanZ;
    if (upperZ != null && middleZ != null && lowerZ != null) {
      buf.writeln(
          '삼정 균형 — 상정 ${_fmtZ(upperZ)} · 중정 ${_fmtZ(middleZ)} · 하정 ${_fmtZ(lowerZ)}');
      buf.writeln();
    }

    for (final nodeId in nodeOrder) {
      final score = report.nodeScores[nodeId];
      if (score == null) continue;
      final label = nodeLabels[nodeId] ?? nodeId;
      final z = score.rollUpMeanZ;

      buf.writeln('▶ $label (z ${_fmtZ(z)})');

      final block = nodeBlockForZ(nodeId, z);
      final body = block != null ? resolveNodeBody(block, report.gender) : '';
      if (body.isNotEmpty) {
        buf.writeln(body);
      }

      // leaf 노드 세부 측정값 (zone/root 는 metricIds 없음).
      final metricIds = nodeById[nodeId]?.metricIds ?? const <String>[];
      final zMap = <String, double>{};
      for (final mid in metricIds) {
        final m = report.metrics[mid] ?? report.lateralMetrics?[mid];
        if (m == null) continue;
        zMap[mid] = m.zScore;
        final info = _metricInfoById[mid];
        final zm = m.zScore;
        final mLabel = info?.nameKo ?? metricDisplayLabels[mid] ?? mid;
        final interp = info == null
            ? ''
            : (zm.abs() < 0.35
                ? '평균 수준'
                : (zm >= 0 ? info.higherLabel : info.lowerLabel));
        final metricBody = metricBodyForZ(mid, zm);
        final tail = metricBody ?? (interp.isNotEmpty ? interp : '');
        buf.writeln(tail.isEmpty
            ? '  · $mLabel (${_fmtZ(zm)})'
            : '  · $mLabel (${_fmtZ(zm)}) — $tail');
      }

      // 조합 해석 (triggeredCombos).
      final combos = triggeredCombos(metricIds, zMap);
      for (final combo in combos) {
        buf.writeln('  ◉ ${combo.body}');
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

  static String _fmtZ(double z) =>
      '${z >= 0 ? '+' : ''}${z.toStringAsFixed(2)}';

  /// Render one text line into a PDF widget based on its marker prefix.
  /// Markers mirror `_generateText`:
  ///   `===` H1, `---` H2, `▶` node header, `  ·` metric, `  ◉` combo.
  static pw.Widget _renderPdfLine(String line) {
    if (line.startsWith('===')) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4, bottom: 10),
        child: pw.Text(
          line.replaceAll('=', '').trim(),
          style:
              pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
      );
    }
    if (line.startsWith('---')) {
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              line.replaceAll('-', '').trim(),
              style: pw.TextStyle(
                  fontSize: 15, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 2),
            pw.Container(
              height: 0.6,
              color: PdfColor.fromInt(0xFF5C4033),
            ),
          ],
        ),
      );
    }
    if (line.startsWith('▶')) {
      final text = line.substring(1).trim();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 10, bottom: 3),
        child: pw.Container(
          padding:
              const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFEDE5D5),
            borderRadius: pw.BorderRadius.circular(3),
          ),
          child: pw.Text(
            text,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromInt(0xFF5C4033),
            ),
          ),
        ),
      );
    }
    if (line.startsWith('  · ')) {
      return pw.Padding(
        padding:
            const pw.EdgeInsets.only(left: 14, top: 1, bottom: 1, right: 0),
        child: pw.Text(
          '· ${line.substring(4)}',
          style: pw.TextStyle(
              fontSize: 10.5, color: PdfColor.fromInt(0xFF7B5B3A)),
        ),
      );
    }
    if (line.startsWith('  ◉ ')) {
      // NotoSerifKR 는 italic variant 가 없어 italic 지정 시 한글이 Helvetica
      // 로 fallback → tofu. 색상으로만 구분한다. 또한 Geometric Shapes 의
      // ◉ 역시 CJK serif 에 없어 ※ 로 치환.
      return pw.Padding(
        padding:
            const pw.EdgeInsets.only(left: 14, top: 2, bottom: 2),
        child: pw.Text(
          '※ ${line.substring(4)}',
          style: pw.TextStyle(
            fontSize: 10.5,
            color: PdfColor.fromInt(0xFF9B7B4F),
          ),
        ),
      );
    }
    if (line.trim().isEmpty) {
      return pw.SizedBox(height: 6);
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.5),
      child: pw.Text(
        line,
        style: const pw.TextStyle(fontSize: 11, lineSpacing: 2.5),
      ),
    );
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
          margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 40),
          build: (pw.Context ctx) {
            return lines.map(_renderPdfLine).toList();
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

