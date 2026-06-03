import 'dart:async';

import 'package:facely/config/router.dart';
import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/admob_service.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/coin_service.dart';
import 'package:facely/data/services/deep_link_service.dart';
import 'package:facely/data/services/face_shape_classifier.dart';
import 'package:facely/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:sentry/sentry.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // DSN 을 읽기 위해 dotenv 먼저 로드. DSN 미설정이면 Sentry 는 no-op.
  await dotenv.load(fileName: '.env');
  // 순수 Dart `sentry` — 네이티브 Kotlin 모듈 없어 build 충돌 없음.
  // appRunner(runZonedGuarded) 는 binding init zone 과 runApp zone 을 어긋나게
  // 해 "Zone mismatch" 를 유발하므로 쓰지 않는다. 대신 모든 init·runApp 을 한
  // zone(root) 에 두고, 비포착 에러는 아래 두 핸들러로 Sentry 에 보낸다.
  await Sentry.init((options) {
    options.dsn = dotenv.maybeGet('SENTRY_DSN') ?? '';
    options.environment = kReleaseMode ? 'production' : 'debug';
    options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
    // 얼굴 PII 가 흐르는 앱 — 기본 PII 자동수집 차단.
    options.sendDefaultPii = false;
  });
  // Flutter 프레임워크(build/layout/paint) 에러 → Sentry. 콘솔 출력도 유지.
  FlutterError.onError = (details) {
    Sentry.captureException(details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
  };
  // 비포착 async/platform 에러 → Sentry (Flutter 3.3+ 권장, runZonedGuarded 대체).
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    Sentry.captureException(error, stackTrace: stack);
    return true;
  };
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  KakaoSdk.init(nativeAppKey: dotenv.env['KAKAO_NATIVE_APP_KEY']!);
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );
  await initHive();
  await ThumbnailPaths.initCache();
  await AuthService().initialize();
  // 딥링크 pending 은 runApp 전에 준비돼야 MainApp initState 가 회수 가능.
  await DeepLinkService.instance.initialize();
  // 무거운 비핵심 init(TFLite 분류기·AdMob·RevenueCat·analytics)은 첫 프레임을
  // 막지 않도록 runApp 이후 백그라운드로 워밍업 — cold-start 흰 화면(3~4초) 단축.
  // 받은 카드/홈 첫 화면은 이들에 의존하지 않고, 분석·광고·결제는 사용 시점까지
  // 시간이 충분하다. 각 서비스는 내부적으로 실패를 swallow.
  _warmUpNonCritical();
  runApp(const ProviderScope(child: MyApp()));
}

/// 첫 프레임 이후 백그라운드로 워밍업하는 비핵심 서비스들. 모두 fire-and-forget
/// 이며 실패해도 무시 (필요 시점에 각 호출부가 재시도/fallback).
void _warmUpNonCritical() {
  unawaited(CoinService().initialize().catchError((Object _) {}));
  unawaited(AdMobService().initialize().catchError((Object _) {}));
  // face-shape TFLite — 분석 시점에만 필요. 실패 시 호출부가 legacy LDA fallback.
  unawaited(FaceShapeClassifier.instance.load().catchError((Object _) {}));
  unawaited(AnalyticsService.instance.logAppOpen().catchError((Object _) {}));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: '관상은 과학이다',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: router,
    );
  }
}
