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
const _kPageColors = [
  AppColors.cream,
  AppColors.background,
  AppColors.shell,
  AppColors.background,
];

const _kPages = [
  _OnboardingPageData(
    asset: 'assets/images/onboarding-physiognomy.png',
    title: '관상',
    chips: ['상세 풀이 무료'],
    body: '카메라로 찍거나 앨범 사진을 올리면\n관상 분석을 무료로 볼 수 있습니다.',
    warm: true,
  ),
  _OnboardingPageData(
    asset: 'assets/images/onboarding-compatibility.png',
    title: '궁합',
    chips: ['상세 풀이 유료'],
    body: '내 관상이 등록된 상태 이후에 올리는 어떤\n사진 속 인물과 나와의 궁합을 볼 수 있습니다.',
    warm: false,
  ),
  _OnboardingPageData(
    asset: 'assets/images/onboarding-chemistry.png',
    title: '케미',
    chips: ['결과표 무료', '상세 풀이 유료'],
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
const double _kRevealRadius = 40;
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

class _OnboardingIntroState extends State<_OnboardingIntro> {
  int _page = 0;

  @override
  Widget build(BuildContext context) {
    // 시트가 전체 화면을 덮으므로 상태바 회피는 raw window inset 으로 직접.
    final topInset = _statusBarHeight(context) + AppSpacing.md;
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
              onChange: (page) => setState(() => _page = page),
              onFinish: _finish,
              nextButtonBuilder: (_) => const _RevealButtonIcon(),
              itemBuilder: (index) => _OnboardingPage(
                data: _kPages[index],
                isLast: index == _kPages.length - 1,
                onStartCapture: _finish,
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
  final bool isLast;
  final VoidCallback onStartCapture;

  const _OnboardingPage({
    required this.data,
    required this.isLast,
    required this.onStartCapture,
  });

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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.huge,
        topInset,
        AppSpacing.huge,
        _kContentBottomInset,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 일러스트 — 라운드 클립만, 외곽선 없음.
          // Flexible + loose 제약: 이미지가 비율 그대로 축소돼 letterbox 없이
          // 렌더된다 (작은 화면 overflow 방지).
          Flexible(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              child: Image.asset(data.asset, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: AppSpacing.huge),
          Text(
            data.title,
            style: AppText.display.copyWith(color: titleColor),
            textAlign: TextAlign.center,
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
          Text(
            data.body,
            style: AppText.body.copyWith(color: bodyColor),
            textAlign: TextAlign.center,
          ),
          if (isLast) ...[
            const SizedBox(height: AppSpacing.xxl),
            PrimaryButton(label: '내 관상 보기', onPressed: onStartCapture),
          ],
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
