import 'dart:ui';

/// 계측 라벨 하나의 배치 입력 — 지시선이 가리킬 얼굴 위 점과 라벨 상자 크기.
class MetricLabelSpec {
  final Offset anchor;
  final Size size;

  /// -1 왼쪽 열, 1 오른쪽 열, null 이면 앵커가 얼굴 중심선의 어느 쪽인지로 결정.
  final int? column;

  const MetricLabelSpec({
    required this.anchor,
    required this.size,
    this.column,
  });
}

/// 라벨 상자들을 화면 좌우 여백에 열로 세운다.
///
/// 앵커가 얼굴 중심선 왼쪽이면 왼쪽 열, 오른쪽이면 오른쪽 열([MetricLabelSpec.column]
/// 으로 고정 가능). 각 열 안에서는
/// 앵커 높이 순으로 놓되 서로 [gap] 이상 떨어지게 아래로 밀고, 화면 아래를
/// 넘치면 위로 되민다. 얼굴 위에 글자를 겹쳐 쓰지 않으므로 라벨끼리도, 라벨과
/// 얼굴도 겹치지 않는다. 반환 순서는 입력 순서와 같다.
List<Rect> layoutMetricLabels(
  List<MetricLabelSpec> specs,
  Size canvas, {
  required double faceCenterX,
  double pad = 8,
  double gap = 6,
}) {
  final rects = List<Rect>.filled(specs.length, Rect.zero);
  final left = <int>[];
  final right = <int>[];
  for (var i = 0; i < specs.length; i++) {
    final col = specs[i].column ?? (specs[i].anchor.dx < faceCenterX ? -1 : 1);
    (col < 0 ? left : right).add(i);
  }

  void place(List<int> column, bool isLeft) {
    column.sort((a, b) => specs[a].anchor.dy.compareTo(specs[b].anchor.dy));
    final tops = List<double>.filled(column.length, 0);
    // 위에서 아래로 — 앵커 높이에 맞추되 이전 라벨과 gap 유지.
    var floor = pad;
    for (var k = 0; k < column.length; k++) {
      final s = specs[column[k]];
      final wanted = s.anchor.dy - s.size.height / 2;
      tops[k] = wanted < floor ? floor : wanted;
      floor = tops[k] + s.size.height + gap;
    }
    // 아래에서 위로 — 화면 바닥을 넘친 만큼 위로 되민다.
    var ceil = canvas.height - pad;
    for (var k = column.length - 1; k >= 0; k--) {
      final h = specs[column[k]].size.height;
      if (tops[k] + h > ceil) tops[k] = ceil - h;
      ceil = tops[k] - gap;
    }
    for (var k = 0; k < column.length; k++) {
      final s = specs[column[k]];
      final x = isLeft ? pad : canvas.width - pad - s.size.width;
      rects[column[k]] = Rect.fromLTWH(x, tops[k], s.size.width, s.size.height);
    }
  }

  place(left, true);
  place(right, false);
  return rects;
}
