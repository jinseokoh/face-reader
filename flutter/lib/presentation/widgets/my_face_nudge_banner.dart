import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/my_face_header.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_snackbar_flutter/safe_area_values.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

/// 내 관상 미설정 nudge 배너 — 홈·관상·궁합 3개 탭 공통 (MainApp 오버레이).
/// top_snackbar_flutter 커스터마이즈: 탭 전환마다 위에서 슬라이드-다운으로
/// 재등장하고, 탭하면(bounce 후) 슬라이드-업으로 닫힌다 (해당 탭에서만 —
/// 탭을 옮기면 다시 나타남). 등록되는 순간 전 탭에서 사라진다.
/// 하단 [바로가기] CTA 는 내 관상 촬영 플로우(startMyFaceCapture)를 연다.
///
/// 이 위젯 자체는 로컬 [Overlay] 호스트다 — 스낵바 entry 를 MainApp Stack
/// 안에 가둬, 위에 push 되는 라우트(카메라 등)가 배너를 덮도록 한다.
///
/// 본문은 공용 [MyFaceHeader] 의 미설정 상태 재사용 (§0.0.3 같은 역할 =
/// 같은 위젯) — 금테 원형 아바타(userPlus) + 금색 eyebrow + 타이틀 +
/// 회색 caption 설명으로 구성된 §3.7 identity 슬롯과 동일한 모습.
class MyFaceNudgeBanner extends ConsumerStatefulWidget {
  const MyFaceNudgeBanner({super.key});

  @override
  ConsumerState<MyFaceNudgeBanner> createState() => _MyFaceNudgeBannerState();
}

class _MyFaceNudgeBannerState extends ConsumerState<MyFaceNudgeBanner> {
  final _overlayKey = GlobalKey<OverlayState>();

  /// 현재 떠 있는 스낵바의 controller — 프로그램적 dismiss 용.
  AnimationController? _snackController;
  bool _visible = false;
  int? _shownTab; // 배너가 떠 있는 탭
  int? _dismissedTab; // 사용자가 탭해서 닫은 탭 — 그 탭에서만 숨김 유지

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(historyProvider, (_, _) => _sync());
    ref.listen(selectedTabProvider, (_, _) => _sync());
    // 빈 Overlay 는 그리지도 hit-test 되지도 않는다 — entry 만 담는 극장.
    return Overlay(key: _overlayKey);
  }

  void _sync() {
    if (!mounted) return;
    final hasMyFace = ref.read(historyProvider).any((r) => r.isMyFace);
    final tab = ref.read(selectedTabProvider);
    // 닫은 탭을 벗어나면 dismissal 해제 — 다음 진입 때 다시 나타난다.
    if (_dismissedTab != null && _dismissedTab != tab) {
      _dismissedTab = null;
    }
    // 설정 탭(3)은 제외 — 홈/관상/궁합에서만 nudge.
    final shouldShow = !hasMyFace && tab <= 2 && _dismissedTab != tab;
    if (shouldShow && (!_visible || _shownTab != tab)) {
      _show(tab); // showTopSnackBar 가 이전 entry 를 스스로 교체한다.
    } else if (!shouldShow && _visible) {
      // 즉시 제거 — value=0 이 dismissed status 를 발화시켜 entry 가 걷힌다.
      _snackController?.value = 0;
    }
  }

  void _show(int tab) {
    final overlay = _overlayKey.currentState;
    if (overlay == null) return;
    _visible = true;
    _shownTab = tab;
    // entry 교체 시 이전 controller 는 dispose 된다 — 새 controller 가
    // onAnimationControllerInit 으로 들어올 때까지 죽은 참조를 비워 둔다.
    _snackController = null;
    showTopSnackBar(
      overlay,
      Material(
        color: AppColors.background,
        elevation: 2,
        child: SafeArea(
          bottom: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MyFaceHeader(
                myFace: null,
                unsetCaption: '앨범 사진이나 사진 촬영으로 등록해주세요.',
                // 배너 위계 전용 — 세로 huge 로 §3.7 기본보다 약 1.5배 높이.
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.huge,
                ),
                // 탭 제스처는 패키지 TapBounceContainer 가 갖는다 — InkWell 금지.
              ),
              // 바로가기 CTA — 헤더 하단 hairline 아래 행동 슬롯 (§3.9).
              // 버튼이 gesture arena 를 이겨 배너 탭-닫힘과 충돌하지 않는다.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                child: PrimaryButton(
                  label: '바로가기',
                  onPressed: () => startMyFaceCapture(context, ref),
                ),
              ),
            ],
          ),
        ),
      ),
      // persistent — 자동 숨김 없음. 닫힘은 아래 onTap 의 reverse 로만.
      persistent: true,
      animationDuration: const Duration(milliseconds: 350),
      reverseAnimationDuration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
      // full-bleed chrome — 패키지 여백·SafeArea 를 끄고 child 가 상태바까지 덮는다.
      padding: EdgeInsets.zero,
      safeAreaValues: const SafeAreaValues(
        top: false,
        bottom: false,
        left: false,
        right: false,
      ),
      dismissType: DismissType.onTap,
      onAnimationControllerInit: (c) => _snackController = c,
      onTap: () {
        // 탭 = 슬라이드-업 닫기 (persistent 라 직접 reverse).
        _dismissedTab = _shownTab;
        _snackController?.reverse();
      },
      onDismissed: () {
        _visible = false;
        _snackController = null;
      },
    );
  }
}
