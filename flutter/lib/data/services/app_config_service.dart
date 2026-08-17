import 'dart:io';

import 'package:face_engine/domain/services/compat/compat_narrative.dart';
import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/domain/services/life_question_narrative.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 강제 업그레이드 판단 결과.
typedef ForceUpdateResult = ({bool required, String? notice});

/// app_config 단일 행 기반 원격 설정 — 앱 시작 시 1회 조회.
/// 정책 변경은 Supabase SQL Editor 에서 컬럼 갱신으로만. 재배포 없음.
class AppConfigService {
  AppConfigService._();
  static final instance = AppConfigService._();

  /// 마지막으로 받은 코퍼스 버전을 담아 두는 prefs 키.
  static const String _kNarrativeVersionKey = 'narrative_version';

  NarrativeVersion? _narrativeVersion;
  bool _cacheRead = false;

  /// 서술 코퍼스 버전. `checkForceUpdate()` 가 같은 조회에서 갱신한다.
  ///
  /// 조회는 네트워크라 수백 ms 가 걸리는데 온보딩은 첫 프레임 직후에 뜬다
  /// (`app.dart` 의 `addPostFrameCallback`). 마지막으로 받은 값을 Hive 에
  /// 남겨 다음 실행부터 그 값으로 시작하지만, **최초 설치 직후 첫 실행**은
  /// 캐시가 없어 어느 쪽인지 알 수 없다.
  ///
  /// 확정 전 기본값은 **v2** 다. v1 은 사진 속 상대의 앞으로의 행동을
  /// 단정하고 미래를 말하는 서술이라, 조회가 안 될 때 그쪽이 나가는 것이
  /// 더 위험하다. 안전한 쪽으로 떨어뜨린다.
  NarrativeVersion get narrativeVersion {
    if (!_cacheRead) {
      _cacheRead = true;
      _narrativeVersion ??= _readCachedVersion();
    }
    return _narrativeVersion ?? NarrativeVersion.v2;
  }

  /// 캐시에 남은 값. 키가 없으면 null (= 아직 모름).
  static NarrativeVersion? _readCachedVersion() {
    try {
      final raw = Hive.box<String>(HiveBoxes.prefs).get(_kNarrativeVersionKey);
      if (raw == null) return null;
      return raw == '2' ? NarrativeVersion.v2 : NarrativeVersion.v1;
    } catch (e) {
      // 박스 미개방 (테스트·초기화 이전). 캐시 없음과 같게 취급한다.
      debugPrint('[AppConfig] narrative version cache unavailable: $e');
      return null;
    }
  }

  /// 궁합 코퍼스 버전 — 관상과 같은 컬럼을 쓴다. 플래그를 따로 두면 관상 v2 +
  /// 궁합 v1 같은 어긋난 조합까지 관리해야 하고 마이그레이션이 하나 더 쌓인다.
  /// `shared` 가 flutter 를 import 할 수 없어 enum 이 둘로 갈렸을 뿐이다.
  CompatVersion get compatVersion => narrativeVersion == NarrativeVersion.v2
      ? CompatVersion.v2
      : CompatVersion.v1;

  /// 내 buildNumber < 플랫폼별 min_build 면 required=true.
  /// 조회 실패·타임아웃은 fail-open (네트워크 사정으로 앱을 잠그지 않는다).
  Future<ForceUpdateResult> checkForceUpdate() async {
    const pass = (required: false, notice: null);
    try {
      final row = await Supabase.instance.client
          .from('app_config')
          .select()
          .eq('id', 1)
          .maybeSingle()
          .timeout(const Duration(seconds: 2));
      if (row == null) return pass;
      _applyNarrativeVersion(row);
      final minBuild =
          (Platform.isIOS
              ? row['ios_min_build']
              : row['android_min_build'])
              as int? ??
          1;
      final info = await PackageInfo.fromPlatform();
      final build = int.tryParse(info.buildNumber) ?? 0;
      return (required: build < minBuild, notice: row['notice'] as String?);
    } catch (e) {
      debugPrint('[AppConfig] remote config check skipped: $e');
      return pass;
    }
  }

  /// 플랫폼별 코퍼스 버전 컬럼을 읽는다. 컬럼이 없거나 값이 이상하면 v1.
  /// 받은 값은 다음 실행의 시작값이 되도록 Hive 에 남긴다.
  void _applyNarrativeVersion(Map<String, dynamic> row) {
    final v = (Platform.isIOS
        ? row['ios_narrative_version']
        : row['android_narrative_version']) as int?;
    _narrativeVersion = v == 2 ? NarrativeVersion.v2 : NarrativeVersion.v1;
    try {
      Hive.box<String>(HiveBoxes.prefs)
          .put(_kNarrativeVersionKey, v == 2 ? '2' : '1');
    } catch (e) {
      debugPrint('[AppConfig] narrative version cache write skipped: $e');
    }
  }

  /// 테스트 전용 — 메모리 상태만 날려 "다음 실행" 을 흉내 낸다.
  @visibleForTesting
  void debugResetNarrativeVersion() {
    _narrativeVersion = null;
    _cacheRead = false;
  }

  /// 테스트 전용 — 원격 row 적용 경로를 네트워크 없이 부른다.
  @visibleForTesting
  void debugApplyNarrativeVersion(Map<String, dynamic> row) =>
      _applyNarrativeVersion(row);
}
