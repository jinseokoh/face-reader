import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/app.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/domain/services/share/share_receive_service.dart';
import 'package:facely/presentation/screens/compatibility/compatibility_detail_screen.dart';
import 'package:facely/presentation/screens/home/info_confirm_screen.dart';
import 'package:facely/presentation/screens/home/report_page.dart';
import 'package:facely/presentation/screens/ledger/ledger_page.dart';
import 'package:facely/domain/models/capture_result.dart';
import 'package:facely/domain/models/face_metadata.dart';

/// 앱 전역 navigation router. 모든 screen 진입은 본 file 의 path 를 통해.
///
/// **Web path 와 통일**: deep link `https://facely.kr/r/{uuid}` 와 in-app
/// `/r/{uuid}` 가 같은 path 라 DeepLinkService 가 받은 URI 의 path 를 그대로
/// `context.push` 로 흘릴 수 있다.
///
/// **Tab 은 router 가 관여하지 않음** — `MainApp` 의 4-tab IndexedStack 은
/// Riverpod `selectedTabProvider` 가 관리 (keep-alive 보존이 핵심 UX). router
/// 는 push 되는 신규 screen 만 책임.
///
/// **Modal 은 router 외부** — `showModalBottomSheet` / `showDialog` 로 열리는
/// `FaceMeshPage`, `AlbumCapturePage` 등은 history stack 의미가 약해 router
/// 등록 안 함.
final router = GoRouter(
  initialLocation: '/main',
  // cold-start 시 GoRouter 가 플랫폼 딥링크(`/r/{uuid}`)를 자체 소비해 `/main`
  // 없이 ReportPage 로 직행 + DeepLinkService(app_links)도 push → 같은 화면 2장
  // (X 두 번 눌러야 main). 플랫폼 초기 location 을 무시하고 항상 `/main` 에서
  // 시작하게 해 share 라우팅을 DeepLinkService 단독 책임으로 통일.
  // (OAuth auth-callback 은 Supabase SDK 가 자체 처리하므로 영향 없음.)
  overridePlatformDefaultLocation: true,
  // OAuth deep link 가로채기 — Supabase SDK 가 `facely://auth-callback/?code=…`
  // 를 받아 session 교환을 이미 처리하지만, Flutter engine 은 같은 URI 를
  // GoRouter 에도 전달한다. router 에 매칭 라우트가 없으면 "Page Not Found" 가
  // 깜빡인다. 여기서 home 으로 흘려보내 깜빡임 제거.
  redirect: (ctx, state) {
    final loc = state.uri.toString();
    if (loc.contains('auth-callback')) return '/main';
    return null;
  },
  routes: [
    GoRoute(
      path: '/main',
      builder: (ctx, state) => const MainApp(),
      routes: [
        GoRoute(
          path: 'ledger', // → /main/ledger
          builder: (ctx, state) => const LedgerPage(),
        ),
      ],
    ),
    // Single-UUID = 관상, "{a}~{b}" = 궁합. SEP("~") 가 있으면 split.
    // Web 의 `/r/{id}` 와 path 동일. preloaded report 가 extra 로 오면 즉시
    // 렌더, 없으면 SupabaseService 로 fetch (received share 흐름).
    GoRoute(
      path: '/r/:id',
      builder: (ctx, state) => _buildShareDestination(state),
      routes: [
        GoRoute(
          // sub-action — Safari same-URL guard 회피용 web bridge.
          // 앱 안에선 부모 path 와 동일 destination (CTA 가 곧 deep link).
          path: 'open', // → /r/:id/open
          builder: (ctx, state) => _buildShareDestination(state),
        ),
      ],
    ),
    GoRoute(
      path: '/capture/confirm',
      builder: (ctx, state) => InfoConfirmScreen(
        capture: (state.extra! as CaptureExtras).capture,
        metadataFuture: (state.extra! as CaptureExtras).metadataFuture,
        asMyFace: (state.extra! as CaptureExtras).asMyFace,
      ),
    ),
  ],
);

/// `/r/:id` builder — id 안에 SEP("~") 가 있으면 궁합, 없으면 관상.
/// extra 가 pre-loaded report (또는 두 report) 면 즉시 push, 아니면 fetch.
Widget _buildShareDestination(GoRouterState state) {
  final id = state.pathParameters['id']!;
  if (id.contains('~')) {
    final parts = id.split('~');
    if (parts.length != 2) return const _ShareErrorScreen();
    final extra = state.extra;
    if (extra is _CompatExtras) {
      return CompatibilityDetailScreen(my: extra.my, album: extra.album);
    }
    return _CompatRouteWrapper(uuidA: parts[0], uuidB: parts[1]);
  }
  final preloaded = state.extra is FaceReadingReport
      ? state.extra as FaceReadingReport
      : null;
  return _ReportRouteWrapper(uuid: id, preloaded: preloaded);
}

