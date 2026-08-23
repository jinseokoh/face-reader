import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/emotion_empty_state.dart';
import 'package:flutter/material.dart';

/// 빈 탭을 채우는 2단 연출.
///
/// 1. 문구 전체가 화면 위에서 **한 번에** 떨어져 중간에 멈춘다. 0.5초 동안
///    점점 빨라지다 그대로 멎어 "쿵" 하고 닿는 느낌이 난다.
/// 2. 그 아래로 일러스트와 한 줄 문구가 fade in 한다.
///
/// 예전엔 문구가 아래에서 위로 천천히 흘러가는 엔딩 크레딧이었다. 다 지나갈
/// 때까지 기다려야 안내가 보여서 지루했다 — 지금은 1초 만에 전부 읽히고,
/// 문구가 화면에 남은 채로 안내가 그 아래 붙는다.
///
/// 연출은 [active] 가 처음 true 가 된 순간(= 그 탭이 실제로 보이는 순간) 딱
/// 한 번 시작한다. 탭 셸이 IndexedStack 이고 TabBarView 도 이웃 탭을 미리
/// 만들어 두므로, 만들어진 시점은 시작 신호가 될 수 없다. 다른 탭에 갔다
/// 돌아와도 다시 재생하지 않는다.
///
/// 글자는 [AppText.displaySubtitle] (SongMyung) 고정 — 장식 문구라 본문
/// 토큰과 섞이지 않는다.

/// 떨어지는 시간.
const Duration _kDropDuration = Duration(milliseconds: 500);

/// 문구가 멈춘 뒤 일러스트·문구가 떠오르는 시간.
const Duration _kRevealDuration = Duration(milliseconds: 700);

/// 시작 높이 — 문구 블록 높이의 배수만큼 위. 화면 밖에서 들어오도록 넉넉히.
const double _kDropFrom = -1.6;

/// 줄 간격 — [AppText.displaySubtitle] 기본값(1.5)의 1.2 배.
/// 한 줄씩 읽히는 문구라 본문보다 성기게 벌린다.
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

  /// 떨어질 문구. 줄바꿈은 이 목록 그대로 유지된다.
  final List<String> lines;

  /// [EmotionEmptyState] 로 넘길 일러스트와 한 줄 문구.
  final String asset;
  final String message;

  @override
  State<CreditsEmptyState> createState() => _CreditsEmptyStateState();
}

class _CreditsEmptyStateState extends State<CreditsEmptyState>
    with TickerProviderStateMixin {
  // animationBehavior.preserve — 기기의 "애니메이션 제거"가 켜져 있으면
  // AnimationController 는 지속시간을 5% 로 줄인다. 그러면 연출이 시작과
  // 동시에 끝나 있다. 이 연출은 화면을 채우는 내용 자체라 그 축약을 따르지
  // 않는다.
  late final AnimationController _drop = AnimationController(
    vsync: this,
    duration: _kDropDuration,
    animationBehavior: AnimationBehavior.preserve,
  );
  late final AnimationController _reveal = AnimationController(
    vsync: this,
    duration: _kRevealDuration,
    animationBehavior: AnimationBehavior.preserve,
  );

  /// 점점 빨라지다 멎는다 — 떨어지는 물체의 가속이라 끝에서 "쿵" 이 난다.
  /// 감속(easeOut)으로 두면 살며시 내려앉아 무게가 사라진다.
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, _kDropFrom),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _drop, curve: Curves.easeInCubic));

  bool _started = false;

  @override
  void initState() {
    super.initState();
    _drop.addStatusListener(_onDropStatus);
    if (widget.active) _start();
  }

  void _onDropStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed && mounted) _reveal.forward();
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
    _drop.forward();
  }

  @override
  void dispose() {
    _drop.removeStatusListener(_onDropStatus);
    _drop.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxl),
          child: SlideTransition(
            position: _slide,
            child: Text(
              widget.lines.join('\n'),
              style: AppText.displaySubtitle.copyWith(height: _kLineHeight),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.huge),
        FadeTransition(
          opacity: _reveal,
          child: EmotionEmptyState(
            asset: widget.asset,
            message: widget.message,
          ),
        ),
      ],
    );
  }
}
