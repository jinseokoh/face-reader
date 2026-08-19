// 코퍼스 버전 캐시 — 온보딩이 원격 조회를 앞지르는 문제의 회귀 방지.
//
// 온보딩은 첫 프레임 직후에 뜨는데(app.dart 의 addPostFrameCallback) 원격
// 조회는 네트워크라 수백 ms 가 걸린다. 메모리 기본값만 두면 온보딩은 매번
// 조회를 앞질러 v1 을 읽는다. 마지막으로 받은 값을 Hive 에 남겨 다음 실행의
// 시작값으로 쓰는 것이 이 캐시의 목적이다.
//
// 실행:
//   flutter test test/app_config_narrative_cache_test.dart

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/data/services/app_config_service.dart';
import 'package:facely/domain/services/life_question_narrative.dart';
import 'package:face_engine/domain/services/compat/compat_narrative.dart';

void main() {
  setUp(() async {
    Hive.init('.dart_tool/test_hive_app_config');
    if (!Hive.isBoxOpen(HiveBoxes.prefs)) {
      await Hive.openBox<String>(HiveBoxes.prefs);
    }
    await Hive.box<String>(HiveBoxes.prefs).clear();
    AppConfigService.instance.debugResetNarrativeVersion();
  });

  tearDown(() async {
    await Hive.box<String>(HiveBoxes.prefs).clear();
    AppConfigService.instance.debugResetNarrativeVersion();
  });

  test('캐시가 비어 있으면 v2 — 최초 설치 직후 첫 실행', () {
    // v1 은 상대의 앞으로의 행동을 단정하고 미래를 말하는 서술이라,
    // 조회가 안 될 때 그쪽이 나가는 것이 더 위험하다.
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v2);
    expect(AppConfigService.instance.compatVersion, CompatVersion.v2);
  });

  test('온보딩 제목 — v1 은 v1 확정일 때만', () {
    // 온보딩의 resolvedTitle 조건과 같은 식.
    bool usesV1Title() =>
        AppConfigService.instance.narrativeVersion == NarrativeVersion.v1;

    expect(usesV1Title(), isFalse, reason: '모름 → v2 제목');

    AppConfigService.instance
        .debugApplyNarrativeVersion({'android_narrative_version': 1});
    expect(usesV1Title(), isTrue, reason: 'v1 확정 → v1 제목');

    AppConfigService.instance
        .debugApplyNarrativeVersion({'android_narrative_version': 2});
    expect(usesV1Title(), isFalse, reason: 'v2 확정 → v2 제목');
  });

  test("캐시에 '2' 가 있으면 조회 전에도 v2", () async {
    await Hive.box<String>(HiveBoxes.prefs).put('narrative_version', '2');
    AppConfigService.instance.debugResetNarrativeVersion();

    // 원격 조회를 하지 않은 상태 — 온보딩이 읽는 시점과 같다.
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v2);
    expect(AppConfigService.instance.compatVersion, CompatVersion.v2);
  });

  test('원격 값이 캐시에 남아 다음 실행의 시작값이 된다', () {
    AppConfigService.instance
        .debugApplyNarrativeVersion({'android_narrative_version': 2});
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v2);
    expect(
      Hive.box<String>(HiveBoxes.prefs).get('narrative_version'),
      '2',
      reason: '다음 실행이 읽을 값이 남아야 한다',
    );

    // 다음 실행 흉내 — 메모리 상태만 날린다.
    AppConfigService.instance.debugResetNarrativeVersion();
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v2);
  });

  test('조회는 한 번만 — 부팅과 강제 업그레이드 게이트가 같은 Future 를 쓴다', () {
    // 부팅(main.dart) 이 먼저 띄우고 MainApp.initState 가 결과를 받아 쓴다.
    // 두 호출이 각각 요청을 내면 앱 시작마다 원격 조회가 두 번 나간다.
    final first = AppConfigService.instance.checkForceUpdate();
    expect(identical(AppConfigService.instance.checkForceUpdate(), first),
        isTrue);
  });

  test('ready — 조회 전에는 즉시, 시작 뒤에는 조회가 끝나야 완료', () async {
    var done = false;
    // 아무도 조회를 시작하지 않았으면 기다릴 것이 없다.
    await AppConfigService.instance.ready;

    final check = AppConfigService.instance.checkForceUpdate();
    unawaited(AppConfigService.instance.ready.then((_) => done = true));
    expect(done, isFalse, reason: '조회가 끝나기 전에는 완료되면 안 된다');
    await check;
    await Future<void>.delayed(Duration.zero);
    expect(done, isTrue);
  });

  test('원격이 1 로 내려오면 캐시도 1 로 덮인다', () async {
    await Hive.box<String>(HiveBoxes.prefs).put('narrative_version', '2');
    AppConfigService.instance.debugResetNarrativeVersion();
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v2);

    AppConfigService.instance
        .debugApplyNarrativeVersion({'android_narrative_version': 1});
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v1);
    expect(Hive.box<String>(HiveBoxes.prefs).get('narrative_version'), '1');
  });
}
