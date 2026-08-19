// 온보딩 첫 장 — 원격 코퍼스 버전에 따라 제목과 이미지가 갈린다.
// v1 확정이면 onboarding0.png, 그 외(v2·확정 전)는 onboarding1.png.
//
// 실행: flutter test test/onboarding_narrative_variant_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
  tearDown(() => AppConfigService.instance.debugResetNarrativeVersion());

  testWidgets('확정 전(=v2 기본값) — onboarding1.png', (tester) async {
    await _openIntro(tester);
    expect(_assets(tester), contains('assets/images/onboarding1.png'));
    expect(_assets(tester), isNot(contains('assets/images/onboarding0.png')));
  });

  testWidgets('v1 확정 — onboarding0.png', (tester) async {
    AppConfigService.instance.debugApplyNarrativeVersion(
      {'android_narrative_version': 1, 'ios_narrative_version': 1},
    );
    await _openIntro(tester);
    expect(_assets(tester), contains('assets/images/onboarding0.png'));
    expect(_assets(tester), isNot(contains('assets/images/onboarding1.png')));
  });

  testWidgets('v2 확정 — onboarding1.png', (tester) async {
    AppConfigService.instance.debugApplyNarrativeVersion(
      {'android_narrative_version': 2, 'ios_narrative_version': 2},
    );
    await _openIntro(tester);
    expect(_assets(tester), contains('assets/images/onboarding1.png'));
    expect(_assets(tester), isNot(contains('assets/images/onboarding0.png')));
  });
}
