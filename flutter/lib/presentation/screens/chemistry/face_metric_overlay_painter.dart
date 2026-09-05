import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/domain/services/face_metrics.dart';
import 'package:facely/domain/services/face_metrics_lateral.dart';

import 'face_mesh_painter.dart';
import 'metric_label_layout.dart';

enum MetricOverlayPhase { frontal, lateral }

/// 카메라 프리뷰 위에 실시간 계측 오버레이를 그린다.
///
/// 메시 삼각형 대신, 엔진이 실제로 계산하는 계측값의 선분(얼굴 세로·가로,
/// 삼정, 하악각, E라인, 비전두각 …)을 긋고 프레임마다 값을 라벨로 띄운다.
/// 라벨은 얼굴 위가 아니라 화면 좌우 여백 열에 세우고 지시선으로 잇는다
/// ([layoutMetricLabels]). 선·점 색은 촬영 준비 상태(빨강/초록)를 그대로 쓴다.
class FaceMetricOverlayPainter extends CustomPainter {
  final FaceMeshResult result;
  final MetricOverlayPhase phase;
  final int rotationCompensation;
  final CameraLensDirection lensDirection;
  final Color overlayColor;

  FaceMetricOverlayPainter({
    required this.result,
    required this.phase,
    required this.rotationCompensation,
    required this.lensDirection,
    required this.overlayColor,
  });

  static const double _padH = AppSpacing.sm;
  static const double _padV = AppSpacing.xs;

  @override
  void paint(Canvas canvas, Size size) {
    final lms = result.landmarks;
    if (lms.length <= LandmarkIndex.leftFaceEdge) return;
    Offset p(int i) =>
        landmarkToOffset(lms[i], size, rotationCompensation, lensDirection);

    final measures = phase == MetricOverlayPhase.frontal
        ? _frontal(lms, p)
        : _lateral(lms, p);

    final linePaint = Paint()
      ..color = overlayColor.withValues(alpha: 0.9)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final dotPaint = Paint()
      ..color = overlayColor
      ..style = PaintingStyle.fill;
    final leaderPaint = Paint()
      ..color = overlayColor.withValues(alpha: 0.6)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final pillPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final textStyle = AppText.caption.copyWith(color: Colors.white, height: 1.2);

    for (final m in measures) {
      for (final path in m.paths) {
        if (path.length < 2) continue;
        final poly = Path()..moveTo(path.first.dx, path.first.dy);
        for (final pt in path.skip(1)) {
          poly.lineTo(pt.dx, pt.dy);
        }
        canvas.drawPath(poly, linePaint);
        for (final pt in path) {
          canvas.drawCircle(pt, 2.5, dotPaint);
        }
      }
    }

    final painters = <TextPainter>[];
    final specs = <MetricLabelSpec>[];
    for (final m in measures) {
      final tp = TextPainter(
        text: TextSpan(text: m.text, style: textStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      painters.add(tp);
      specs.add(MetricLabelSpec(
        anchor: m.anchor,
        size: Size(tp.width + _padH * 2, tp.height + _padV * 2),
        column: m.column,
      ));
    }

    final faceCenterX =
        (p(LandmarkIndex.rightFaceEdge).dx + p(LandmarkIndex.leftFaceEdge).dx) /
            2;
    final rects = layoutMetricLabels(
      specs,
      size,
      faceCenterX: faceCenterX,
      pad: AppSpacing.sm,
      gap: AppSpacing.xs,
    );

    for (var i = 0; i < measures.length; i++) {
      final r = rects[i];
      final isLeft = r.center.dx < faceCenterX;
      final from = Offset(isLeft ? r.right : r.left, r.center.dy);
      canvas.drawLine(from, measures[i].anchor, leaderPaint);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(AppRadius.sm)),
        pillPaint,
      );
      painters[i].paint(canvas, Offset(r.left + _padH, r.top + _padV));
    }
  }

