import 'package:face_reader/app.dart';
import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/data/services/analytics_service.dart';
import 'package:face_reader/data/services/auth_service.dart';
import 'package:face_reader/data/services/coin_service.dart';
import 'package:face_reader/data/services/deep_link_service.dart';
import 'package:face_reader/data/services/face_shape_classifier.dart';
import 'package:face_reader/core/theme.dart';
import 'package:face_reader/firebase_options.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  timeago.setLocaleMessages('ko', timeago.KoMessages());
  await dotenv.load(fileName: '.env');
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
  await CoinService().initialize();
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
    return MaterialApp(
      title: 'AI 관상가',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const MainApp(),
    );
  }
}
