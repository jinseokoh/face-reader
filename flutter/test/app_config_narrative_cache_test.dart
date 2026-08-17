// 코퍼스 버전 캐시 — 온보딩이 원격 조회를 앞지르는 문제의 회귀 방지.
//
// 온보딩은 첫 프레임 직후에 뜨는데(app.dart 의 addPostFrameCallback) 원격
// 조회는 네트워크라 수백 ms 가 걸린다. 메모리 기본값만 두면 온보딩은 매번
// 조회를 앞질러 v1 을 읽는다. 마지막으로 받은 값을 Hive 에 남겨 다음 실행의
// 시작값으로 쓰는 것이 이 캐시의 목적이다.
//
// 실행:
//   flutter test test/app_config_narrative_cache_test.dart

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

  test('캐시가 비어 있으면 v1', () {
    expect(AppConfigService.instance.narrativeVersion, NarrativeVersion.v1);
    expect(AppConfigService.instance.compatVersion, CompatVersion.v1);
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
