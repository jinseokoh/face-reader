import 'dart:math' as math;

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/constants/metric_quantiles.dart';
import 'package:face_engine/data/constants/model_version.dart';
import 'package:face_engine/data/constants/symmetry_reference.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/metric_type.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/geometry_profile.dart';
import 'package:face_engine/domain/services/impression_features.dart';
import 'package:face_engine/domain/services/symmetry_metrics.dart';
import 'package:flutter/material.dart';

import '../../../core/storage/thumbnail_paths.dart';
import '../../../core/theme.dart';

/// measure 에디션(iOS v1) 리포트 본문 — APPLE.md §2.2.1 백분위·희귀도 리포트.
///
/// 서술이 없다. 숫자와 그 숫자가 동아시아 얼굴 11,800장 안에서 어디쯤인지만 말한다.
/// 순서: 고정 안내 → 첫인상 4축(근거 계측 3개씩) → 특이점 Top 3 / 평균 근접 3
/// → 정면 계측 26 표 → 측면 8 표 → 얼굴형 → 참고 자료.
class MeasureReportBody extends StatelessWidget {
  final FaceReadingReport report;

  const MeasureReportBody({super.key, required this.report});

  static const String disclaimer =
      '첫인상 지표는 공개 학술연구를 기반으로 계산한 추정치이며, 한국인 평가자를 '
      '대상으로 학습·검증된 모델이 아닙니다. 실제 성격·능력이 아니라 얼굴 형태가 '
      '기준 집단 안에서 갖는 상대 위치입니다.';

  static const List<String> references = [
    'Oosterhof & Todorov (2008) PNAS — 얼굴 평가의 두 축(신뢰감·지배력)',
    'Todorov, Dotsch, Porter, Oosterhof & Falvello (2013) Emotion — 데이터 기반 얼굴 인상 모델 검증',
    'Sutherland et al. (2013) Cognition — 자연 사진에서의 첫인상 3축',
    'Sutherland et al. (2018) PSPB — 중국·영국 평가자에서 같은 인상 축 확인',
    'Vernon, Sutherland, Young & Hartley (2014) PNAS — 랜드마크 속성의 선형 조합으로 인상 변동 58% 설명',
    'Rhodes (2006) Annual Review of Psychology — 평균성·대칭과 매력',
    'Foo, Sutherland, Burton, Nakagawa & Rhodes (2022) PSPB — 인상과 실제 특성의 상관은 약함(메타분석)',
    'AAF 동아시아 얼굴 11,800장 실측 — 계측 분위표와 첫인상 축 백분위의 기준 집단',
    '구글 미디어파이프 얼굴 메시 — 468개 랜드마크',
  ];

  List<String> get _ids => [for (final m in metricInfoList) m.id];

  Map<String, double> get _z =>
      {for (final e in report.metrics.entries) e.key: e.value.zScore};

