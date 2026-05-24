import 'package:go_router/go_router.dart';

import 'package:facely/app.dart';
import 'package:facely/presentation/screens/home/report_page.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';

final router = GoRouter(
  initialLocation: '/main',
  routes: [
    GoRoute(
      path: '/main',
      builder: (ctx, state) => const MainApp(),
    ),
    GoRoute(
      path: '/report',
      builder: (ctx, state) => ReportPage(report: state.extra as FaceReadingReport),
    ),
  ],
);
