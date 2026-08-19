import 'dart:ui' show lerpDouble;

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:flutter/material.dart';

/// 관상 미등록 첫 화면 — 빈 여백을 세 단계로 채운다.
///
/// 1. 크레딧 문구가 맨 아래(하단 탭 바 바로 위)에서 천천히 나타나 영역의
///    1/4 지점까지 올라간다.
/// 2. 올라간 자리에서 문구가 완전히 사라진다.
/// 3. 화면이 비워진 다음에야 [EmotionEmptyState] (일러스트 + 문구)가 화면
///    중앙에 한꺼번에 fade in 한다.
///
/// 글자는 [AppText.displaySubtitle] (SongMyung) 고정 — 장식 문구라 본문
/// 토큰과 섞이지 않는다.
///
/// 위치 계산은 [CustomSingleChildLayout] 으로 한다. `LayoutBuilder` 는
/// intrinsic dimension 조회를 지원하지 않아, 자식의 intrinsic height 를 먼저
/// 재는 `SliverFillRemaining(hasScrollBody: false)` 안에 넣으면 그 영역의
/// 레이아웃이 통째로 실패한다.

/// 문구가 3/4 에서 1/4 까지 올라가는 데 걸리는 시간.
/// 읽는 속도보다 느려야 해서 넉넉히 잡는다.
const Duration _kScrollDuration = Duration(seconds: 10);

/// 다 올라간 문구가 사라지는 시간.
const Duration _kExitDuration = Duration(milliseconds: 900);

/// 문구가 사라진 뒤 일러스트·문구가 떠오르는 시간.
const Duration _kRevealDuration = Duration(milliseconds: 700);

/// 문구 블록이 멈추는 지점 — 영역 높이 대비 비율(블록 중심 기준).
/// 시작 지점은 비율이 아니라 "블록 아래끝 = 영역 아래끝" 이다. 영역의 아래끝은
/// 하단 탭 바 바로 위라, 문구가 탭 바 위에서 떠올라 올라가는 것처럼 보인다.
const double _kScrollTo = 0.25;

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
  });

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
  late final AnimationController _scroll = AnimationController(
    vsync: this,
    duration: _kScrollDuration,
  );
  late final AnimationController _exit = AnimationController(
    vsync: this,
    duration: _kExitDuration,
  );
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _kRevealDuration,
  );

  @override
  void initState() {
    super.initState();
    // 탭이 보이는 순간부터 흐른다 — 숨은 탭에서는 TickerMode 가 꺼져 있어
    // (app.dart 의 IndexedStack) 여기서 시작해도 멈춰 있다.
    // 올라간다 → 사라진다 → 일러스트가 떠오른다. 각 단계는 앞 단계가 끝난
    // 뒤에만 시작한다 — 문구가 남아 있는 채로 일러스트가 겹치면 안 된다.
    _scroll.forward().whenComplete(() {
      if (!mounted) return;
      _exit.forward().whenComplete(() {
        if (mounted) _reveal.forward();
      });
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _exit.dispose();
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
              // 등장(이동 초반)과 퇴장(이동 완료 후)을 각각 건다.
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _scroll,
                  curve: const Interval(0, _kTextFadeIn),
                ),
                child: FadeTransition(
                  opacity: ReverseAnimation(_exit),
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
        ),
        // 문구가 완전히 사라진 뒤 일러스트와 한 줄 문구가 한꺼번에 떠오른다.
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

/// 문구 블록을 영역 맨 아래(아래끝 맞춤)에서 [_kScrollTo] 지점까지 밀어
/// 올린다. 자식 높이를 레이아웃 단계에서 직접 받으므로 문구가 몇 줄이든
/// 시작할 때 잘리지 않고, 멈추는 지점도 정확하다.
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
      size.height * _kScrollTo,
      progress.value,
    )!;
    return Offset(0, center - childSize.height / 2);
  }

  @override
  bool shouldRelayout(_CreditsLayout oldDelegate) =>
      oldDelegate.progress != progress;
}
