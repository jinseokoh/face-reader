import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/data/constants/impression_evidence.dart';
import 'package:face_engine/data/constants/metric_quantiles.dart';
import 'package:face_engine/domain/services/first_impression.dart';
import 'package:face_engine/domain/services/geometry_profile.dart';
import 'package:face_engine/domain/services/landmark_normalize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../core/storage/thumbnail_paths.dart';
import '../../../core/theme.dart';
import '../../widgets/landmark_mesh_painter.dart';
import '../../../domain/services/pair_score.dart';
import '../../widgets/detail_avatar.dart';
import '../../widgets/source_badge.dart';

/// measure 에디션 두 얼굴 비교 본문 — APPLE.md §81.3.
///
/// 궁합 등급·오행·서술이 없다. 케미 합(0~300)과 그 세 성분, 첫인상 유사도,
/// 영역별 닮은 정도, 두 사람의 첫인상 3축 나란히, 가장 닮은/다른 계측 3개.
class MeasurePairBody extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;

  const MeasurePairBody({super.key, required this.my, required this.album});

  static const String disclaimer =
      '두 얼굴 비교는 얼굴 형태와 첫인상 프로필의 관계를 계산한 결과이며, 실제 '
      '연애·결혼·인간관계의 성공 여부를 예측하지 않습니다. 조화도는 제품 정의 '
      '지표로 학술 검증을 거치지 않았습니다.';

  static const Map<String, String> regionKo = {
    'outline': '윤곽',
    'eyes': '눈',
    'brows': '눈썹',
    'nose': '코',
    'mouth': '입',
    'jaw': '턱선',
  };

  @override
  Widget build(BuildContext context) {
    final pair = analyzePairReports(my, album);
    // §25 — 닮은 부분(내림차순) / 다른 부분(오름차순).
    final regions = pair.similarity.byRegion.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final similarRegions = [
      for (final e in regions)
        if (similarityBandOf(e.key, e.value).isSimilar) e,
    ];
    final differentRegions = [
      for (final e in regions.reversed)
        if (!similarityBandOf(e.key, e.value).isSimilar) e,
    ];
    // §24 — 정규화 + Procrustes 정렬 (저장된 원본 좌표에서 계산).
    final aligned = alignFaces(my.landmarks, album.landmarks);
    final pa = impressionOf(my);
    final pb = impressionOf(album);
    final ca = axisContributionsOf(my);
    final cb = axisContributionsOf(album);
    final sameDev = sharedDeviations(my, album, sameDirection: true).take(3);
    final oppDev = sharedDeviations(my, album, sameDirection: false).take(3);
    final symA = computeGeometryProfile(
        zByMetric: zMapOf(my), gender: my.gender, symmetry: my.symmetry)['symmetry'];
    final symB = computeGeometryProfile(
        zByMetric: zMapOf(album),
        gender: album.gender,
        symmetry: album.symmetry)['symmetry'];
    final myAlias = my.alias ?? '나';
    final albumAlias = album.alias ?? '상대';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Hero(
          my: my,
          album: album,
          myAlias: myAlias,
          albumAlias: albumAlias,
          chemistry: pair.chemistry,
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('케미 점수의 세 성분'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            children: [
              _ScoreRow(label: '조화도', value: pair.harmony, note: '가설 지표'),
              _ScoreRow(label: '보완도', value: pair.complementarity),
              _ScoreRow(label: '닮은 정도', value: pair.similarity.overall),
              const Divider(height: AppSpacing.xl),
              _ScoreRow(label: '첫인상 유사도', value: pair.impressionSimilarity),
              const SizedBox(height: AppSpacing.md),
              Text(
                '무작위로 만난 두 사람과 비교하면 닮은 정도는 상위 '
                '${_topPct(pairSimilarityPercentile(pair.similarity.overall))}, '
                '케미 점수는 상위 ${_topPct(chemistryPercentile(pair.chemistry))}입니다. '
                '기준은 동아시아 얼굴 11,800장에서 무작위로 고른 두 사람 2만 쌍입니다.',
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('두 얼굴 겹쳐 보기'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '사진 속 위치·크기·기울기는 빼고 두 얼굴의 모양만 남겨 겹친 모습입니다. '
          '닮은 부분으로 분류된 영역은 진하게 그리고, 두 얼굴의 같은 점이 벌어진 '
          '자리는 두 점을 잇는 선으로 표시합니다. 선이 길고 진할수록 그 자리가 다릅니다.',
          style: AppText.hint,
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: LandmarkMeshPainter(
                    a: aligned.a,
                    b: aligned.bAligned,
                    highlight: {for (final e in similarRegions) e.key},
                    showPointDiff: true,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LegendDot(color: AppColors.gold, label: myAlias),
                  const SizedBox(width: AppSpacing.xl),
                  _LegendDot(color: AppColors.info, label: albumAlias),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('영역별 닮은 정도'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '문구의 경계는 동아시아 얼굴 11,800장에서 무작위로 고른 두 사람의 '
          '닮은 정도 분포(상위 25%·50%·75%)입니다.',
          style: AppText.hint,
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (similarRegions.isNotEmpty) ...[
                Text('닮은 부분', style: AppText.subTitle),
                const SizedBox(height: AppSpacing.sm),
                for (final e in similarRegions)
                  _ScoreRow(
                    label: regionKo[e.key] ?? e.key,
                    value: e.value,
                    note: similarityBandOf(e.key, e.value).labelKo,
                  ),
              ],
              if (similarRegions.isNotEmpty && differentRegions.isNotEmpty)
                const SizedBox(height: AppSpacing.lg),
              if (differentRegions.isNotEmpty) ...[
                Text('다른 부분', style: AppText.subTitle),
                const SizedBox(height: AppSpacing.sm),
                for (final e in differentRegions)
                  _ScoreRow(
                    label: regionKo[e.key] ?? e.key,
                    value: e.value,
                    note: similarityBandOf(e.key, e.value).labelKo,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('두 사람의 첫인상'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            children: [
              _namesHeader(myAlias, albumAlias),
              const SizedBox(height: AppSpacing.sm),
              for (final axis in pairAxes) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 2,
                          child: Text(axis.labelKo, style: AppText.body)),
                      for (final v in [_top(pa[axis]), _top(pb[axis])])
                        Expanded(
                          flex: 3,
                          child: Text(v,
                              style: AppText.body, textAlign: TextAlign.right),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    _axisDiffSentence(axis, pa, pb, ca, cb, myAlias, albumAlias),
                    style: AppText.caption,
                  ),
                ),
              ],
              const Divider(height: AppSpacing.xl),
              Text('조화도에서 리드하는 쪽', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '조화도는 축마다 두 사람 중 높은 쪽을 취해 평균합니다. 축마다 리드하는 쪽입니다.',
                style: AppText.hint,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final axis in pairAxes)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Expanded(child: Text(axis.labelKo, style: AppText.body)),
                      Text(
                        (pa[axis] - pb[axis]).abs() < 1
                            ? '둘이 같음'
                            : (pa[axis] > pb[axis] ? myAlias : albumAlias),
                        style: AppText.body,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('같이 튀는 곳과 반대로 튀는 곳'),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '두 사람 모두 기준 집단 평균에서 1σ 이상 떨어진 계측입니다. 같은 방향이면 '
          '둘의 공통된 특징, 반대 방향이면 서로 다른 특징입니다.',
          style: AppText.hint,
        ),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('같이 튀는 곳', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.sm),
              if (sameDev.isEmpty)
                Text('없음', style: AppText.body)
              else
                for (final id in sameDev)
                  _devLine(id, '둘 다 ${zMapOf(my)[id]! > 0 ? '높은' : '낮은'} 편'),
              const SizedBox(height: AppSpacing.lg),
              Text('반대로 튀는 곳', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.sm),
              if (oppDev.isEmpty)
                Text('없음', style: AppText.body)
              else
                for (final id in oppDev)
                  _devLine(
                    id,
                    '$myAlias ${zMapOf(my)[id]! > 0 ? '높은' : '낮은'} 편, '
                    '$albumAlias ${zMapOf(album)[id]! > 0 ? '높은' : '낮은'} 편',
                  ),
              const SizedBox(height: AppSpacing.md),
              Text(
                _deviationSentence(sameDev.toList(), oppDev.toList(), myAlias,
                    albumAlias),
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('대칭과 얼굴형'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            children: [
              _namesHeader(myAlias, albumAlias),
              const SizedBox(height: AppSpacing.sm),
              _twoColumn('얼굴 대칭', symA == null ? '—' : _top(symA),
                  symB == null ? '—' : _top(symB)),
              _twoColumn('얼굴형', my.faceShape.korean, album.faceShape.korean),
              const SizedBox(height: AppSpacing.md),
              Text(
                '${_symmetrySentence(symA, symB, myAlias, albumAlias)} '
                '${_faceShapeSentence(pair, myAlias, albumAlias)}',
                style: AppText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _title('계측으로 본 닮은 곳과 다른 곳'),
        const SizedBox(height: AppSpacing.md),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('가장 닮은 3개', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.sm),
              for (final id in rankMetricsByDifference(my, album, mostSimilar: true).take(3))
                _metricLine(id, myAlias, albumAlias),
              const SizedBox(height: AppSpacing.lg),
              Text('가장 다른 3개', style: AppText.subTitle),
              const SizedBox(height: AppSpacing.sm),
              for (final id in rankMetricsByDifference(my, album, mostSimilar: false).take(3))
                _metricLine(id, myAlias, albumAlias),
              const SizedBox(height: AppSpacing.md),
              Text(
                '닮은 3개는 두 사람의 기준 집단 위치가 가장 가까운 계측, 다른 3개는 가장 '
                '먼 계측입니다. 각 계측 아래에 그 계측이 들어가는 첫인상 축을 적었습니다. '
                '다른 계측이 어느 축에 들어가면 그 축의 첫인상 차이로 이어집니다.',
                style: AppText.hint,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _Card(child: Text(disclaimer, style: AppText.caption)),
      ],
    );
  }

  Widget _title(String text) => Text(
        text,
        style: AppText.modalTitle.copyWith(fontWeight: FontWeight.w700),
      );

  /// 축 하나의 두 사람 차이 문장 (§13 식) — 백분위 차 5 미만이면 비슷함.
  String _axisDiffSentence(
    ImpressionAxis axis,
    FirstImpressionProfile pa,
    FirstImpressionProfile pb,
    Map<ImpressionAxis, Map<String, double>> ca,
    Map<ImpressionAxis, Map<String, double>> cb,
    String nameA,
    String nameB,
  ) {
    final diff = pa[axis] - pb[axis];
    if (diff.abs() < 5) return '두 사람이 비슷합니다.';
    final strong = diff > 0 ? nameA : nameB;
    final weak = diff > 0 ? nameB : nameA;
    // 차이를 가장 크게 만든 feature 2개 — 기여 차이 순.
    final keys = {...ca[axis]!.keys, ...cb[axis]!.keys}.toList()
      ..sort((x, y) => ((ca[axis]![y] ?? 0) - (cb[axis]![y] ?? 0))
          .abs()
          .compareTo(((ca[axis]![x] ?? 0) - (cb[axis]![x] ?? 0)).abs()));
    final drivers = keys.take(2).map(featureNameKo).join(', ');
    return '$strong 쪽이 $weak 쪽보다 이 인상이 강합니다. 차이를 만든 계측: $drivers.';
  }

  Widget _devLine(String id, String phrase) {
    final info = metricInfoList.firstWhere((m) => m.id == id);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(info.nameKo, style: AppText.body)),
              Text(phrase, style: AppText.caption),
            ],
          ),
          Text(_axesLabel(id), style: AppText.hint),
        ],
      ),
    );
  }

  /// 계측이 들어가는 첫인상 축 — 없으면 그렇다고 적는다.
  String _axesLabel(String id) {
    final axes = axesForMetric(id);
    if (axes.isEmpty) return '첫인상 축에는 직접 들어가지 않는 계측';
    return '관련 첫인상: ${axes.map((a) => a.labelKo).join(', ')}';
  }

  /// 같이/반대로 튀는 곳의 뜻 — 개수와 축 관여로만 말한다.
  String _deviationSentence(
      List<String> same, List<String> opp, String nameA, String nameB) {
    if (same.isEmpty && opp.isEmpty) {
      return '두 사람 모두 평균에서 1σ 이상 벗어난 계측이 겹치지 않습니다. 튀는 자리가 '
          '서로 다른 얼굴입니다.';
    }
    final parts = <String>[];
    if (same.isNotEmpty) {
      final axes = {for (final id in same) ...axesForMetric(id)};
      parts.add('같은 방향으로 튀는 계측 ${same.length}개는 두 사람이 공통으로 가진 특징이라 '
          '닮은 정도를 올리는 쪽입니다'
          '${axes.isEmpty ? '.' : ', 첫인상에서는 ${axes.map((a) => a.labelKo).join(', ')}에 같은 방향으로 작용합니다.'}');
    }
    if (opp.isNotEmpty) {
      final axes = {for (final id in opp) ...axesForMetric(id)};
      parts.add('반대로 튀는 계측 ${opp.length}개는 두 사람이 서로 다른 쪽으로 가진 특징이라 '
          '보완도에 기여합니다'
          '${axes.isEmpty ? '.' : ', 첫인상에서는 ${axes.map((a) => a.labelKo).join(', ')}에서 $nameA 쪽과 $nameB 쪽이 갈립니다.'}');
    }
    return parts.join(' ');
  }

  /// 대칭 해석 — 두 사람의 위치와 차이. 대칭은 매력·신뢰감 축의 feature 다.
  String _symmetrySentence(
      double? symA, double? symB, String nameA, String nameB) {
    if (symA == null || symB == null) return '';
    final diff = (symA - symB).abs();
    final both = symA >= 75 && symB >= 75;
    if (diff < 10) {
      return both
          ? '두 사람 모두 얼굴 대칭이 높은 편이고 수준도 비슷합니다.'
          : '두 사람의 얼굴 대칭 수준이 비슷합니다.';
    }
    final higher = symA > symB ? nameA : nameB;
    return '$higher 쪽이 얼굴 대칭이 더 높습니다. 대칭은 매력적인 인상과 신뢰감 있는 인상 '
        '축에 들어가는 특징입니다.';
  }

  /// 얼굴형 해석 — 같은지 다른지와 윤곽 영역 닮은 정도로 말한다.
  String _faceShapeSentence(PairAnalysis pair, String nameA, String nameB) {
    final same = my.faceShape == album.faceShape;
    final outline = pair.similarity.byRegion['outline'];
    final tail = outline == null
        ? ''
        : ' 윤곽 영역의 닮은 정도는 ${outline.round()}'
            '(${similarityBandOf('outline', outline).labelKo})입니다.';
    return same
        ? '얼굴형은 둘 다 ${my.faceShape.korean}으로 같습니다.$tail'
        : '얼굴형은 $nameA ${my.faceShape.korean}, $nameB ${album.faceShape.korean}으로 다릅니다.$tail';
  }

  /// 두 사람 이름 헤더 — '두 사람의 첫인상'·'대칭과 얼굴형' 공용. 칸 비율 2 : 3 : 3.
  Widget _namesHeader(String a, String b) => Row(
        children: [
          const Expanded(flex: 2, child: SizedBox()),
          for (final name in [a, b])
            Expanded(
              flex: 3,
              child: Text(name,
                  style: AppText.caption,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
        ],
      );

  /// 값 칸은 줄바꿈하지 않는다 — "세로로 긴 얼굴형" 같은 긴 라벨은 폭이 모자라면
  /// 글자를 줄여 한 줄에 맞춘다.
  Widget _twoColumn(String label, String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(flex: 2, child: Text(label, style: AppText.body)),
            for (final v in [a, b])
              Expanded(
                flex: 3,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(v, style: AppText.body, maxLines: 1, softWrap: false),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _metricLine(String id, String nameA, String nameB) {
    final info = metricInfoList.firstWhere((m) => m.id == id);
    final quantA = metricQuantiles[my.gender]![id]!;
    final quantB = metricQuantiles[album.gender]![id]!;
    final topA = _top(percentileFromQuantiles(zMapOf(my)[id]!, quantA));
    final topB = _top(percentileFromQuantiles(zMapOf(album)[id]!, quantB));
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(info.nameKo, style: AppText.body)),
              Text('$nameA $topA, $nameB $topB', style: AppText.caption),
            ],
          ),
          Text(_axesLabel(id), style: AppText.hint),
        ],
      ),
    );
  }
}

String _top(double percentile) =>
    '상위 ${(100 - percentile).round().clamp(1, 99)}%';

String _topPct(double percentile) =>
    '${(100 - percentile).round().clamp(1, 99)}%';

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

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(label, style: AppText.caption),
        ],
      );
}

