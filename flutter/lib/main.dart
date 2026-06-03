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
  // DSN 을 읽기 위해 dotenv 만 먼저 로드. 이후 모든 init·runApp 을 Sentry 로
  // 감싸 cold-start init 단계의 예외까지 포착한다. DSN 미설정이면 Sentry 는
  // no-op (앱 정상 동작).
  await dotenv.load(fileName: '.env');
  // 순수 Dart `sentry` 패키지 — 네이티브 Kotlin 모듈이 없어 build 충돌 없음.
  // appRunner 가 runZonedGuarded 로 비포착 async 에러를 자동 수집. Flutter
  // 프레임워크 에러는 아래 _bootstrapAndRun 에서 FlutterError.onError 로 연결.
  await Sentry.init(
    (options) {
      options.dsn = dotenv.maybeGet('SENTRY_DSN') ?? '';
      options.environment = kReleaseMode ? 'production' : 'debug';
      options.tracesSampleRate = kReleaseMode ? 0.2 : 1.0;
      // 얼굴 PII 가 흐르는 앱 — 기본 PII 자동수집 차단.
      options.sendDefaultPii = false;
    },
    appRunner: _bootstrapAndRun,
  );
}

Future<void> _bootstrapAndRun() async {
  // Flutter 프레임워크(build/layout/paint) 에러를 Sentry 로. 콘솔 출력도 유지.
  FlutterError.onError = (details) {
    Sentry.captureException(details.exception, stackTrace: details.stack);
    FlutterError.presentError(details);
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
  await CoinService().initialize();
  // AdMob — 광고 SDK warm-up. 실패해도 앱 launch 자체는 막지 않음 (서비스 내부에서 swallow).
  await AdMobService().initialize();
  await AuthService().initialize();
  // Warm up face-shape TFLite classifier; failure is non-fatal (falls back
  // to legacy LDA rule at call site).
  try {
    await FaceShapeClassifier.instance.load();
  } catch (_) {
    // intentionally swallowed — see classifier load() for logging
  }
  await AnalyticsService.instance.logAppOpen();
  // face.kr universal/app link → ReportPage 라우팅. cold start + warm 양쪽.
  // 라우팅 wire-up 은 share host 의 /api/decode 추가 후 마무리.
  await DeepLinkService.instance.initialize();
  runApp(const ProviderScope(child: MyApp()));
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
