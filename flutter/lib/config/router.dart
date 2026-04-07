import 'package:go_router/go_router.dart';

import 'package:face_reader/app.dart';
import 'package:face_reader/presentation/screens/home/report_page.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';

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