class _ScoreRow extends StatelessWidget {
  final String label;
  final double value;
  final String? note;
  const _ScoreRow({required this.label, required this.value, this.note});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Expanded(child: Text(label, style: AppText.body)),
            if (note != null) ...[
              Text(note!, style: AppText.hint),
              const SizedBox(width: AppSpacing.sm),
            ],
            SizedBox(
              width: 120,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  height: 8,
                  child: Stack(
                    children: [
                      Container(color: AppColors.shell),
                      FractionallySizedBox(
                        widthFactor: (value / 100).clamp(0.0, 1.0),
                        child: Container(color: AppColors.gold),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            SizedBox(
              width: 36,
              child: Text(value.round().toString(),
                  style: AppText.body, textAlign: TextAlign.right),
            ),
          ],
        ),
      );
}

/// 다크 hero — 두 인물 + 케미 합. 관상 hero 와 같은 다크 톤(신규 색 없음).
class _Hero extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  final String myAlias;
  final String albumAlias;
  final double chemistry;

  const _Hero({
    required this.my,
    required this.album,
    required this.myAlias,
    required this.albumAlias,
    required this.chemistry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.darkBrown, AppColors.warmBrown],
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        children: [
          Text(
            '케미 ${chemistry.round()}',
            style: AppText.display.copyWith(color: Colors.white, height: 1.0),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text('/ 300', style: AppText.hint.copyWith(color: AppColors.gold)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _Person(report: my, alias: myAlias)),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xxl),
                child: Text(
                  '×',
                  style: AppText.sectionTitle.copyWith(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    height: 1.0,
                  ),
                ),
              ),
              Expanded(child: _Person(report: album, alias: albumAlias)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Person extends StatelessWidget {
  final FaceReadingReport report;
  final String alias;
  const _Person({required this.report, required this.alias});

  @override
  Widget build(BuildContext context) {
    final demographic =
        '${report.gender.labelKo} ${report.ageGroup.labelKo} ${report.faceShape.korean}';
    return Column(
      children: [
        DetailAvatar(
          thumbnailKey: report.thumbnailKey,
          borderColor: sourceBorderColor(report.source),
          fallback: Center(
            child: SvgPicture.asset(
              report.gender == Gender.male
                  ? 'assets/svgs/male.svg'
                  : 'assets/svgs/female.svg',
              height: DetailAvatar.size * 0.5,
              colorFilter: const ColorFilter.mode(
                AppColors.textHint,
                BlendMode.srcIn,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          alias,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.caption.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          demographic,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.hint.copyWith(color: AppColors.gold),
        ),
      ],
    );
  }
}

/// measure 에디션 카카오 공유 카드 — 800×800. 두 썸네일 + 케미 합 + 세 성분.
class MeasurePairShareCard extends StatelessWidget {
  final FaceReadingReport my;
  final FaceReadingReport album;
  const MeasurePairShareCard({super.key, required this.my, required this.album});

  @override
  Widget build(BuildContext context) {
    final pair = analyzePairReports(my, album);
    Widget thumb(FaceReadingReport r) {
      const size = 220.0;
      final file = ThumbnailPaths.cacheFileSync(r.thumbnailKey);
      if (file != null && file.existsSync()) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Image.file(file, width: size, height: size, fit: BoxFit.cover),
        );
      }
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: const Icon(Icons.face, size: 96, color: AppColors.textHint),
      );
    }

    Widget line(String label, double v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Expanded(
                child: Text(label,
                    style: AppText.sectionTitle.copyWith(fontSize: 26)),
              ),
              Text(v.round().toString(),
                  style: AppText.sectionTitle.copyWith(fontSize: 26)),
            ],
          ),
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
                  Text('두 얼굴 비교', style: AppText.display.copyWith(fontSize: 40)),
                  const SizedBox(height: AppSpacing.huge),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      thumb(my),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
                        child: Text('×',
                            style: AppText.sectionTitle.copyWith(
                                fontSize: 60,
                                fontWeight: FontWeight.w300,
                                color: AppColors.textSecondary)),
                      ),
                      thumb(album),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.huge),
                  Center(
                    child: Text('케미 ${pair.chemistry.round()} / 300',
                        style: AppText.display.copyWith(fontSize: 44)),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  line('조화도', pair.harmony),
                  line('보완도', pair.complementarity),
                  line('닮은 정도', pair.similarity.overall),
                  const Spacer(),
                  Text(MeasurePairBody.disclaimer,
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

/// 목록 카드용 요약 — 케미 합 + 세 성분 한 줄. 관상 카드의 등급 블록 자리.
class MeasurePairSummary extends StatelessWidget {
  final FaceReadingReport a;
  final FaceReadingReport b;
  const MeasurePairSummary({super.key, required this.a, required this.b});

  @override
  Widget build(BuildContext context) {
    final pair = analyzePairReports(a, b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '케미 ${pair.chemistry.round()} / 300',
          style: AppText.sectionTitle.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '조화도 ${pair.harmony.round()}  보완도 ${pair.complementarity.round()}  '
          '닮은 정도 ${pair.similarity.overall.round()}',
          style: AppText.hint,
        ),
      ],
    );
  }
}

/// 비교 탭 (i) 안내 — measure 에디션.
Future<void> showMeasurePairInfoDialog(BuildContext context) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        title: const Text('두 얼굴 비교에 대하여', style: AppText.modalTitle),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '두 얼굴의 계측값과 첫인상 프로필을 나란히 놓고 네 가지 숫자를 계산합니다. '
                '케미 점수는 조화도·보완도·닮은 정도 세 성분의 합(0~300)입니다.',
                style: AppText.body,
              ),
              SizedBox(height: AppSpacing.lg),
              Text('닮은 정도', style: AppText.sectionTitle),
              SizedBox(height: AppSpacing.xs),
              Text(
                '두 얼굴의 468개 특징점에서 사진 속 위치·크기·기울기를 빼고 모양만 남겨 '
                '겹친 뒤, 점들이 서로 얼마나 벌어져 있는지를 0~100으로 바꾼 값입니다. '
                '동아시아 얼굴 11,800장에서 무작위로 고른 두 사람의 중앙값이 50점입니다. '
                '윤곽·눈·눈썹·코·입·턱선 영역별로도 같은 식으로 계산합니다.\n\n'
                '겹치는 방법은 프로크루스테스 정렬(Procrustes analysis)입니다. 두 형태의 '
                '위치·크기·회전을 맞춘 뒤 남는 차이만 재는, 형태 비교의 표준 방법입니다.',
                style: AppText.body,
              ),
              SizedBox(height: AppSpacing.lg),
              Text('첫인상 유사도', style: AppText.sectionTitle),
              SizedBox(height: AppSpacing.xs),
              Text(
                '두 사람의 첫인상 3축(신뢰감·친근함·주도성) 백분위 차이의 평균을 100에서 뺀 값입니다.',
                style: AppText.body,
              ),
              SizedBox(height: AppSpacing.lg),
              Text('조화도', style: AppText.sectionTitle),
              SizedBox(height: AppSpacing.xs),
              Text(
                '축마다 두 사람 중 높은 쪽을 취해 평균한 값입니다. 둘이 함께 있으면 세 인상이 '
                '얼마나 채워지는가를 봅니다. 제품 정의 지표이며 학술 검증을 거치지 않았습니다.',
                style: AppText.body,
              ),
              SizedBox(height: AppSpacing.lg),
              Text('보완도', style: AppText.sectionTitle),
              SizedBox(height: AppSpacing.xs),
              Text(
                '축마다 두 사람의 백분위 차이를 평균한 값입니다. 두 얼굴에서 추정된 첫인상 '
                '프로필이 서로 다른 방향의 특성을 보이는 정도이며, 실제 성격의 보완을 뜻하지 않습니다.',
                style: AppText.body,
              ),
              SizedBox(height: AppSpacing.lg),
              Text(MeasurePairBody.disclaimer, style: AppText.caption),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: AppText.subTitle),
          ),
        ],
      ),
    );
