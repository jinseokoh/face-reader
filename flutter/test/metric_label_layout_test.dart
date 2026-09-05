import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:facely/presentation/screens/chemistry/metric_label_layout.dart';

void main() {
  const canvas = Size(360, 640);
  const label = Size(90, 24);

  bool overlaps(Rect a, Rect b) => a.overlaps(b);

  test('같은 열 라벨은 서로 겹치지 않고 앵커 높이 순으로 놓인다', () {
    final specs = [
      for (var i = 0; i < 8; i++)
        MetricLabelSpec(anchor: Offset(100, 300 + i * 4.0), size: label),
    ];
    final rects = layoutMetricLabels(specs, canvas, faceCenterX: 180);
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(overlaps(rects[i], rects[j]), isFalse, reason: '$i vs $j');
      }
      expect(rects[i].left, 8);
      expect(rects[i].top, greaterThanOrEqualTo(0));
      expect(rects[i].bottom, lessThanOrEqualTo(canvas.height));
    }
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].top, greaterThan(rects[i - 1].top));
    }
  });

  test('앵커가 중심선 오른쪽이면 오른쪽 여백 열에 붙는다', () {
    final rects = layoutMetricLabels(
      [MetricLabelSpec(anchor: const Offset(300, 100), size: label)],
      canvas,
      faceCenterX: 180,
    );
    expect(rects.single.right, canvas.width - 8);
    expect(rects.single.center.dy, 100);
  });

  test('column 고정은 앵커 위치보다 우선한다', () {
    final rects = layoutMetricLabels(
      [
        MetricLabelSpec(anchor: const Offset(300, 100), size: label, column: -1),
      ],
      canvas,
      faceCenterX: 180,
    );
    expect(rects.single.left, 8);
  });

  test('화면 바닥을 넘치면 위로 되밀되 순서와 간격을 지킨다', () {
    final specs = [
      for (var i = 0; i < 6; i++)
        MetricLabelSpec(anchor: Offset(100, 630 - i * 2.0), size: label),
    ];
    final rects = layoutMetricLabels(specs, canvas, faceCenterX: 180);
    final sorted = [...rects]..sort((a, b) => a.top.compareTo(b.top));
    expect(sorted.last.bottom, lessThanOrEqualTo(canvas.height - 8));
    for (var i = 1; i < sorted.length; i++) {
      expect(sorted[i].top - sorted[i - 1].bottom, greaterThanOrEqualTo(6));
    }
  });
}
