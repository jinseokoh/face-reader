import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../widgets/primary_button.dart';

/// 강제 업그레이드 게이트 — app_config 의 min_build 미달 시 앱 전체를 덮는
/// 닫을 수 없는 화면 (뒤로가기 차단). [업데이트] → 스토어.
class UpdateGateScreen extends StatelessWidget {
  /// app_config.notice — 없으면 기본 안내문.
  final String? notice;
  const UpdateGateScreen({super.key, this.notice});

  static const _kPlayStoreUrl =
      'https://play.google.com/store/apps/details?id=com.scienceintegration.facely';

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Image.asset(
                  'assets/images/emotion-namaste.png',
                  width: 84,
                  height: 84,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '새 버전 업데이트가 필요합니다',
                  textAlign: TextAlign.center,
                  style: AppText.modalTitle.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  notice ?? '지금 버전으로는 이용할 수 없습니다.\n최신 버전으로 업데이트해 주세요.',
                  textAlign: TextAlign.center,
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                ),
                const SizedBox(height: AppSpacing.xxl),
                PrimaryButton(
                  label: '업데이트',
                  onPressed: () => launchUrl(
                    Uri.parse(_kPlayStoreUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