  @override
  Widget build(BuildContext context) {
    final z = _z;
    final symZ = symmetryOverallZ(report.symmetry, report.gender);
    final profile = computeFirstImpression(z,
        gender: report.gender, referenceMetricIds: _ids, symmetryZ: symZ);
    final features =
        buildImpressionFeatures(z, referenceMetricIds: _ids, symmetryZ: symZ);
    final quant = metricQuantiles[report.gender]!;
    final profileScores = computeGeometryProfile(
        zByMetric: z, gender: report.gender, symmetry: report.symmetry);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Card(child: Text(disclaimer, style: AppText.caption)),
        const SizedBox(height: AppSpacing.xl),
        _title('첫인상'),
        const SizedBox(height: AppSpacing.md),
        for (final axis in ImpressionAxis.values) ...[
          _AxisRow(
            axis: axis,
            percentile: profile[axis],
            evidence: _topEvidence(axis, features),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        const SizedBox(height: AppSpacing.sm),
        _title('얼굴 기하학 프로필'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '영역마다 기준 집단(동아시아 얼굴 11,800장) 평균에 가까운 정도입니다. '
          '100에 가까울수록 평균에 가깝고, 대칭은 높을수록 대칭입니다. '
          '평균에서 먼 것은 드문 형태이지 나쁜 것이 아닙니다.',
          style: AppText.hint,
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            children: [
              for (final id in geometryProfileIds)
                if (profileScores[id] != null)
                  _ProfileRow(
                    name: geometryProfileNameKo[id]!,
                    score: profileScores[id]!,
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('내 얼굴의 특이점'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('평균에서 가장 먼 3개', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.sm),
              for (final id in _rankByAbsZ(z, descending: true).take(3))
                _percentLine(id, z[id]!, quant),
              const SizedBox(height: AppSpacing.lg),
              Text('평균에 가장 가까운 3개', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.sm),
              for (final id in _rankByAbsZ(z, descending: false).take(3))
                _percentLine(id, z[id]!, quant),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('정면 계측 26'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            children: [
              for (final info in metricInfoList)
                if (report.metrics[info.id] != null)
                  _MetricRow(
                    name: info.nameKo,
                    value: _formatValue(report.metrics[info.id]!.rawValue, info),
                    percentile: percentileFromQuantiles(
                        report.metrics[info.id]!.zScore, quant[info.id]!),
                    z: report.metrics[info.id]!.zScore,
                  ),
            ],
          ),
        ),
        if (report.symmetry != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _title('좌우 대칭'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '값은 좌우 짝 랜드마크의 어긋남을 얼굴 폭으로 나눈 것입니다. '
            '0%가 완전 대칭이고, 상위 N%는 대칭이 높은 쪽이 상위입니다.',
            style: AppText.hint,
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            child: Column(
              children: [
                for (final id in symmetryIds)
                  if (report.symmetry![id] != null)
                    _MetricRow(
                      name: symmetryNameKo[id]!,
                      value:
                          '${(report.symmetry![id]! * 100).toStringAsFixed(1)}%',
                      percentile: 100 -
                          percentileFromQuantiles(report.symmetry![id]!,
                              symmetryReference[report.gender]![id]!.quantiles),
                      z: -_symmetryZ(id),
                    ),
              ],
            ),
          ),
        ],
        if (report.lateralMetrics != null) ...[
          const SizedBox(height: AppSpacing.xl),
          _title('측면 계측 8'),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '측면은 정면 표본이 없어 정규 근사로 위치를 표시합니다.',
            style: AppText.hint,
          ),
          const SizedBox(height: AppSpacing.md),
          _Card(
            child: Column(
              children: [
                for (final info in lateralMetricInfoList)
                  if (report.lateralMetrics![info.id] != null)
                    _MetricRow(
                      name: info.nameKo,
                      value: _formatValue(
                          report.lateralMetrics![info.id]!.rawValue, info),
                      percentile: _normalCdf(
                              report.lateralMetrics![info.id]!.zScore) *
                          100,
                      z: report.lateralMetrics![info.id]!.zScore,
                    ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xl),
        _title('얼굴형'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Row(
            children: [
              Expanded(
                child: Text(report.faceShape.korean, style: AppText.subTitle),
              ),
              if (report.faceShapeConfidence != null)
                Text(
                  '확률 ${(report.faceShapeConfidence! * 100).round()}%',
                  style: AppText.caption,
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('참고 자료'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < references.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                      bottom: i == references.length - 1 ? 0 : AppSpacing.sm),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text('${i + 1}.', style: AppText.hint),
                      ),
                      Expanded(
                        child: Text(references[i], style: AppText.hint),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('모델 버전'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final e in _modelVersionRows)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(e.key, style: AppText.caption)),
                      Text(e.value, style: AppText.caption),
                    ],
                  ),
                ),
              if (_isStaleModel) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '이 카드는 위 버전으로 계측되었습니다. 화면의 백분위와 첫인상은 '
                  '현재 모델(${currentModelVersions().values.join(' / ')}) 기준으로 '
                  '다시 계산한 값이라 계측 당시와 다를 수 있습니다.',
                  style: AppText.hint,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  static const Map<String, String> _modelVersionLabelKo = {
    'geometry': '기하학 (계측·대칭·프로필)',
    'impression': '첫인상 (4축)',
    'pair': '두 얼굴 (닮은 정도·케미)',
  };

  /// 카드에 기록된 버전. 기록 전 카드는 현재 버전을 보여주되 "기록 없음" 을 붙인다.
  List<MapEntry<String, String>> get _modelVersionRows {
    final stored = report.modelVersion;
    final current = currentModelVersions();
    return [
      for (final e in current.entries)
        MapEntry(
          _modelVersionLabelKo[e.key]!,
          stored == null ? '${e.value} (기록 없음)' : stored[e.key] ?? '—',
        ),
    ];
  }

  bool get _isStaleModel {
    final stored = report.modelVersion;
    if (stored == null) return false;
    final current = currentModelVersions();
    return current.entries.any((e) => stored[e.key] != e.value);
  }

  /// 대칭 계측의 z (비대칭도 기준 — 양수가 더 비대칭).
  double _symmetryZ(String id) {
    final ref = symmetryReference[report.gender]![id]!;
    return (report.symmetry![id]! - ref.mean) / ref.sd;
  }

  Widget _title(String text) => Text(
        text,
        style: AppText.modalTitle.copyWith(fontWeight: FontWeight.w700),
      );

  Widget _percentLine(
      String id, double z, Map<String, List<double>> quant) {
    final info = metricInfoList.firstWhere((m) => m.id == id);
    final p = percentileFromQuantiles(z, quant[id]!);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(info.nameKo, style: AppText.body)),
          Text(_topLabel(p), style: AppText.body),
        ],
      ),
    );
  }

  /// |z| 순 정렬된 계측 id.
  Iterable<String> _rankByAbsZ(Map<String, double> z, {required bool descending}) {
    final ids = [for (final id in _ids) if (z[id] != null) id];
    ids.sort((a, b) => descending
        ? z[b]!.abs().compareTo(z[a]!.abs())
        : z[a]!.abs().compareTo(z[b]!.abs()));
    return ids;
  }

  /// 축에 기여한 근거 3개 — |부호×비중×feature| 순.
  List<_Evidence> _topEvidence(
      ImpressionAxis axis, Map<String, double> features) {
    final rows = <_Evidence>[];
    for (final link in impressionEvidence.where((l) => l.axis == axis)) {
      final f = features[link.feature];
      if (f == null) continue;
      final w = link.tier == EvidenceTier.primary ? 1.0 : 0.5;
      final c = link.sign * w * f;
      final spec = impressionFeatureSpecs
          .where((s) => s.id == link.feature)
          .firstOrNull;
      // 특징의 물리적 방향 — 계측 z 기준(feature 부호를 되돌린다).
      final String name;
      final double metricZ;
      if (spec != null) {
        name = metricInfoList.firstWhere((m) => m.id == spec.metric).nameKo;
        metricZ = f * spec.sign;
      } else if (link.feature == symmetryFeatureId) {
        name = '얼굴 대칭';
        metricZ = f;
      } else {
        name = '평균과의 거리';
        metricZ = -f;
      }
      rows.add(_Evidence(
        feature: _featurePhrase(name, metricZ),
        contribution: c,
      ));
    }
    rows.sort((a, b) => b.contribution.abs().compareTo(a.contribution.abs()));
    return rows.take(3).toList();
  }
}

class _Evidence {
  /// "눈 세로/가로 비율이 높은 편" 같은 특징 문장 (§13).
  final String feature;
  final double contribution;
  const _Evidence({required this.feature, required this.contribution});
}

/// 계측 z → "높은 편 / 낮은 편 / 기준 범위" 문장. ±0.5σ 를 경계로 쓴다.
String _featurePhrase(String name, double z) {
  if (z >= 0.5) return '$name이(가) 높은 편';
  if (z <= -0.5) return '$name이(가) 낮은 편';
  return '$name이(가) 기준 범위에 위치';
}

String _topLabel(double percentile) {
  // 백분위 p → "상위 N%" (p 가 높을수록 상위). 1~99 로 클램프.
  final top = (100 - percentile).round().clamp(1, 99);
  return '상위 $top%';
}

String _formatValue(double v, MetricInfo info) =>
    info.type == MetricType.angle ? '${v.toStringAsFixed(1)}°' : v.toStringAsFixed(3);

double _normalCdf(double z) => 0.5 * (1 + _erf(z / math.sqrt2));

// Abramowitz–Stegun 7.1.26 — 오차 1.5e-7. 측면 계측의 정규 근사 표기용.
double _erf(double x) {
  final sign = x < 0 ? -1.0 : 1.0;
  final ax = x.abs();
  const p = 0.3275911;
  const a1 = 0.254829592, a2 = -0.284496736, a3 = 1.421413741;
  const a4 = -1.453152027, a5 = 1.061405429;
  final t = 1 / (1 + p * ax);
  final y = 1 -
      (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * math.exp(-ax * ax);
  return sign * y;
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(color: AppColors.shell),
        ),
        child: child,
      );
}

/// 첫인상 축 한 줄 — 이름 · 상위 N% · 백분위 막대 · 근거 계측 3개.
class _AxisRow extends StatelessWidget {
  final ImpressionAxis axis;
  final double percentile;
  final List<_Evidence> evidence;

  const _AxisRow({
    required this.axis,
    required this.percentile,
    required this.evidence,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(axis.labelKo, style: AppText.subTitle)),
              Text(_topLabel(percentile), style: AppText.subTitle),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          _Bar(fraction: percentile / 100),
          const SizedBox(height: AppSpacing.md),
          Text('주요 관련 특징', style: AppText.hint),
          const SizedBox(height: AppSpacing.xs),
          for (final e in evidence)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(child: Text(e.feature, style: AppText.caption)),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    e.contribution >= 0 ? '이 인상을 높이는 방향' : '이 인상을 낮추는 방향',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
          Text(
            '위 특징은 이 점수의 계산에 실제로 쓰인 항목이며, 공개 학술연구에서 '
            '해당 인상과 통계적으로 연결된 것으로 보고된 방향을 따릅니다.',
            style: AppText.hint,
          ),
        ],
      ),
    );
  }
}

/// 기하학 프로필 한 줄 — 이름 · 막대 · 점수 · 상위 N% (§7·§8).
class _ProfileRow extends StatelessWidget {
  final String name;
  final double score;
  const _ProfileRow({required this.name, required this.score});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(name, style: AppText.body)),
            SizedBox(width: 120, child: _Bar(fraction: score / 100)),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 36,
              child: Text(score.round().toString(),
                  style: AppText.body, textAlign: TextAlign.right),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 64,
              child: Text(_topLabel(score),
                  style: AppText.caption, textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}

/// 계측 한 줄 — 이름 · 값 · 상위 N% · 평균(가운데) 기준 편차 막대.
class _MetricRow extends StatelessWidget {
  final String name;
  final String value;
  final double percentile;
  final double z;

