import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/my_face_header.dart';

/// 내 관상 미설정 nudge 배너 — 홈·관상·궁합 3개 탭 공통 (MainApp 오버레이).
/// 탭 전환마다 위에서 살짝 내려오는 슬라이드 애니메이션으로 재등장하고,
/// 탭하면 내 관상 등록 플로우, 등록되는 순간 전 탭에서 사라진다.
///
/// 본문은 공용 [MyFaceHeader] 의 미설정 상태 재사용 (§0.0.3 같은 역할 =
/// 같은 위젯) — 금테 원형 아바타(userPlus) + 금색 eyebrow + 타이틀 +
/// 회색 caption 설명으로 구성된 §3.7 identity 슬롯과 동일한 모습.
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
          child: MyFaceHeader(
            myFace: null,
            unsetCaption: '셀카 한 장이면 끝, 궁합과 교감도에 쓰여요.',
            onTap: () => startMyFaceCapture(context, ref),
          ),
        ),
      ),
    );
  }
}
