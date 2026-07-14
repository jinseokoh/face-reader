import 'package:flutter/material.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/widgets/primary_button.dart';

/// 온보딩 안내 — 관상 → 궁합 → 케미 → 시작(내 관상 등록) 4페이지 좌우 스와이프
/// 인트로. MainApp 이 첫 프레임 뒤에 호출한다.
///
/// 내 관상이 등록되거나 "다시 보지 않기"를 누르기 전까지 매 실행 노출.
/// [OnboardingIntroResult] 처리(촬영 진입·flag 기록)는 호출부 몫.
///
/// 제시는 캡처 플로우와 동일한 full-screen showModalBottomSheet 레시피.
/// 바깥 탭·드래그 닫힘은 막는다 — 페이지 스와이프와 제스처가 겹치지 않도록.
Future<OnboardingIntroResult> showOnboardingIntro(BuildContext context) async {
  final size = MediaQuery.of(context).size;
  final result = await showModalBottomSheet<OnboardingIntroResult>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    useSafeArea: true,
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

enum OnboardingIntroResult {
  /// "내 관상 보기" CTA — 촬영 플로우로 이어간다.
  startCapture,

  /// "다시 보지 않기" — flag 를 기록해 이후 노출을 끈다.
  neverAgain,

  /// 건너뛰기·뒤로가기 — 기록 없음, 다음 실행 때 다시 노출.
  later,
}

/// prefs box 의 "다시 보지 않기" flag 키. 값은 '1' 하나만 쓴다.
const String kOnboardingNeverAgainKey = 'onboarding_never_again';

const _kAnimDuration = Duration(milliseconds: 350);
const double _kIllustrationHeight = 220;

class _OnboardingPageData {
  final String asset;
  final String title;
  final List<String> chips;
  final String body;

  const _OnboardingPageData({
    required this.asset,
    required this.title,
    this.chips = const [],
    required this.body,
  });
}

const _kPages = [
  _OnboardingPageData(
    asset: 'assets/images/onboarding-physiognomy.png',
    title: '관상',
    chips: ['무료'],
    body: '카메라로 찍거나 앨범 사진을 올리면\n내 관상 분석을 바로 볼 수 있습니다.\n횟수 제한이 없습니다.',
  ),
  _OnboardingPageData(
    asset: 'assets/images/onboarding-compatibility.png',
    title: '궁합',
    chips: ['유료'],
    body: '상대방이 보낸 관상을 북마크하거나\n앨범 사진을 올리면\n나와 상대의 궁합을 볼 수 있습니다.',
  ),
  _OnboardingPageData(
    asset: 'assets/images/onboarding-chemistry.png',
    title: '케미',
    chips: ['결과표 무료', '상세 풀이 유료'],
    body: '그룹을 만들고 참여자 전원이 관상을 올리면\n모든 사람 사이의 케미 결과표가 완성됩니다.',
  ),
  _OnboardingPageData(
    asset: 'assets/images/banner.png',
    title: '시작은 내 관상부터',
    body: '궁합과 케미는 내 관상이 등록되어 있어야\n이용할 수 있습니다.\n지금 내 관상부터 확인해보세요.',
  ),
];

class _OnboardingIntro extends StatefulWidget {
  const _OnboardingIntro();

  @override
  State<_OnboardingIntro> createState() => _OnboardingIntroState();
}

class _OnboardingIntroState extends State<_OnboardingIntro> {
  final _controller = PageController();
  int _page = 0;

  bool get _isLast => _page == _kPages.length - 1;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    _controller.nextPage(duration: _kAnimDuration, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      child: Material(
        color: AppColors.background,
        child: SafeArea(
          child: Column(
            children: [
              // 상단 건너뛰기 — 기록 없이 닫기, 다음 실행 때 다시 노출.
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  child: TextButton(
                    onPressed: () => Navigator.of(context)
                        .pop(OnboardingIntroResult.later),
                    child: Text(
                      '건너뛰기',
                      style:
                          AppText.caption.copyWith(color: AppColors.textHint),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _controller,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final page in _kPages) _OnboardingPage(data: page),
                  ],
                ),
              ),
              _Dots(current: _page),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: PrimaryButton(
                  label: _isLast ? '내 관상 보기' : '다음',
                  onPressed: _isLast
                      ? () => Navigator.of(context)
                          .pop(OnboardingIntroResult.startCapture)
                      : _next,
                ),
              ),
              // 명시적 노출 종료 — 이 버튼만 flag 를 남긴다.
              SizedBox(
                height: 40,
                child: TextButton(
                  onPressed: () => Navigator.of(context)
                      .pop(OnboardingIntroResult.neverAgain),
                  child: Text(
                    '다시 보지 않기',
                    style: AppText.caption.copyWith(color: AppColors.textHint),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final _OnboardingPageData data;

  const _OnboardingPage({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.huge),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Image.asset(
            data.asset,
            height: _kIllustrationHeight,
            fit: BoxFit.contain,
          ),
          const SizedBox(height: AppSpacing.huge),
          Text(data.title, style: AppText.display, textAlign: TextAlign.center),
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
          Text(data.body, style: AppText.body, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

/// 무료·유료 표기 chip — §3.3 단일톤 (surface bg + AppRadius.sm + caption).
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        label,
        style: AppText.caption.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int current;

  const _Dots({required this.current});

  @override
  Widget build(BuildContext context) {
    return Row(
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
