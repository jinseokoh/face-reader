import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';

/// 내 관상 미설정 nudge 배너 — 홈·관상·궁합 3개 탭 공통 (MainApp 오버레이).
/// 탭 전환마다 위에서 살짝 내려오는 슬라이드 애니메이션으로 재등장하고,
/// 탭하면 내 관상 등록 플로우, 등록되는 순간 전 탭에서 사라진다.
/// (구 static 안내 컨테이너 대체 — 홈/관상 탭의 미설정 헤더는 숨김 처리)
class MyFaceNudgeBanner extends ConsumerStatefulWidget {
  const MyFaceNudgeBanner({super.key});

  @override
  ConsumerState<MyFaceNudgeBanner> createState() => _MyFaceNudgeBannerState();
}

class _MyFaceNudgeBannerState extends ConsumerState<MyFaceNudgeBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(_controller);

  int? _lastShownTab;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasMyFace =
        ref.watch(historyProvider).any((r) => r.isMyFace);
    final tab = ref.watch(selectedTabProvider);
    // 설정 탭(3)은 제외 — 홈/관상/궁합에서만 nudge.
    final show = !hasMyFace && tab <= 2;
    if (!show) {
      _lastShownTab = null;
      return const SizedBox.shrink();
    }
    // 탭이 바뀔 때마다 슬라이드-다운 재생.
    if (_lastShownTab != tab) {
      _lastShownTab = tab;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward(from: 0);
      });
    }

    return SlideTransition(
      position: _slide,
      child: Material(
        color: AppColors.background,
        elevation: 2,
        child: SafeArea(
          bottom: false,
          child: InkWell(
            onTap: () => startMyFaceCapture(context, ref),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 0.5),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  const FaIcon(
                    FontAwesomeIcons.userPlus,
                    size: 18,
                    color: AppColors.gold,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      '내 관상을 설정해주세요.',
                      style: AppText.subTitle.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const FaIcon(
                    FontAwesomeIcons.chevronRight,
                    size: 14,
                    color: AppColors.textHint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
