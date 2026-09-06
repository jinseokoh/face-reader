// 온보딩 — 이미지는 페이지 번호 + 플랫폼(onboarding{n}-ios/android.png)으로만
// 정해지고, 첫 장 제목만 원격 코퍼스 버전(v1/v2)을 따른다.
//
// 실행: flutter test test/onboarding_narrative_variant_test.dart

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facely/core/edition.dart';
import 'package:facely/data/services/app_config_service.dart';
import 'package:facely/presentation/widgets/onboarding_intro.dart';

Set<String> _assets(WidgetTester tester) => tester
    .widgetList<Image>(find.byType(Image))
    .map((i) => i.image)
    .whereType<AssetImage>()
    .map((i) => i.assetName)
    .toSet();

Future<void> _openIntro(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () => showOnboardingIntro(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  final suffix = Platform.isIOS ? 'ios' : 'android';
  tearDown(() => AppConfigService.instance.debugResetNarrativeVersion());

  test('이미지 경로는 페이지 번호 + 플랫폼', () {
    expect(onboardingAssetPath(1), 'assets/images/onboarding1-$suffix.png');
    expect(onboardingAssetPath(4), 'assets/images/onboarding4-$suffix.png');
  });

  testWidgets('첫 장 이미지 — 확정 전(v2 기본값)에도 플랫폼 파일', (tester) async {
    await _openIntro(tester);
    expect(_assets(tester), contains('assets/images/onboarding1-$suffix.png'));
  });

  testWidgets('첫 장 이미지 — v1 확정이어도 같은 플랫폼 파일', (tester) async {
    AppConfigService.instance.debugApplyNarrativeVersion(
      {'android_narrative_version': 1, 'ios_narrative_version': 1},
    );
    await _openIntro(tester);
    expect(_assets(tester), contains('assets/images/onboarding1-$suffix.png'));
  });

  testWidgets('v1 확정이면 full 에디션 첫 장 제목이 v1 문구', (tester) async {
    if (kMeasureEdition) return;
    AppConfigService.instance.debugApplyNarrativeVersion(
      {'android_narrative_version': 1, 'ios_narrative_version': 1},
    );
    await _openIntro(tester);
    expect(find.textContaining('얼굴 특징을 측정하여'), findsOneWidget);
  });
}
