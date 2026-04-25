import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Firebase Analytics 이벤트 단일 진입점.
/// 추적 이벤트 화이트리스트:
///   app_open, camera_open, album_open, click_compat,
///   click_coin1, click_coin3, click_coin10
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final FirebaseAnalytics _fa = FirebaseAnalytics.instance;

  Future<void> logAppOpen() => _log('app_open');
  Future<void> logCameraOpen() => _log('camera_open');
  Future<void> logAlbumOpen() => _log('album_open');
  Future<void> logClickCompat() => _log('click_compat');

  /// 코인 상품 클릭 — coins 가 1/3/10 일 때만 화이트리스트에 들어감.
  /// 그 외 값은 무시 (이름이 폭발적으로 늘어나지 않게).
  Future<void> logClickCoin(int coins) {
    if (coins != 1 && coins != 3 && coins != 10) return Future.value();
    return _log('click_coin$coins');
  }

  Future<void> _log(String name) async {
    try {
      await _fa.logEvent(name: name);
    } catch (e) {
      debugPrint('[Analytics] $name failed: $e');
    }
  }
}