  List<_Measure> _frontal(
    List<FaceMeshLandmark> lms,
    Offset Function(int) p,
  ) {
    final m = FaceMetrics(lms, aspect: result.imageHeight / result.imageWidth);
    final tickHalf = (p(LandmarkIndex.leftFaceEdge).dx -
                p(LandmarkIndex.rightFaceEdge).dx)
            .abs() *
        0.12;
    List<Offset> tick(Offset c) =>
        [Offset(c.dx - tickHalf, c.dy), Offset(c.dx + tickHalf, c.dy)];

    final top = p(LandmarkIndex.foreheadTop);
    final nasion = p(LandmarkIndex.nasion);
    final subnasale = p(LandmarkIndex.subnasale);
    final chin = p(LandmarkIndex.chin);

    return [
      _Measure(
        '얼굴 비율 ${_r2(m.faceAspectRatio)}',
        anchor: top,
        column: 1,
        paths: [
          [top, chin],
          [p(LandmarkIndex.rightFaceEdge), p(LandmarkIndex.leftFaceEdge)],
        ],
      ),
      _Measure(
        '상안 ${_pct(m.upperFaceRatio)}',
        anchor: _mid(top, nasion),
        column: -1,
        paths: [tick(nasion), tick(subnasale)],
      ),
      _Measure(
        '중안 ${_pct(m.midFaceRatio)}',
        anchor: _mid(nasion, subnasale),
        column: -1,
      ),
      _Measure(
        '하안 ${_pct(m.lowerFaceRatio)}',
        anchor: _mid(subnasale, chin),
        column: -1,
      ),
      _Measure(
        '턱 각 ${_deg(m.gonialAngle)}',
        anchor: p(LandmarkIndex.rightGonion),
        paths: [
          [p(LandmarkIndex.rightEar), p(LandmarkIndex.rightGonion), chin],
          [p(LandmarkIndex.leftEar), p(LandmarkIndex.leftGonion), chin],
        ],
      ),
      _Measure(
        '눈꼬리 ${_sdeg(m.eyeCanthalTilt)}',
        anchor: p(LandmarkIndex.rightExocanthion),
        paths: [
          [p(LandmarkIndex.rightEndocanthion), p(LandmarkIndex.rightExocanthion)],
          [p(LandmarkIndex.leftEndocanthion), p(LandmarkIndex.leftExocanthion)],
        ],
      ),
      _Measure(
        '눈 사이 ${_r2(m.intercanthalRatio)}',
        anchor: p(LandmarkIndex.leftEndocanthion),
        paths: [
          [p(LandmarkIndex.rightEndocanthion), p(LandmarkIndex.leftEndocanthion)],
        ],
      ),
      _Measure(
        '코 길이 ${_r2(m.nasalHeightRatio)}',
        anchor: p(LandmarkIndex.noseTip),
        column: 1,
        paths: [
          [nasion, p(LandmarkIndex.noseTip)],
        ],
      ),
      _Measure(
        '입 폭 ${_r2(m.mouthWidthRatio)}',
        anchor: p(LandmarkIndex.leftCheilion),
        paths: [
          [p(LandmarkIndex.rightCheilion), p(LandmarkIndex.leftCheilion)],
        ],
      ),
      _Measure(
        '인중 ${_r2(m.philtrumLength)}',
        anchor: p(LandmarkIndex.upperLipTop),
        column: 1,
        paths: [
          [subnasale, p(LandmarkIndex.upperLipTop)],
        ],
      ),
    ];
  }

  List<_Measure> _lateral(
    List<FaceMeshLandmark> lms,
    Offset Function(int) p,
  ) {
    final l = LateralFaceMetrics(lms);
    final top = p(LandmarkIndex.foreheadTop);
    final nasion = p(LandmarkIndex.nasion);
    final rhinion = p(195);
    final tip = p(LandmarkIndex.noseTip);
    final subnasale = p(LandmarkIndex.subnasale);
    final upperLip = p(LandmarkIndex.upperLipTop);
    final lowerLipInner = p(LandmarkIndex.lowerLipInner);
    final lowerLip = p(LandmarkIndex.lowerLipBottom);
    final chin = p(LandmarkIndex.chin);

    return [
      _Measure(
        '비전두각 ${_deg(l.nasofrontalAngle)}',
        anchor: nasion,
        paths: [
          [top, nasion, tip],
        ],
      ),
      _Measure(
        '콧대 굴곡 ${_pct(l.dorsalConvexity)}',
        anchor: rhinion,
        paths: [
          [nasion, rhinion, tip],
        ],
      ),
      _Measure(
        '코 길이 ${_r2(l.noseTipProjection)}',
        anchor: tip,
      ),
      _Measure(
        '비순각 ${_deg(l.nasolabialAngle)}',
        anchor: subnasale,
        paths: [
          [tip, subnasale, upperLip],
        ],
      ),
      _Measure(
        '안면 돌출 ${_deg(l.facialConvexity)}',
        anchor: _mid(subnasale, chin),
        paths: [
          [top, subnasale, chin],
        ],
      ),
      _Measure(
        'E라인 윗입술 ${_sr2(l.upperLipEline)}',
        anchor: upperLip,
        paths: [
          [tip, chin],
          [upperLip, _foot(upperLip, tip, chin)],
        ],
      ),
      _Measure(
        'E라인 아랫입술 ${_sr2(l.lowerLipEline)}',
        anchor: lowerLip,
        paths: [
          [lowerLip, _foot(lowerLip, tip, chin)],
        ],
      ),
      _Measure(
        '순이각 ${_deg(l.mentolabialAngle)}',
        anchor: lowerLip,
        paths: [
          [lowerLipInner, lowerLip, chin],
        ],
      ),
    ];
  }

  static Offset _mid(Offset a, Offset b) => Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

  /// 점 [q] 에서 직선 [a]–[b] 로 내린 수선의 발.
  static Offset _foot(Offset q, Offset a, Offset b) {
    final ab = b - a;
    final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (len2 == 0) return a;
    final t = ((q - a).dx * ab.dx + (q - a).dy * ab.dy) / len2;
    return a + ab * t;
  }

  static String _deg(double v) => '${v.round()}°';
  static String _sdeg(double v) => '${v >= 0 ? '+' : ''}${v.round()}°';
  static String _r2(double v) => v.toStringAsFixed(2);
  static String _sr2(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';
  static String _pct(double v) => '${(v * 100).round()}%';

  @override
  bool shouldRepaint(FaceMetricOverlayPainter oldDelegate) => true;
}

class _Measure {
  final String text;
  final Offset anchor;
  final List<List<Offset>> paths;

  /// -1 왼쪽 열 고정, 1 오른쪽 열 고정, null 이면 앵커 위치로 자동.
  /// 얼굴 중심선 위의 앵커는 프레임마다 좌우가 튀므로 고정한다.
  final int? column;

  const _Measure(
    this.text, {
    required this.anchor,
    this.paths = const [],
    this.column,
  });
}
