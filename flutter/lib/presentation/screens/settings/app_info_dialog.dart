import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/theme.dart';

/// 설정 > 앱 정보 팝업 — emotion 패밀리 이미지가 3초마다 랜덤으로 무한
/// 교체되는 애니메이션 + 버전 + 제작자. 구성: 이미지 / 버전 / 공대삼촌 / 확인.
class AppInfoDialog extends StatefulWidget {
  const AppInfoDialog({super.key});

  static Future<void> show(BuildContext context) => showDialog<void>(
    context: context,
    builder: (_) => const AppInfoDialog(),
  );

  @override
  State<AppInfoDialog> createState() => _AppInfoDialogState();
}

class _AppInfoDialogState extends State<AppInfoDialog> {
  static const _emotions = [
    'assets/images/emotion-anger.png',
    'assets/images/emotion-frown.png',
    'assets/images/emotion-happy.png',
    'assets/images/emotion-laugh.png',
    'assets/images/emotion-love.png',
    'assets/images/emotion-namaste.png',
    'assets/images/emotion-photo.png',
    'assets/images/emotion-sad.png',
    'assets/images/emotion-shrug.png',
    'assets/images/emotion-smile.png',
    'assets/images/emotion-surprise.png',
    'assets/images/emotion-yawn.png',
  ];

  final _random = Random();
  late int _index = _random.nextInt(_emotions.length);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      // 직전과 다른 이미지만 — 같은 그림이 두 번 연속이면 멈춘 듯 보인다.
      var next = _random.nextInt(_emotions.length - 1);
      if (next >= _index) next += 1;
      setState(() => _index = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: AppSpacing.sm),
          // EmotionEmptyState 와 동일 스케일(84) — fade 교체.
          Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 400),
              child: Image.asset(
                _emotions[_index],
                key: ValueKey(_index),
                width: 84,
                height: 84,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData
                  ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                  : '…';
              return Text(
                '버전 $version',
                style: AppText.body.copyWith(color: AppColors.textSecondary),
              );
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '공대삼촌',
            style: AppText.caption.copyWith(color: AppColors.textHint),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('확인', style: AppText.subTitle),
        ),
      ],
    );
  }
}