/// 캡처 흐름 → InfoConfirmScreen 으로 넘기는 인자 묶음.
/// router 의 `extra` 는 한 객체만 받으므로 wrapper.
/// [asMyFace] — 홈 [내 관상 만들기] 경로. 분석 완료 즉시 내 관상으로 등록.
class CaptureExtras {
  final CaptureResult capture;
  final Future<FaceMetadata?>? metadataFuture;
  final bool asMyFace;
  const CaptureExtras({
    required this.capture,
    this.metadataFuture,
    this.asMyFace = false,
  });
}

/// 궁합 push 시 두 report 를 동시에 넘기는 wrapper.
class _CompatExtras {
  final FaceReadingReport my;
  final FaceReadingReport album;
  const _CompatExtras({required this.my, required this.album});
}

/// in-app push 의 편의 helper — 두 report 를 넘긴다.
extension CompatPushExtension on BuildContext {
  void pushCompat({
    required FaceReadingReport my,
    required FaceReadingReport album,
    String? supabaseIdA,
    String? supabaseIdB,
  }) {
    final a = supabaseIdA ?? my.supabaseId;
    final b = supabaseIdB ?? album.supabaseId;
    if (a == null || b == null) {
      // fallback — supabaseId 없으면 in-process push (router 우회).
      Navigator.of(this).push(
        MaterialPageRoute(
          builder: (_) => CompatibilityDetailScreen(my: my, album: album),
        ),
      );
      return;
    }
    push('/r/$a~$b', extra: _CompatExtras(my: my, album: album));
  }

  /// pushCompat 의 `go` 버전 — 상세를 최상위 라우트로 띄워 (스택을 접어) 닫을 때
  /// `/main` 으로 빠지게 한다. 받은 카드에서 궁합 탭으로 전환 후 상세를 열 때
  /// 사용 — 닫으면 받은 카드가 아니라 궁합 탭으로 복귀.
  void goCompat({
    required FaceReadingReport my,
    required FaceReadingReport album,
  }) {
    final a = my.supabaseId;
    final b = album.supabaseId;
    if (a == null || b == null) {
      Navigator.of(this).push(
        MaterialPageRoute(
          builder: (_) => CompatibilityDetailScreen(my: my, album: album),
        ),
      );
      return;
    }
    go('/r/$a~$b', extra: _CompatExtras(my: my, album: album));
  }
}

/// 관상 deep-link wrapper — preloaded null 이면 Supabase 에서 fetch.
/// 공유 링크 열람만으로 history 에 자동 저장하지 않는다 (주체적 추가 정책).
class _ReportRouteWrapper extends StatefulWidget {
  final String uuid;
  final FaceReadingReport? preloaded;
  const _ReportRouteWrapper({required this.uuid, this.preloaded});

  @override
  State<_ReportRouteWrapper> createState() => _ReportRouteWrapperState();
}

class _ReportRouteWrapperState extends State<_ReportRouteWrapper> {
  late final Future<FaceReadingReport?> _future;

  @override
  void initState() {
    super.initState();
    final preloaded = widget.preloaded;
    _future = preloaded != null
        ? Future.value(preloaded)
        : ShareReceiveService().fetchByUuid(widget.uuid);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FaceReadingReport?>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        final report = snap.data;
        if (report == null) return const _ShareErrorScreen();
        return ReportPage(report: report);
      },
    );
  }
}

/// 궁합 deep-link wrapper — 두 UUID 모두 fetch.
class _CompatRouteWrapper extends StatefulWidget {
  final String uuidA;
  final String uuidB;
  const _CompatRouteWrapper({required this.uuidA, required this.uuidB});

  @override
  State<_CompatRouteWrapper> createState() => _CompatRouteWrapperState();
}

class _CompatRouteWrapperState extends State<_CompatRouteWrapper> {
  late final Future<List<FaceReadingReport?>> _future;

  @override
  void initState() {
    super.initState();
    final svc = ShareReceiveService();
    _future = Future.wait([
      svc.fetchByUuid(widget.uuidA),
      svc.fetchByUuid(widget.uuidB),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FaceReadingReport?>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        final my = snap.data?[0];
        final album = snap.data?[1];
        if (my == null || album == null) return const _ShareErrorScreen();
        return CompatibilityDetailScreen(my: my, album: album);
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.white,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ShareErrorScreen extends StatelessWidget {
  const _ShareErrorScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('공유 카드')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.huge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FaIcon(FontAwesomeIcons.faceFrown,
                  size: 56, color: AppColors.border),
              const SizedBox(height: AppSpacing.lg),
              Text(
                '카드를 찾을 수 없어요',
                style: AppText.sectionTitle.copyWith(
                  fontWeight: FontWeight.w400,
                  color: AppColors.textHint,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                '만료됐거나 link 가 잘못됐어요',
                style: AppText.hint,
              ),
              const SizedBox(height: AppSpacing.xl),
              TextButton(
                onPressed: () => context.go('/main'),
                child: const Text('홈으로'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
