import 'package:concentric_transition/concentric_transition.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

/// prefs box 의 "다시 보지 않기" flag 키. 값은 '1' 하나만 쓴다.
const String kOnboardingNeverAgainKey = 'onboarding_never_again';

const _kAnimDuration = Duration(milliseconds: 350);

const double _kContentBottomInset = 200;

/// 페이지 배경색 — 리플 대비를 위해 warm 톤과 흰색 교대.
/// 마지막 sentinel(흰색)은 실제 페이지가 아니다 — 패키지가 "다음 페이지 색"
/// 원판을 마지막 페이지에서도 그리는데, 배경과 같은 색을 주면 보이지 않는다.
const _kPageColors = [
  AppColors.cream,
  AppColors.background,
  AppColors.shell,
  AppColors.background,
  AppColors.background,
];

const _kPages = [
  _OnboardingPageData(
    asset: 'assets/images/onboarding-physiognomy.png',
    title: '관상',
    chips: ['관상풀이 무료'],
    body: '카메라로 찍거나 앨범 사진을 올리면\n관상 분석을 무료로 볼 수 있습니다.',
    warm: true,
  ),
  _OnboardingPageData(
    asset: 'assets/images/onboarding-compatibility.png',
    title: '궁합',
    chips: ['상세궁합 유료'],
    body: '내 관상이 등록된 상태 이후에 올리는 모든\n사진 속 인물과 나와의 궁합을 볼 수 있습니다.',
    warm: false,
  ),
  _OnboardingPageData(
    asset: 'assets/images/onboarding-chemistry.png',
    title: '케미',
    chips: ['결과표 무료'],
    body: '케미 그룹을 만들고 참여자 전원이 관상을 올리면\n구성원 간의 그룹 케미 결과표가 완성됩니다.',
    warm: true,
  ),
  _OnboardingPageData(
    asset: 'assets/images/banner.png',
    title: '시작은 내 관상부터',
    body: '궁합과 케미는 내 관상이 등록되어 있어야\n이용할 수 있습니다.\n지금 내 관상부터 확인해보세요.',
    warm: false,
  ),
];
/// 동심원 버튼 반지름 + 세로 위치 (화면 높이 비율). 원 중심은
/// verticalPosition * H + radius — 0.75 를 넘기면 하단 시스템 내비와 겹친다.
/// 본문은 [_kContentBottomInset] 만큼 하단을 비워 버튼 존과 분리한다.
const double _kRevealRadius = 32;
const double _kRevealVerticalPosition = 0.75;

/// 상단 컨트롤 바 고정 높이 — Align 자식이 세로로 확장돼 화면 중앙까지
/// 흘러내리는 것을 차단한다.
const double _kTopBarHeight = 48;

/// 온보딩 안내 — 관상 → 궁합 → 케미 → 시작(내 관상 등록) 4페이지 인트로.
/// MainApp 이 첫 프레임 뒤에 호출한다.
///
/// 전환은 ConcentricPageView — 하단 원형 버튼에서 다음 페이지 배경이
/// 동심원으로 확장된다. 리플이 보이려면 페이지 배경색이 서로 달라야 하므로
/// warm beige 팔레트(cream/shell)와 흰색을 교대 배치한다.
///
/// 내 관상이 등록되거나 "다시 보지 않기"를 누르기 전까지 매 실행 노출.
/// [OnboardingIntroResult] 처리(촬영 진입·flag 기록)는 호출부 몫.
Future<OnboardingIntroResult> showOnboardingIntro(BuildContext context) async {
  final size = MediaQuery.of(context).size;
  // useSafeArea 금지 — ConcentricPageView 는 리플 원판을 시트 높이로,
  // 화살표 버튼을 MediaQuery 전체 화면 높이로 계산한다. 시트가 상태바만큼
  // 짧아지면 두 좌표계가 어긋나 버튼이 원판 아래로 밀린다. 시트를 전체 화면
  // 높이로 맞춰 일치시키고, 상태바는 위젯 안에서 viewPadding 으로 비킨다.
  final result = await showModalBottomSheet<OnboardingIntroResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints.tightFor(
      width: size.width,
      height: size.height,
    ),
    builder: (_) => const _OnboardingIntro(),
  );
  // null = Android 뒤로가기 — 건너뛰기와 동일하게 다음 실행 때 다시 보여준다.
  return result ?? OnboardingIntroResult.later;
}

/// 상태바 높이 — bottom sheet route 가 MediaQuery padding 을 조작하므로
/// 가공되지 않는 raw window inset 에서 직접 읽는다.
double _statusBarHeight(BuildContext context) {
  final view = View.of(context);
  return view.padding.top / view.devicePixelRatio;
}

