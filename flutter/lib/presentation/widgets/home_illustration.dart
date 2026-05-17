import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 홈 화면 상단 일러스트.
///
/// 외부 asset 없이 [CustomPainter] 로 직접 그리는 손그림 느낌 line drawing.
/// 중앙: 정면 얼굴 + face mesh dots (관상 모티프).
/// 주변: 측면 옆모습 미니어처, 별, 점, 나선, dotted arc — 분석/관측 분위기.
/// 모노톤 단일 stroke 색 + cream 배경. 색은 file-local 상수 [_kInk].
class HomeIllustration extends StatelessWidget {
  final double size;
  const HomeIllustration({super.key, this.size = 280});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _HomeIllustrationPainter()),
    );
  }
}

const Color _kInk = Color(0xFF2A2A2A);

class _HomeIllustrationPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = _kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final strokeThin = Paint()
      ..color = _kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    final fill = Paint()
      ..color = _kInk
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;

    // ── 중앙 얼굴 (정면, egg shape) ─────────────────────────────────────
    final face = Rect.fromCenter(
      center: Offset(w * 0.5, h * 0.55),
      width: w * 0.50,
      height: w * 0.60,
    );
    canvas.drawOval(face, stroke);

    // 눈썹 — 짧은 두 줄
    final browY = face.top + face.height * 0.30;
    final browDx = face.width * 0.16;
    final browSpan = face.width * 0.12;
    canvas.drawLine(
      Offset(face.center.dx - browDx - browSpan / 2, browY),
      Offset(face.center.dx - browDx + browSpan / 2, browY - 2),
      stroke,
    );
    canvas.drawLine(
      Offset(face.center.dx + browDx - browSpan / 2, browY - 2),
      Offset(face.center.dx + browDx + browSpan / 2, browY),
      stroke,
    );

    // 눈 — 채워진 점
    final eyeY = browY + 14;
    canvas.drawCircle(
        Offset(face.center.dx - browDx, eyeY), 3.0, fill);
    canvas.drawCircle(
        Offset(face.center.dx + browDx, eyeY), 3.0, fill);

    // 코 — 짧은 세로선 + 작은 곡선 콧방울
    final noseTop = Offset(face.center.dx, eyeY + 10);
    final noseBot = Offset(face.center.dx, eyeY + 32);
    canvas.drawLine(noseTop, noseBot, strokeThin);
    final nostril = Path()
      ..moveTo(noseBot.dx - 4, noseBot.dy)
      ..quadraticBezierTo(
          noseBot.dx, noseBot.dy + 3, noseBot.dx + 4, noseBot.dy);
    canvas.drawPath(nostril, strokeThin);

    // 입 — 살짝 웃는 곡선
    final mouthY = face.bottom - face.height * 0.20;
    final mouth = Path()
      ..moveTo(face.center.dx - 14, mouthY)
      ..quadraticBezierTo(
          face.center.dx, mouthY + 7, face.center.dx + 14, mouthY);
    canvas.drawPath(mouth, stroke);

    // ── face mesh dots — 광대·턱 라인에 sparse 6개점 ───────────────────
    final meshDots = [
      Offset(face.left + face.width * 0.18, face.top + face.height * 0.50),
      Offset(face.left + face.width * 0.82, face.top + face.height * 0.50),
      Offset(face.left + face.width * 0.22, face.top + face.height * 0.68),
      Offset(face.left + face.width * 0.78, face.top + face.height * 0.68),
      Offset(face.left + face.width * 0.42, face.top + face.height * 0.85),
      Offset(face.left + face.width * 0.58, face.top + face.height * 0.85),
    ];
    final meshFill = Paint()
      ..color = _kInk.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    for (final d in meshDots) {
      canvas.drawCircle(d, 1.6, meshFill);
    }

    // ── 좌상단: 큰 4-point sparkle ─────────────────────────────────────
    _drawSparkle(canvas, Offset(w * 0.14, h * 0.15), 11, strokeThin);

    // ── 우상단: 작은 측면 옆얼굴 ──────────────────────────────────────
    _drawSideProfile(canvas, Offset(w * 0.86, h * 0.20), 30, stroke);

    // ── 우상단 옆: 점 패턴 (3개) ──────────────────────────────────────
    for (int i = 0; i < 3; i++) {
      canvas.drawCircle(
          Offset(w * 0.72 + i * 4.5, h * 0.10), 1.4, fill);
    }

    // ── 좌하단: 작은 nautilus 나선 ─────────────────────────────────────
    _drawSpiral(canvas, Offset(w * 0.14, h * 0.82), 14, strokeThin);

    // ── 우하단: 작은 sparkle ──────────────────────────────────────────
    _drawSparkle(canvas, Offset(w * 0.86, h * 0.80), 7, strokeThin);

    // ── 얼굴 위쪽: dotted arc (분석 후광) ─────────────────────────────
    _drawDottedArc(canvas, face, fill);

    // ── 좌측 중간: 작은 ⌀ — 원 안의 점 ────────────────────────────────
    canvas.drawCircle(Offset(w * 0.08, h * 0.50), 7, strokeThin);
    canvas.drawCircle(Offset(w * 0.08, h * 0.50), 1.6, fill);

    // ── 우측 중간: 작은 wavy 곡선 ─────────────────────────────────────
    _drawWave(canvas, Offset(w * 0.92, h * 0.52), strokeThin);
  }

  void _drawSparkle(Canvas c, Offset center, double size, Paint paint) {
    c.drawLine(Offset(center.dx - size, center.dy),
        Offset(center.dx + size, center.dy), paint);
    c.drawLine(Offset(center.dx, center.dy - size),
        Offset(center.dx, center.dy + size), paint);
    final diag = size * 0.55;
    c.drawLine(Offset(center.dx - diag, center.dy - diag),
        Offset(center.dx + diag, center.dy + diag), paint);
    c.drawLine(Offset(center.dx + diag, center.dy - diag),
        Offset(center.dx - diag, center.dy + diag), paint);
  }

  void _drawSideProfile(Canvas c, Offset center, double size, Paint paint) {
    // 단순화된 옆얼굴 — 이마→코→입→턱 곡선 + 머리 윗부분
    final path = Path()
      ..moveTo(center.dx - size * 0.35, center.dy - size * 0.95)
      ..quadraticBezierTo(
        center.dx + size * 0.10, center.dy - size * 1.05,
        center.dx + size * 0.40, center.dy - size * 0.55,
      )
      ..quadraticBezierTo(
        center.dx + size * 0.55, center.dy - size * 0.20,
        center.dx + size * 0.48, center.dy + size * 0.05,
      )
      ..quadraticBezierTo(
        center.dx + size * 0.38, center.dy + size * 0.25,
        center.dx + size * 0.25, center.dy + size * 0.45,
      )
      ..quadraticBezierTo(
        center.dx + size * 0.05, center.dy + size * 0.78,
        center.dx - size * 0.30, center.dy + size * 0.92,
      );
    c.drawPath(path, paint);
    // 눈 점 하나
    c.drawCircle(
        Offset(center.dx + size * 0.18, center.dy - size * 0.45), 1.4,
        Paint()
          ..color = _kInk
          ..style = PaintingStyle.fill);
  }

  void _drawSpiral(Canvas c, Offset center, double size, Paint paint) {
    final path = Path();
    const steps = 80;
    for (int i = 0; i <= steps; i++) {
      final t = i / steps;
      final r = t * size;
      final a = t * math.pi * 2.6;
      final p = Offset(center.dx + math.cos(a) * r, center.dy + math.sin(a) * r);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    c.drawPath(path, paint);
  }

  void _drawDottedArc(Canvas c, Rect face, Paint fill) {
    const count = 9;
    for (int i = 0; i < count; i++) {
      final t = i / (count - 1);
      final a = math.pi * 1.18 + t * math.pi * 0.64; // 윗쪽 호
      final r = face.width * 0.66;
      final p = Offset(
        face.center.dx + math.cos(a) * r,
        face.center.dy + math.sin(a) * r * 0.85,
      );
      c.drawCircle(p, 1.4, fill);
    }
  }

  void _drawWave(Canvas c, Offset center, Paint paint) {
    final path = Path()
      ..moveTo(center.dx - 8, center.dy)
      ..quadraticBezierTo(center.dx - 4, center.dy - 5, center.dx, center.dy)
      ..quadraticBezierTo(center.dx + 4, center.dy + 5, center.dx + 8, center.dy);
    c.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_HomeIllustrationPainter oldDelegate) => false;
}
