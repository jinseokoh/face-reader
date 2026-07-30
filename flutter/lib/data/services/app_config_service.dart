import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 강제 업그레이드 판단 결과.
typedef ForceUpdateResult = ({bool required, String? notice});

/// app_config 단일 행 기반 강제 업그레이드 판정 — 앱 시작 시 1회.
/// 정책 발동/해제는 Supabase SQL Editor 에서 min_build 갱신으로만.
class AppConfigService {
  AppConfigService._();
  static final instance = AppConfigService._();

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
      debugPrint('[AppConfig] force-update check skipped: $e');
      return pass;
    }
  }
}