enum OnboardingIntroResult {
  /// "내 관상 보기" CTA — 촬영 플로우로 이어간다.
  startCapture,

  /// "다시 보지 않기" — flag 를 기록해 이후 노출을 끈다.
  neverAgain,

  /// 건너뛰기·뒤로가기 — 기록 없음, 다음 실행 때 다시 노출.
  later,
}

class _Dots extends StatelessWidget {
  final int current;

  const _Dots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < _kPages.length; i++)
          AnimatedContainer(
            duration: _kAnimDuration,
            curve: Curves.easeOutCubic,
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            width: i == current ? AppSpacing.xl : AppSpacing.sm,
            height: AppSpacing.sm,
            decoration: BoxDecoration(
              color: i == current ? AppColors.textPrimary : AppColors.border,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
      ],
    );
  }
}

class _OnboardingIntro extends StatefulWidget {
  const _OnboardingIntro();

  @override
  State<_OnboardingIntro> createState() => _OnboardingIntroState();
}

class _OnboardingIntroState extends State<_OnboardingIntro>
    with TickerProviderStateMixin {
  int _page = 0;

  // 패키지에 넘기는 controller — 마지막 페이지 "정착 순간" 감지용.
  // dispose 는 패키지가 대신 한다 (여기서 또 하면 이중 dispose).
  final PageController _pageController = PageController();

  /// 마지막 페이지 정착 시 패키지가 남기는 이전 페이지 색 원판은 한 프레임에
  /// 사라진다(sentinel 색 교체). 같은 자리·같은 색 원판을 이어받아 그린 뒤
  /// 스케일-아웃으로 흡수시키는 cover. value 1 = 숨김 (초기값).
  late final AnimationController _discAbsorb = AnimationController(
    vsync: this,
    duration: _kAnimDuration,
    value: 1,
  );
  bool _absorbArmed = true;

  /// "내 관상 보기" CTA fade-in — 원판 흡수가 끝난 뒤에만 forward.
  /// value 0 = 숨김 (초기값).
  late final AnimationController _ctaFade = AnimationController(
    vsync: this,
    duration: _kAnimDuration,
  );

  bool get _onLastPage =>
      (_pageController.page ?? 0) >= _kPages.length - 1 - 0.005;

  @override
  void initState() {
    super.initState();
    _pageController.addListener(_onScroll);
    // 흡수 완료 → CTA fade-in 체이닝. 마지막 페이지를 떠나며 value=1 로
    // 리셋할 때도 completed 가 발화하므로 페이지 위치로 가드.
    _discAbsorb.addStatusListener((status) {
      if (status == AnimationStatus.completed && _onLastPage) {
        _ctaFade.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _discAbsorb.dispose();
    _ctaFade.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_onLastPage) {
      // 마지막 페이지 정착 — 원판 흡수 애니메이션 1회 발화.
      if (_absorbArmed) {
        _absorbArmed = false;
        _discAbsorb.forward(from: 0);
      }
    } else {
      _absorbArmed = true;
      if (_discAbsorb.value != 1) _discAbsorb.value = 1;
      if (_ctaFade.value != 0) _ctaFade.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 시트가 전체 화면을 덮으므로 상태바 회피는 raw window inset 으로 직접.
    final topInset = _statusBarHeight(context) + AppSpacing.md;
    final screenHeight = MediaQuery.of(context).size.height;
    return Material(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: ConcentricPageView(
              colors: _kPageColors,
              itemCount: _kPages.length,
              radius: _kRevealRadius,
              verticalPosition: _kRevealVerticalPosition,
              pageController: _pageController,
              onChange: (page) => setState(() => _page = page),
              onFinish: _finish,
              // 마지막 페이지는 CTA(내 관상 보기)가 있으므로 화살표 숨김.
              nextButtonBuilder: (_) => _page == _kPages.length - 1
                  ? const SizedBox.shrink()
                  : const _RevealButtonIcon(),
              itemBuilder: (index) => _OnboardingPage(
                data: _kPages[index],
                // 기능 3장은 이미지 여백을 텍스트(huge)의 절반으로 — 더 크게.
                imageHInset: index < _kPages.length - 1
                    ? AppSpacing.lg
                    : AppSpacing.huge,
              ),
            ),
          ),
          // 원판 흡수 cover — 패키지 버튼과 동일 좌표 (verticalPosition * H,
          // 지름 = radius * 2), 색은 마지막 직전 페이지 배경.
          Positioned(
            top: screenHeight * _kRevealVerticalPosition,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1, end: 0).animate(
                    CurvedAnimation(
                      parent: _discAbsorb,
                      curve: Curves.easeInCubic,
                    ),
                  ),
                  child: Container(
                    width: _kRevealRadius * 2,
                    height: _kRevealRadius * 2,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kPageColors[_kPages.length - 2],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // "내 관상 보기" CTA — 흡수된 원판과 같은 세로 중심선
          // (verticalPosition * H + radius)에서 흡수 완료 후 fade-in.
          // 버튼 높이 48 의 절반만큼 올려 원 중심과 정렬한다.
          Positioned(
            top: screenHeight * _kRevealVerticalPosition +
                _kRevealRadius -
                24,
            left: 0,
            right: 0,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: AnimatedBuilder(
                animation: _ctaFade,
                builder: (_, child) => IgnorePointer(
                  ignoring: _ctaFade.value == 0,
                  child: Opacity(
                    opacity: Curves.easeOut.transform(_ctaFade.value),
                    child: child,
                  ),
                ),
                child: PrimaryButton(
                  label: '내 관상 보기',
                  onPressed: _finish,
                ),
              ),
            ),
          ),
          // 상단 오버레이 — 좌 "다시 보지 않기" / 중앙 dots / 우 "건너뛰기".
          // PageView 밖이라 페이지 스케일 애니메이션의 영향을 받지 않는다.
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.sm,
              topInset,
              AppSpacing.sm,
              AppSpacing.xs,
            ),
            child: SizedBox(
              height: _kTopBarHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.of(context)
                          .pop(OnboardingIntroResult.neverAgain),
                      child: Text(
                        '다시 보지 않기',
                        style: AppText.caption
                            .copyWith(color: AppColors.textHint),
                      ),
                    ),
                  ),
                  _Dots(current: _page),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(context)
                          .pop(OnboardingIntroResult.later),
                      child: Text(
                        '건너뛰기',
                        style: AppText.caption
                            .copyWith(color: AppColors.textHint),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _finish() =>
      Navigator.of(context).pop(OnboardingIntroResult.startCapture);
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  /// 일러스트 좌우 여백 — 기능 3장(관상·궁합·케미)은 텍스트 여백의 절반으로
  /// 이미지를 더 크게, 마지막 장(banner)은 텍스트와 동일.
  final double imageHInset;

  const _OnboardingPage({required this.data, required this.imageHInset});

  @override
  Widget build(BuildContext context) {
    final titleColor =
        data.warm ? AppColors.darkBrown : AppColors.textPrimary;
    final bodyColor =
        data.warm ? AppColors.warmBrown : AppColors.textSecondary;
    // 시트가 전체 화면을 덮으므로 상태바 + 상단 컨트롤 바 아래에서 시작.
    final topInset = _statusBarHeight(context) +
        AppSpacing.md +
        _kTopBarHeight +
        AppSpacing.sm;
    // 좌우 여백은 요소별로: 일러스트 = imageHInset, 텍스트·chip = huge.
    return Padding(
      padding: EdgeInsets.only(top: topInset, bottom: _kContentBottomInset),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 일러스트 — 라운드 클립만, 외곽선 없음.
          // Flexible + loose 제약: 이미지가 비율 그대로 축소돼 letterbox 없이
          // 렌더된다 (작은 화면 overflow 방지).
          Flexible(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: imageHInset),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Image.asset(data.asset, fit: BoxFit.contain),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.huge),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.huge),
            child: Text(
              data.title,
              style: AppText.display.copyWith(color: titleColor),
              textAlign: TextAlign.center,
            ),
          ),
          if (data.chips.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final chip in data.chips)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                    ),
                    child: _PriceChip(label: chip),
                  ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.huge),
            child: Text(
              data.body,
              style: AppText.body.copyWith(color: bodyColor),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPageData {
  final String asset;
  final String title;
  final List<String> chips;
  final String body;

  /// cream/shell 배경 페이지 — DESIGN.md §1.2 warm beige 짝
  /// (darkBrown 타이틀 + warmBrown 본문)을 쓴다.
  final bool warm;

  const _OnboardingPageData({
    required this.asset,
    required this.title,
    this.chips = const [],
    required this.body,
    required this.warm,
  });
}

/// 무료·유료 표기 chip — §3.3 단일톤. 배경색 페이지 위에서도 보이도록
/// 흰 바탕 + hairline border (§3.2 카드 chrome 과 동일 언어).
class _PriceChip extends StatelessWidget {
  final String label;

  const _PriceChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

/// 동심원 버튼 위 화살표 — 보더 없이 화살표만. 원판 자체 색은 패키지가
/// 다음 페이지 배경색으로 채운다.
class _RevealButtonIcon extends StatelessWidget {
  const _RevealButtonIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: FaIcon(
        FontAwesomeIcons.arrowRight,
        size: 18,
        color: AppColors.textPrimary,
      ),
    );
  }
}
