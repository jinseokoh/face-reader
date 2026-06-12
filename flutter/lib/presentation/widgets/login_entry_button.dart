import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/presentation/widgets/primary_button.dart';
import 'package:facely/presentation/widgets/login_bottom_sheet.dart';

/// 비로그인 화면의 중립 로그인/가입 진입 버튼 — 탭 시 `LoginBottomSheet`
/// (카카오 + 이메일 가입/로그인 + OTP) 노출.
///
/// SSOT: settings / ledger / 기타 빈-상태 화면이 동일 위젯 공유.
/// (예전엔 두 곳이 카카오 yellow + 220×46 / infinity×48 로 disparate 했음.)
class LoginEntryButton extends ConsumerWidget {
  const LoginEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PrimaryButton(
      label: '로그인 / 가입',
      onPressed: () => showLoginBottomSheet(context, ref),
    );
  }
}
