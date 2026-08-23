import 'package:flutter/material.dart';

import 'package:facely/core/theme.dart';

/// 되돌릴 수 없는 비동기 작업이 도는 동안 화면을 막고 스피너를 띄운다.
///
/// 결제·탈퇴처럼 **네트워크 왕복이 여러 번 이어지는 구간**이 대상이다. 아무
/// 표시 없이 몇 초가 지나면 사용자는 탭이 먹지 않았다고 판단해 다시 누르고,
/// 그 사이 화면은 멀쩡해 보이므로 두 번 결제된 것처럼 느낀다.
///
/// 스피너 스펙은 [PrimaryButton] 의 busy 상태와 같다 (§0.0.1 같은 역할 =
/// 같은 token). 문구는 넣지 않는다 — 진행 중이라는 사실 외에 더 알릴 게 없다.
///
/// ```dart
/// final loader = showBlockingLoader(context);
/// try {
///   await something();
/// } finally {
///   loader.dismiss();
/// }
/// ```
BlockingLoaderHandle showBlockingLoader(BuildContext context) {
  // 라우트는 showDialog 호출 시점에 스택에 올라가지만 builder 는 다음 프레임에
  // 돈다. 그래서 pop 대상을 builder 가 아니라 여기서 잡아둬야, 작업이 즉시
  // 끝나 dismiss 가 먼저 불려도 스피너가 남지 않는다.
  final navigator = Navigator.of(context, rootNavigator: true);
  final handle = BlockingLoaderHandle._(navigator);
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      // 뒤로가기로 닫히면 handle 이 다음에 진짜 화면을 pop 해버린다.
      canPop: false,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.textPrimary),
          ),
        ),
      ),
    ),
  );
  return handle;
}

class BlockingLoaderHandle {
  BlockingLoaderHandle._(this._navigator);

  final NavigatorState _navigator;
  bool _dismissed = false;

  /// 몇 번 불려도 한 번만 닫는다 — 오류 경로와 `finally` 가 겹쳐도 안전하다.
  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    if (_navigator.canPop()) _navigator.pop();
  }
}
