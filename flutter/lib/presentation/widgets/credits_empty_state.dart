import 'dart:ui' show lerpDouble;

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// 관상 미등록 첫 화면 — 빈 여백을 영화 엔딩 크레딧처럼 채운다.
///
/// 연출은 [CreditsEmptyState.active] 가 처음 true 가 된 순간(= 관상 탭으로
/// 이동한 순간) 딱 한 번 시작한다. 탭 셸이 IndexedStack 이라 이 위젯은 앱을
/// 켤 때 이미 만들어져 있어, 만들어진 시점을 시작 신호로 쓸 수 없다. 다른
/// 탭에 갔다 돌아와도 다시 재생하지 않는다.
///
/// 1. 크레딧 문구가 화면 아래 바깥에서 올라와 **일정한 속도로** 지나간다.
///    첫 줄이 아래끝(하단 탭 바 바로 위)에 나타나고, 위끝을 지나는 줄부터
///    차례로 잘려 사라진다. 중간에 멈추거나 제자리에서 fade out 하지 않는다.
///    문구가 화면보다 길어도 같다 — 시작 자세가 화면을 채우지 않는다.
/// 2. 마지막 글자까지 위로 빠져나간 다음에야 [EmotionEmptyState]
///    (일러스트 + 문구)가 화면 중앙에 한꺼번에 fade in 한다.
///
/// 흐르는 동안 화면을 누르면 멈추고 반투명 일시정지 표시가 뜬다. 다시 누르면
/// 멈춘 자리에서 같은 속도로 이어진다.
///
/// 글자는 [AppText.displaySubtitle] (SongMyung) 고정 — 장식 문구라 본문
/// 토큰과 섞이지 않는다.
///
/// 위치 계산은 [CustomSingleChildLayout] 으로 한다. `LayoutBuilder` 는
/// intrinsic dimension 조회를 지원하지 않아, 자식의 intrinsic height 를 먼저
/// 재는 `SliverFillRemaining(hasScrollBody: false)` 안에 넣으면 그 영역의
/// 레이아웃이 통째로 실패한다.

/// 흐르는 속도(logical px/초). 지속시간을 고정하면 문구 길이가 바뀔 때마다
/// 속도가 달라지므로, 이동 거리에서 지속시간을 역산한다.
const double _kScrollSpeed = 60;

/// 이동 거리를 아직 재지 못했을 때 쓰는 지속시간 (레이아웃 전 시작 등).
const Duration _kFallbackScrollDuration = Duration(seconds: 20);

/// 문구가 다 빠져나간 뒤 일러스트·문구가 떠오르는 시간.
const Duration _kRevealDuration = Duration(milliseconds: 700);

/// 일시정지 표시의 지름과 불투명도. 문구를 가리지 않을 만큼만 드러낸다.
const double _kPauseBadgeSize = 72;
const double _kPauseBadgeOpacity = 0.28;

/// 일시정지 표시가 뜨고 지는 시간.
const Duration _kPauseBadgeFade = Duration(milliseconds: 150);

/// 줄 간격 — [AppText.displaySubtitle] 기본값(1.5)의 1.2 배.
/// 크레딧은 한 줄씩 천천히 읽히는 문구라 본문보다 성기게 벌린다.
const double _kLineHeight = 1.5 * 1.2;

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
    duration: _kFallbackScrollDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// 마지막 레이아웃에서 잰 이동 거리(영역 높이 + 문구 높이). 지속시간을
  /// 여기서 역산해 문구 길이와 무관하게 속도를 일정하게 유지한다.
  double? _travel;
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _kRevealDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  bool _started = false;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    // 마지막 글자가 위로 빠져나간 뒤에 일러스트가 떠오른다 — 문구가 아직
    // 화면에 남아 있는 채로 겹치면 안 된다. 일시정지로 멈춘 것과 끝까지
    // 흐른 것을 구분해야 해서 상태로 듣는다 (`whenComplete` 는 둘을 못
    // 가린다).
    _scroll.addStatusListener(_onScrollStatus);
    if (widget.active) _start();
  }

  void _onScrollStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) _reveal.forward();
  }

  /// 흐르는 동안 화면을 누르면 멈추고, 다시 누르면 멈춘 자리에서 이어진다.
  /// 시작 전이거나 이미 다 흐른 뒤에는 무시한다.
  void _togglePause() {
    if (!_started || _scroll.isCompleted) return;
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _scroll.stop(canceled: false);
      } else {
        // forward() 는 남은 구간만큼만 시간을 쓰므로 속도가 그대로다.
        _scroll.forward();
      }
    });
  }

  @override
  void didUpdateWidget(CreditsEmptyState oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active) _start();
  }

  /// 첫 호출에만 반응한다 — 탭을 오갈 때마다 다시 재생하지 않는다.
  /// 이동 거리는 레이아웃에서 나오므로 프레임이 끝난 뒤에 읽는다.
  void _start() {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final travel = _travel;
      if (travel != null && travel > 0) {
        _scroll.duration = Duration(
          milliseconds: (travel / _kScrollSpeed * 1000).round(),
        );
      }
      _scroll.forward();
    });
  }

  @override
  void dispose() {
    _scroll.removeStatusListener(_onScrollStatus);
    _scroll.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePause,
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
              // 등장도 퇴장도 영역 경계에서 잘려 나가는 것으로 처리한다
              // (엔딩 크레딧과 같은 방식). 별도의 fade 는 걸지 않는다.
              child: ClipRect(
                child: CustomSingleChildLayout(
                  delegate: _CreditsLayout(
                    _scroll,
                    onMeasured: (travel) => _travel = travel,
                  ),
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
          // 멈춰 있는 동안만 보이는 표시. 탭은 아래 GestureDetector 가 받는다.
          IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                duration: _kPauseBadgeFade,
                opacity: _paused ? _kPauseBadgeOpacity : 0,
                child: const FaIcon(
                  FontAwesomeIcons.solidCirclePause,
                  size: _kPauseBadgeSize,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 문구 블록을 영역 아래 바깥(위끝이 영역 아래끝에 닿는 지점)에서 위 바깥
/// (아래끝이 영역 위끝에 닿는 지점)까지 일정한 속도로 밀어 올린다. 자식
/// 높이를 레이아웃 단계에서 직접 받으므로, 문구가 화면보다 길어도 시작 자세가
/// 화면을 채우지 않고 끝날 때는 마지막 글자까지 확실히 빠져나간다.
///
/// 잰 이동 거리는 [onMeasured] 로 돌려준다 — 지속시간을 거기서 역산해야
/// 문구 길이가 달라져도 속도가 같다.
class _CreditsLayout extends SingleChildLayoutDelegate {
  _CreditsLayout(this.progress, {required this.onMeasured})
    : super(relayout: progress);

  final Animation<double> progress;

  /// 이동 거리(영역 높이 + 문구 높이)를 알린다. 레이아웃 중 호출되므로
  /// 받는 쪽은 값만 담아 두고 rebuild 를 일으키지 않아야 한다.
  final ValueChanged<double> onMeasured;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.tightFor(width: constraints.maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    onMeasured(size.height + childSize.height);
    return Offset(
      0,
      lerpDouble(size.height, -childSize.height, progress.value)!,
    );
  }

  @override
  bool shouldRelayout(_CreditsLayout oldDelegate) =>
      oldDelegate.progress != progress;
}
