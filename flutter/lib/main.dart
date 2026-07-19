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
import 'package:facely/data/services/push_service.dart';
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
  // native splash 는 백지(흰색) placeholder — 즉시 runApp 으로 in-app 스플래시
  // (수묵화 + 타이틀) 전환. 무거운 init 은 BootstrapApp 이 스플래시를 그리는
  // 동안 진행하고, 끝나는 즉시 MyApp 으로 교체 — 인위적 지연 0초.
  runApp(const BootstrapApp());
}

/// 앱 구동에 필수인 서비스 init — in-app 스플래시가 떠 있는 동안 실행된다.
/// 실측 0.5~1초 (Firebase/Supabase/Hive/Auth/DeepLink).
Future<void> _bootstrap() async {
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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
  // 딥링크 pending 은 MainApp build 이전에 준비돼야 initState 가 회수 가능 —
  // bootstrap 완료 후에만 MyApp(router→MainApp) 이 빌드되므로 보장된다.
  await DeepLinkService.instance.initialize();
  // 무거운 비핵심 init(TFLite 분류기·AdMob·RevenueCat·analytics)은 첫 프레임을
  // 막지 않도록 백그라운드로 워밍업 — cold-start 흰 화면 단축.
  // 받은 카드/홈 첫 화면은 이들에 의존하지 않고, 분석·광고·결제는 사용 시점까지
  // 시간이 충분하다. 각 서비스는 내부적으로 실패를 swallow.
  _warmUpNonCritical();
}

/// 첫 프레임 이후 백그라운드로 워밍업하는 비핵심 서비스들. 모두 fire-and-forget
/// 이며 실패해도 무시 (필요 시점에 각 호출부가 재시도/fallback).
void _warmUpNonCritical() {
  unawaited(CoinService().initialize().catchError((Object _) {}));
  unawaited(AdMobService().initialize().catchError((Object _) {}));
  // face-shape TFLite — 분석 시점에만 필요. 실패 시 호출부가 legacy LDA fallback.
  unawaited(FaceShapeClassifier.instance.load().catchError((Object _) {}));
  unawaited(AnalyticsService.instance.logAppOpen().catchError((Object _) {}));
  // 매칭 응답 푸시 — token 등록 + 수신 배선. 권한 거부·실패 무시.
  unawaited(PushService.instance.initialize().catchError((Object _) {}));
}

/// 부팅 게이트 — [_bootstrap] 진행 동안 수묵화 + 타이틀 스플래시를 그리고,
/// 완료 즉시 [MyApp] 으로 교체한다. 스플래시는 부팅 시간만 사용 (지연 0초).
class BootstrapApp extends StatefulWidget {
  const BootstrapApp({super.key});

  @override
  State<BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<BootstrapApp> {
  late Future<void> _future = _bootstrap();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.done && !snap.hasError) {
          return const ProviderScope(child: MyApp());
        }
        return MaterialApp(
          title: '관상은 과학이다',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: _BootSplash(
            error: snap.hasError,
            onRetry: () => setState(() => _future = _bootstrap()),
          ),
        );
      },
    );
  }
}

/// in-app 스플래시 — 구 홈의 수묵화 일러스트 + "관상은 과학이다." 타이틀이
/// 이주해 온 자리 (PIVOT A5 스플래시 스펙).
class _BootSplash extends StatelessWidget {
  final bool error;
  final VoidCallback onRetry;

  const _BootSplash({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.height < 720;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/banner.png',
                height: compact ? 220 : 280,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: AppSpacing.huge),
              Text(
                '관상은 과학이다.',
                style: AppText.display.copyWith(
                  fontSize: compact ? 30 : 36,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                '안면 계측 데이터 기반 인공지능 관상앱',
                style: AppText.body.copyWith(
                  color: AppTheme.textSecondary,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              if (error) ...[
                const SizedBox(height: AppSpacing.xl),
                Text(
                  '시작 중 문제가 발생했어요',
                  style: AppText.body.copyWith(color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton(onPressed: onRetry, child: const Text('다시 시도')),
              ],
            ],
          ),
        ),
      ),
    );
  }
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
