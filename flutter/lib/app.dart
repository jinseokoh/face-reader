import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/deep_link_service.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/screens/compatibility/compatibility_screen.dart';
import 'package:facely/presentation/screens/home/home_screen.dart';
import 'package:facely/presentation/screens/physiognomy/physiognomy_screen.dart';
import 'package:facely/presentation/screens/settings/settings_screen.dart';
import 'package:facely/presentation/widgets/my_face_nudge_banner.dart';

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  StreamSubscription<void>? _bonusSkippedSub;
  StreamSubscription<ShareLink>? _shareLinkSub;

  // cold-start 시 getInitialLink + uriLinkStream 이중 전달 / pending+stream 겹침으로
  // 같은 화면이 2번 push 되는 것 방지용 dedup.
  String? _lastSharePath;
  DateTime _lastShareAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _bonusSkippedSub =
        AuthService().signupBonusSkippedNotice.listen((_) {
      if (!mounted) return;
      _showBonusSkippedDialog();
    });
    _shareLinkSub = DeepLinkService.instance.shareLinkStream.listen((link) {
      if (!mounted) return;
      _handleShareLink(link);
    });
    // cold-start 시 DeepLinkService 가 MainApp build 이전에 이미 emit 했을 수 있음.
    final pending = DeepLinkService.instance.pendingLink;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        DeepLinkService.instance.consumePending();
        _handleShareLink(pending);
      });
    }
  }

  @override
  void dispose() {
    _bonusSkippedSub?.cancel();
    _shareLinkSub?.cancel();
    super.dispose();
  }

  void _handleShareLink(ShareLink link) {
    debugPrint('[ShareLink] handling $link');
    if (!mounted) return;
    // router 의 `/r/:id` wrapper 가 Supabase fetch + error UI 까지 책임. 여기선
    // path 만 조립해서 push — fetch latency 동안 wrapper 가 loading shell.
    final path = switch (link) {
      SoloShareLink(:final uuid) => '/r/$uuid',
      CompatShareLink(:final uuidA, :final uuidB) => '/r/$uuidA~$uuidB',
    };
    // 동일 link 이중 전달 무시 (2초 내 같은 path) → 화면 1장만.
    final now = DateTime.now();
    if (path == _lastSharePath &&
        now.difference(_lastShareAt) < const Duration(seconds: 2)) {
      debugPrint('[ShareLink] dup ignored: $path');
      return;
    }
    _lastSharePath = path;
    _lastShareAt = now;
    // 최종 방어: 이미 같은 share 라우트가 최상단이면 push 금지. cold-start 의
    // GoRouter native nav / app_links 이중 전달 등 소스·타이밍과 무관하게 중복
    // ReportPage 를 차단 (2초 window 를 벗어난 재전달도 커버).
    final currentUri = GoRouter.of(context).state.uri.toString();
    if (currentUri == path) {
      debugPrint('[ShareLink] already on $path, skip duplicate push');
      return;
    }
    context.push(path);
  }

  Future<void> _showBonusSkippedDialog() async {
    // Wait one frame so any in-flight modal sheet (login bottom sheet) has
    // popped before we surface the alert — otherwise the dialog can fight
    // the bottom sheet's dismissal animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '가입 보너스 안내',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: const Text(
          '보너스 코인은 이미 지급했었기 때문에 더이상 지급되지 않습니다.',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w400,
            color: AppTheme.textSecondary,
            height: 1.7,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              '확인',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedTabProvider);

    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: selectedIndex,
            children: const [
              HomeScreen(),
              PhysiognomyScreen(),
              CompatibilityScreen(),
              SettingsScreen(),
            ],
          ),
          // 내 관상 미설정 nudge — 홈/관상/궁합 탭 상단에 슬라이드-다운 오버레이.
          const Align(
            alignment: Alignment.topCenter,
            child: MyFaceNudgeBanner(),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: (i) => ref.read(selectedTabProvider.notifier).selectTab(i),
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.textPrimary,
        unselectedItemColor: AppTheme.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.house, size: 22),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.eye, size: 22),
            label: '관상',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.handshake, size: 22),
            label: '궁합',
          ),
          BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.userGear, size: 22),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
