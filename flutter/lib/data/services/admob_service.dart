import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// AdMob rewarded video — phase 1: Google 공식 test ad unit ID 기본값.
///
/// Release 전 교체 대상:
///   - `.env` : ADMOB_REWARDED_UNIT_ID_IOS / ADMOB_REWARDED_UNIT_ID_ANDROID
///   - AndroidManifest.xml : meta-data `com.google.android.gms.ads.APPLICATION_ID`
///   - ios/Runner/Info.plist : `GADApplicationIdentifier`
///
/// 무료 코인 흐름은 `FreeCoinService.recordView()` 가 서버 측에서 진행도 누적
/// + 3편 도달 시 자동 grant 처리. AdMobService 는 광고 노출 + earned 콜백만
/// 책임. earned=true 일 때만 server RPC 호출.
class AdMobService {
  static final AdMobService _instance = AdMobService._();
  factory AdMobService() => _instance;
  AdMobService._();

  // Google 공식 rewarded ad test unit ID — 개발/디버그용 영구 유효.
  static const _testRewardedIdAndroid =
      'ca-app-pub-3940256099942544/5224354917';
  static const _testRewardedIdIos = 'ca-app-pub-3940256099942544/1712485313';

  bool _initialized = false;
  bool get isAvailable => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await MobileAds.instance.initialize();
      _initialized = true;
      debugPrint('[AdMob] initialized');
    } catch (e) {
      debugPrint('[AdMob] initialize failed: $e');
    }
  }

  String _rewardedUnitId() {
    // debug 빌드는 항상 Google 공식 test 유닛 — 실 유닛은 debug/미등록 기기에서
    // no-fill 이 잦고 정책 위반 위험이 있다. 실 유닛(.env)은 release 에서만 사용.
    if (kDebugMode) {
      return Platform.isIOS ? _testRewardedIdIos : _testRewardedIdAndroid;
    }
    final envKey = Platform.isIOS
        ? 'ADMOB_REWARDED_UNIT_ID_IOS'
        : 'ADMOB_REWARDED_UNIT_ID_ANDROID';
    final v = dotenv.env[envKey]?.trim();
    if (v != null && v.isNotEmpty) return v;
    return Platform.isIOS ? _testRewardedIdIos : _testRewardedIdAndroid;
  }

  /// Load + show rewarded ad. Returns true if user earned the reward
  /// (watched to completion). False on load fail / dismiss / show fail.
  Future<bool> showRewarded() async {
    if (!_initialized) await initialize();
    if (!_initialized) return false;

    final completer = Completer<bool>();
    void resolve(bool v) {
      if (!completer.isCompleted) completer.complete(v);
    }

    try {
      await RewardedAd.load(
        adUnitId: _rewardedUnitId(),
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            ad.fullScreenContentCallback = FullScreenContentCallback(
              onAdDismissedFullScreenContent: (ad) {
                ad.dispose();
                resolve(false);
              },
              onAdFailedToShowFullScreenContent: (ad, err) {
                debugPrint('[AdMob] show failed: $err');
                ad.dispose();
                resolve(false);
              },
            );
            ad.show(onUserEarnedReward: (ad, reward) {
              debugPrint('[AdMob] earned ${reward.amount} ${reward.type}');
              resolve(true);
            });
          },
          onAdFailedToLoad: (err) {
            debugPrint('[AdMob] load failed: $err');
            resolve(false);
          },
        ),
      );
    } catch (e) {
      debugPrint('[AdMob] showRewarded error: $e');
      resolve(false);
    }
    return completer.future;
  }
}
