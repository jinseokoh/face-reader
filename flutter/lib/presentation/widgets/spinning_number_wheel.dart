import 'package:facely/core/theme.dart';
import 'package:flutter/material.dart';

/// compatibility.png 일러스트 + 계속 회전하는 숫자 릴 두 개.
///
/// 일러스트 자체에 그려진 숫자창 두 칸을 흰색으로 덮고 그 위에서 0~9 를
/// 무한 스크롤한다. 결제 전이라 점수가 정해지지 않은 상태이므로 특정 숫자에
/// 멈추지 않고 다이얼로그가 떠 있는 동안 계속 돈다.

/// 원본 일러스트 한 변(px). 아래 좌표 상수는 전부 이 좌표계 기준 실측값이다.
const double _kArtSize = 640;

/// 숫자창 안쪽 사각형 — 테두리 선(54~56 / 286~287)은 덮지 않는다.
const double _kWindowTop = 57;
const double _kWindowHeight = 229;
const double _kWindowWidth = 104;
const double _kLeftWindowX = 203;
const double _kRightWindowX = 335;

/// 창 모서리 곡률. 원본 창의 둥근 모서리 선을 가리지 않기 위한 값.
const double _kWindowRadius = 10;

/// 숫자 한 칸의 높이 / 창 높이. 0.5 면 원본처럼 가운데 숫자 하나와
/// 위아래 숫자가 절반씩 보인다.
const double _kCellRatio = 0.5;

/// 숫자 글자 크기 / 창 높이.
const double _kDigitRatio = 0.56;

/// 한 바퀴(=controller 1주기) 동안 각 릴이 넘기는 숫자 수.
/// 10 의 배수여야 주기가 넘어갈 때 숫자가 튀지 않는다.
/// 두 값을 다르게 둬서 좌우 릴이 어긋나 돈다.
const int _kLeftCellsPerLoop = 30;
const int _kRightCellsPerLoop = 40;

const Duration _kLoopDuration = Duration(seconds: 8);

/// 원본 일러스트의 숫자와 같은 먹색.
const Color _kDigitColor = Color(0xFF1F1F1F);

class SpinningNumberWheel extends StatefulWidget {
  const SpinningNumberWheel({super.key, required this.size});

  /// 정사각 일러스트의 한 변.
  final double size;

  @override
  State<SpinningNumberWheel> createState() => _SpinningNumberWheelState();
}

class _SpinningNumberWheelState extends State<SpinningNumberWheel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _kLoopDuration,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // asset px → logical px.
    final scale = widget.size / _kArtSize;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          Image.asset(
            'assets/images/compatibility.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
          ),
          _reel(scale, _kLeftWindowX, _kLeftCellsPerLoop),
          _reel(scale, _kRightWindowX, _kRightCellsPerLoop),
        ],
      ),
    );
  }

  Widget _reel(double scale, double windowX, int cellsPerLoop) {
    return Positioned(
      left: windowX * scale,
      top: _kWindowTop * scale,
      width: _kWindowWidth * scale,
      height: _kWindowHeight * scale,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kWindowRadius * scale),
        child: ColoredBox(
          color: AppColors.background,
          child: _DigitReel(
            spin: _controller,
            cellsPerLoop: cellsPerLoop,
            windowHeight: _kWindowHeight * scale,
          ),
        ),
      ),
    );
  }
}

/// 창 하나 안에서 0~9 를 무한히 흘려보내는 릴.
class _DigitReel extends StatelessWidget {
  const _DigitReel({
    required this.spin,
    required this.cellsPerLoop,
    required this.windowHeight,
  });

  final Animation<double> spin;
  final int cellsPerLoop;
  final double windowHeight;

  @override
  Widget build(BuildContext context) {
    final cell = windowHeight * _kCellRatio;
    final style = AppText.modalTitle.copyWith(
      fontSize: windowHeight * _kDigitRatio,
      fontWeight: FontWeight.w700,
      color: _kDigitColor,
      height: 1,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        AnimatedBuilder(
          animation: spin,
          builder: (context, _) {
            // 흘러간 칸 수. 정수부가 맨 위 칸의 숫자, 소수부가 스크롤 위치.
            final position = spin.value * cellsPerLoop;
            final firstDigit = position.floor();
            final offset = position - firstDigit;
            return Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  // 위로 반 칸 올려야 가운데 칸이 창 정중앙에 온다.
                  top: -(0.5 + offset) * cell,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < 4; i++)
                        SizedBox(
                          height: cell,
                          child: Center(
                            child: Text(
                              '${(firstDigit + i) % 10}',
                              style: style,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
        // 위·아래 흰색 페이드 — 원본 일러스트의 회전 모션블러를 대신한다.
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background,
                  AppColors.background.withValues(alpha: 0),
                  AppColors.background.withValues(alpha: 0),
                  AppColors.background,
                ],
                stops: const [0, 0.3, 0.7, 1],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
