import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/widgets/my_face_capture_flow.dart';
import 'package:facely/presentation/widgets/my_face_header.dart';
import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:top_snackbar_flutter/tap_bounce_container.dart';

/// 내 관상 미설정 nudge 배너 — 관상·궁합·교감 3개 탭 공통 (MainApp 오버레이).
/// 탭 전환마다 위에서 슬라이드-다운으로 재등장하고, 탭하면(bounce 후)
/// 슬라이드-업으로 닫힌다 (해당 탭에서만 — 탭을 옮기면 다시 나타남).
/// 등록되는 순간 전 탭에서 사라진다.
/// 하단 [내 관상 등록하기] CTA 는 닫힘 애니메이션 완료 후 촬영 플로우를 연다.
///
/// entry 는 **직접 소유** — showTopSnackBar 를 쓰지 않는다. 패키지의 이전-entry
/// 교체가 전역 변수 하나라, 앱 곳곳의 CompactSnackBar 토스트가 그 포인터를
/// 가로채면 배너 제거 핸들이 유실돼 persistent entry 가 무한 중첩됐다.
///
/// 이 위젯 자체는 로컬 [Overlay] 호스트다 — entry 를 MainApp Stack 안에 가둬,
/// 위에 push 되는 라우트(카메라 등)가 배너를 덮도록 한다. 배너가 떠 있는 동안
/// 아래 콘텐츠에는 dim barrier 가 깔린다 (dim 탭 = 배너 닫기).
///
/// 본문은 공용 [MyFaceHeader] 의 미설정 상태 재사용 (§0.0.3 같은 역할 =
/// 같은 위젯).
class MyFaceNudgeBanner extends ConsumerStatefulWidget {
  const MyFaceNudgeBanner({super.key});

  @override
  ConsumerState<MyFaceNudgeBanner> createState() => _MyFaceNudgeBannerState();
}

/// 사용자가 nudge 배너를 닫은 탭 (null = 닫지 않음). 배너 위젯이 소비하고,
/// 다른 화면이 [restore] 로 배너를 다시 부를 수 있다.
final nudgeDismissedTabProvider =
    NotifierProvider<NudgeDismissedTabNotifier, int?>(
  NudgeDismissedTabNotifier.new,
);

class NudgeDismissedTabNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void dismiss(int tab) => state = tab;

  /// 닫힘 해제 — 배너가 슬라이드-다운으로 재등장한다.
  void restore() => state = null;
}

/// dim barrier 색 — 화면-국지 일회성 (DESIGN.md §2.4).
const _kBarrierColor = Colors.black38;

const _kAnimDuration = Duration(milliseconds: 350);

