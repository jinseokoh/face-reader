import 'dart:ui' show lerpDouble;

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:flutter/material.dart';

/// 관상 미등록 첫 화면 — 빈 여백을 영화 엔딩 크레딧처럼 채운다.
///
/// 연출은 [CreditsEmptyState.active] 가 처음 true 가 된 순간(= 관상 탭으로
/// 이동한 순간) 딱 한 번 시작한다. 탭 셸이 IndexedStack 이라 이 위젯은 앱을
/// 켤 때 이미 만들어져 있어, 만들어진 시점을 시작 신호로 쓸 수 없다. 다른
/// 탭에 갔다 돌아와도 다시 재생하지 않는다.
///
/// 1. 크레딧 문구가 맨 아래(하단 탭 바 바로 위)에서 나타나 **일정한 속도로**
///    계속 올라가고, 영역 위끝을 지나는 글자부터 차례로 잘려 사라진다.
///    중간에 멈추거나 제자리에서 fade out 하지 않는다.
/// 2. 마지막 글자까지 위로 빠져나간 다음에야 [EmotionEmptyState]
///    (일러스트 + 문구)가 화면 중앙에 한꺼번에 fade in 한다.
///
/// 글자는 [AppText.displaySubtitle] (SongMyung) 고정 — 장식 문구라 본문
/// 토큰과 섞이지 않는다.
///
/// 위치 계산은 [CustomSingleChildLayout] 으로 한다. `LayoutBuilder` 는
/// intrinsic dimension 조회를 지원하지 않아, 자식의 intrinsic height 를 먼저
/// 재는 `SliverFillRemaining(hasScrollBody: false)` 안에 넣으면 그 영역의
/// 레이아웃이 통째로 실패한다.

/// 문구 아래끝이 영역 아래끝에 붙은 상태에서 출발해 위끝 밖으로 완전히
/// 빠져나가기까지 걸리는 시간. 이동 거리는 영역 높이와 같고 곡선을 걸지
/// 않으므로 속도가 일정하다. 읽는 속도보다 느려야 해서 넉넉히 잡는다.
const Duration _kScrollDuration = Duration(seconds: 10);

/// 문구가 다 빠져나간 뒤 일러스트·문구가 떠오르는 시간.
const Duration _kRevealDuration = Duration(milliseconds: 700);

/// 문구가 불쑥 나타나지 않도록 이동 초반에 걸치는 fade in 구간.
const double _kTextFadeIn = 0.08;

/// 줄 간격 — [AppText.displaySubtitle] 기본값(1.5)의 1.5 배.
/// 크레딧은 한 줄씩 천천히 읽히는 문구라 본문보다 성기게 벌린다.
const double _kLineHeight = 1.5 * 1.5;

class CreditsEmptyState extends StatefulWidget {
  const CreditsEmptyState({
    super.key,
    required this.lines,
    required this.asset,
    required this.message,
    required this.active,
  });

  /// 이 화면이 지금 사용자에게 보이는 중인가. false → true 로 바뀌는 첫
  /// 순간에 연출이 시작된다.
  final bool active;

  /// 크레딧 문구. 줄바꿈은 이 목록 그대로 유지된다.
  final List<String> lines;

  /// [EmotionEmptyState] 로 넘길 일러스트와 한 줄 문구.
  final String asset;
  final String message;

  @override
  State<CreditsEmptyState> createState() => _CreditsEmptyStateState();
}

class _CreditsEmptyStateState extends State<CreditsEmptyState>
    with TickerProviderStateMixin {
  // animationBehavior.preserve — 기기의 "애니메이션 제거"(개발자 옵션의 전환
  // 애니메이션 배율 0 포함)가 켜져 있으면 AnimationController 는 지속시간을
  // 5% 로 줄인다. 그러면 10초짜리 연출이 0.5초 만에 지나가, 탭을 열었을 때
  // 이미 중간이거나 끝나 있다. 이 연출은 화면을 채우는 내용 자체라 그 축약을
  // 따르지 않는다.
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: _kScrollDuration,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _kRevealDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  bool _started = false;

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(CreditsEmptyState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) _start();
  }

  /// 첫 호출에만 반응한다 — 탭을 오갈 때마다 다시 재생하지 않는다.
  void _start() {
    if (_started) return;
    _started = true;
    // 마지막 글자가 위로 빠져나간 뒤에 일러스트가 떠오른다 — 문구가 아직
    // 화면에 남아 있는 채로 겹치면 안 된다.
    _scroll.forward().whenComplete(() {
      if (mounted) _reveal.forward();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
            child: ClipRect(
              // 등장에만 fade 를 건다. 퇴장은 영역 위끝을 지나며 잘려
              // 나가는 것으로 처리한다 (엔딩 크레딧과 같은 방식).
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _scroll,
                  curve: const Interval(0, _kTextFadeIn),
                ),
                child: CustomSingleChildLayout(
                  delegate: _CreditsLayout(_scroll),
                  child: Text(
                    widget.lines.join('\n'),
                    style: AppText.displaySubtitle.copyWith(
                      height: _kLineHeight,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
        // 문구가 위로 다 빠져나간 뒤 일러스트와 한 줄 문구가 함께 떠오른다.
        Center(
          child: FadeTransition(
            opacity: _reveal,
            child: EmotionEmptyState(
              asset: widget.asset,
              message: widget.message,
            ),
          ),
        ),
      ],
    );
  }
}

/// 문구 블록을 영역 맨 아래(아래끝 맞춤)에서 위끝 밖(아래끝이 영역 위끝에
/// 닿는 지점)까지 일정한 속도로 밀어 올린다. 자식 높이를 레이아웃 단계에서
/// 직접 받으므로 문구가 몇 줄이든 시작할 때 잘리지 않고, 끝날 때는 마지막
/// 글자까지 확실히 빠져나간다.
class _CreditsLayout extends SingleChildLayoutDelegate {
  _CreditsLayout(this.progress) : super(relayout: progress);

  final Animation<double> progress;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: constraints.maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final center = lerpDouble(
      size.height - childSize.height / 2,
      -childSize.height / 2,
      progress.value,
    )!;
    return Offset(0, center - childSize.height / 2);
  }

  @override
  bool shouldRelayout(_CreditsLayout oldDelegate) =>
      oldDelegate.progress != progress;
}
