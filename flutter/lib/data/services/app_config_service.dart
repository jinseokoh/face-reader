import 'dart:io';

import 'package:facely/domain/services/life_question_narrative.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 강제 업그레이드 판단 결과.
typedef ForceUpdateResult = ({bool required, String? notice});

/// app_config 단일 행 기반 원격 설정 — 앱 시작 시 1회 조회.
/// 정책 변경은 Supabase SQL Editor 에서 컬럼 갱신으로만. 재배포 없음.
class AppConfigService {
  AppConfigService._();
  static final instance = AppConfigService._();

  /// 서술 코퍼스 버전. `checkForceUpdate()` 가 같은 조회에서 채운다.
  /// 조회 전·실패 시에는 v1 — 현행 서술이 나온다.
  NarrativeVersion narrativeVersion = NarrativeVersion.v1;

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
  void _applyNarrativeVersion(Map<String, dynamic> row) {
    final v = (Platform.isIOS
        ? row['ios_narrative_version']
        : row['android_narrative_version']) as int?;
    narrativeVersion = v == 2 ? NarrativeVersion.v2 : NarrativeVersion.v1;
  }
}