  const _MetricRow({
    required this.name,
    required this.value,
    required this.percentile,
    required this.z,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(flex: 5, child: Text(name, style: AppText.caption)),
          Expanded(
            flex: 3,
            child: Text(value, style: AppText.caption, textAlign: TextAlign.right),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(flex: 4, child: _DeviationBar(z: z)),
          const SizedBox(width: AppSpacing.md),
          SizedBox(
            width: 64,
            child: Text(
              _topLabel(percentile),
              style: AppText.caption,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  const _Bar({required this.fraction});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          height: 8,
          child: Stack(
            children: [
              Container(color: AppColors.shell),
              FractionallySizedBox(
                widthFactor: fraction.clamp(0.0, 1.0),
                child: Container(color: AppColors.gold),
              ),
            ],
          ),
        ),
      );
}

/// 가운데(평균)에서 z 방향으로 뻗는 편차 막대. ±2.5σ 를 양끝으로.
class _DeviationBar extends StatelessWidget {
  final double z;
  const _DeviationBar({required this.z});

  @override
  Widget build(BuildContext context) {
    final t = (z / 2.5).clamp(-1.0, 1.0);
    return SizedBox(
      height: 8,
      child: LayoutBuilder(
        builder: (context, c) {
          final half = c.maxWidth / 2;
          final w = half * t.abs();
          return Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: AppColors.shell,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
              ),
              Positioned(
                left: t >= 0 ? half : half - w,
                width: w,
                top: 0,
                bottom: 0,
                child: Container(color: AppColors.gold),
              ),
              Positioned(
                left: half - 0.5,
                width: 1,
                top: 0,
                bottom: 0,
                child: Container(color: AppColors.textHint),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// measure 에디션 카카오 공유 카드 — 800×800. 관상 배너·서술 없이 썸네일 +
/// 첫인상 4축 + 특이점 3개. RepaintBoundary 로 캡처된다.
class MeasureShareCard extends StatelessWidget {
  final FaceReadingReport report;
  const MeasureShareCard({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final ids = [for (final m in metricInfoList) m.id];
    final z = {for (final e in report.metrics.entries) e.key: e.value.zScore};
    final profile = computeFirstImpression(z,
        gender: report.gender,
        referenceMetricIds: ids,
        symmetryZ: symmetryOverallZ(report.symmetry, report.gender));
    final quant = metricQuantiles[report.gender]!;
    final top = [for (final id in ids) if (z[id] != null) id]
      ..sort((a, b) => z[b]!.abs().compareTo(z[a]!.abs()));

    const thumbSize = 220.0;
    final thumbFile = ThumbnailPaths.cacheFileSync(report.thumbnailKey);
    final Widget thumb = thumbFile != null && thumbFile.existsSync()
        ? Image.file(thumbFile, width: thumbSize, height: thumbSize, fit: BoxFit.cover)
        : Container(
            width: thumbSize,
            height: thumbSize,
            color: AppColors.surface,
            child: const Icon(Icons.face, size: 96, color: AppColors.textHint),
          );

    return MediaQuery(
      data: const MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: AppColors.cream,
          child: SizedBox(
            width: 800,
            height: 800,
            child: Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('얼굴 측정 결과',
                      style: AppText.display.copyWith(fontSize: 40)),
                  const SizedBox(height: AppSpacing.huge),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        child: thumb,
                      ),
                      const SizedBox(width: AppSpacing.huge),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final axis in ImpressionAxis.values) ...[
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(axis.labelKo,
                                        style: AppText.sectionTitle
                                            .copyWith(fontSize: 26)),
                                  ),
                                  Text(_topLabel(profile[axis]),
                                      style: AppText.sectionTitle
                                          .copyWith(fontSize: 26)),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _Bar(fraction: profile[axis] / 100),
                              const SizedBox(height: AppSpacing.lg),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('평균에서 가장 먼 3개',
                      style: AppText.sectionTitle.copyWith(fontSize: 26)),
                  const SizedBox(height: AppSpacing.sm),
                  for (final id in top.take(3))
                    Text(
                      '${metricInfoList.firstWhere((m) => m.id == id).nameKo} — '
                      '${_topLabel(percentileFromQuantiles(z[id]!, quant[id]!))}',
                      style: AppText.body.copyWith(fontSize: 24),
                    ),
                  const Spacer(),
                  Text(MeasureReportBody.disclaimer,
                      style: AppText.hint.copyWith(fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