class _MyFaceNudgeBannerState extends ConsumerState<MyFaceNudgeBanner>
    with TickerProviderStateMixin {
  final _overlayKey = GlobalKey<OverlayState>();

  /// 배너 슬라이드 (다운=forward / 업=reverse).
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: _kAnimDuration,
  );
  late final Animation<Offset> _offset = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(
    parent: _slide,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  ));

  /// dim barrier — 배너와 같은 350ms 로 페이드 인/아웃.
  late final AnimationController _barrier = AnimationController(
    vsync: this,
    duration: _kAnimDuration,
  );

  OverlayEntry? _snackEntry;
  OverlayEntry? _barrierEntry;
  int? _shownTab; // 배너가 떠 있는 탭
  bool _dismissing = false; // 닫힘 애니메이션 진행 중 — _sync 개입 차단

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    _slide.dispose();
    _barrier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(historyProvider, (_, _) => _sync());
    ref.listen(selectedTabProvider, (_, _) => _sync());
    ref.listen(nudgeDismissedTabProvider, (_, _) => _sync());
    // 빈 Overlay 는 그리지도 hit-test 되지도 않는다 — entry 만 담는 극장.
    return Overlay(key: _overlayKey);
  }

  void _sync() {
    if (!mounted || _dismissing) return;
    final hasMyFace = ref.read(historyProvider).any((r) => r.isMyFace);
    final tab = ref.read(selectedTabProvider);
    final dismissedTab = ref.read(nudgeDismissedTabProvider);
    // 닫은 탭을 벗어나면 dismissal 해제 — 다음 진입 때 다시 나타난다.
    // (restore 가 listener 로 _sync 를 재발화시키지만 즉시 수렴한다.)
    if (dismissedTab != null && dismissedTab != tab) {
      ref.read(nudgeDismissedTabProvider.notifier).restore();
      return;
    }
    // 설정 탭(3)은 제외 — 관상/궁합/교감에서만 nudge.
    final shouldShow = !hasMyFace && tab <= 2 && dismissedTab != tab;
    if (shouldShow && (_snackEntry == null || _shownTab != tab)) {
      _show(tab);
    } else if (!shouldShow && _snackEntry != null) {
      _hideInstant();
    }
  }

  void _show(int tab) {
    final overlay = _overlayKey.currentState;
    if (overlay == null) return;
    // 이전 entry 는 무조건 직접 제거 — 중첩 원천 차단 (소유권이 우리에게 있다).
    _removeSnack();
    _shownTab = tab;
    _showBarrier(overlay);
    _snackEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SlideTransition(
          position: _offset,
          child: TapBounceContainer(
            onTap: _dismissByUser,
            child: _bannerBody(),
          ),
        ),
      ),
    );
    overlay.insert(_snackEntry!);
    _slide.forward(from: 0);
  }

  Widget _bannerBody() {
    return Material(
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
              // 탭 제스처는 TapBounceContainer 가 갖는다 — InkWell 금지.
            ),
            // CTA — 헤더 하단 hairline 아래 행동 슬롯 (§3.9).
            // 버튼이 gesture arena 를 이겨 배너 탭-닫힘과 충돌하지 않는다.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: PrimaryButton(
                label: '내 관상 등록하기',
                // 스낵바·dim 닫힘 애니메이션이 완전히 끝난 뒤 등록 페이지 진입.
                onPressed: () async {
                  await _dismissByUser();
                  if (!mounted) return;
                  await startMyFaceCapture(context, ref);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// dim barrier 를 배너 entry 아래 층에 깐다. 탭 = 배너 닫기.
  void _showBarrier(OverlayState overlay) {
    if (_barrierEntry == null) {
      _barrierEntry = OverlayEntry(
        builder: (_) => FadeTransition(
          opacity: _barrier,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissByUser,
            child: const ColoredBox(
              color: _kBarrierColor,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      overlay.insert(_barrierEntry!); // 배너 insert 전 — 항상 아래 층.
    }
    _barrier.forward();
  }

  void _removeSnack() {
    _slide.stop();
    _snackEntry?.remove();
    _snackEntry = null;
  }

  void _removeBarrier() {
    _barrier.stop();
    _barrierEntry?.remove();
    _barrierEntry = null;
    _barrier.value = 0;
  }

  /// 배너 본체 탭 / dim 탭 / CTA 공용 — 슬라이드-업 + 페이드-아웃이 완전히
  /// 끝난 뒤 entry 를 걷는다. 반환 Future 는 그 시점에 완료.
  Future<void> _dismissByUser() async {
    final tab = _shownTab;
    if (_snackEntry == null || tab == null || _dismissing) return;
    _dismissing = true;
    try {
      // orCancel — 중도 취소돼도 (영원히 미완료 대신) throw 로 빠져나온다.
      await Future.wait<void>([
        _slide.reverse().orCancel,
        _barrier.reverse().orCancel,
      ]);
    } on TickerCanceled {
      // 취소돼도 아래 정리는 동일.
    } finally {
      _removeSnack();
      _removeBarrier();
      _dismissing = false;
    }
    ref.read(nudgeDismissedTabProvider.notifier).dismiss(tab);
  }

  /// 프로그램적 숨김 (등록 완료·설정 탭 진입) — 애니메이션 없이 즉시 제거.
  void _hideInstant() {
    _removeSnack();
    _removeBarrier();
    _slide.value = 0;
  }
}
