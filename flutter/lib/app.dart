import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/core/theme.dart';
import 'package:facely/data/services/app_config_service.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/deep_link_service.dart';
import 'package:facely/domain/models/team.dart';
import 'package:facely/presentation/providers/team_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';
import 'package:facely/presentation/providers/tab_provider.dart';
import 'package:facely/presentation/screens/chat/chat_tab_screen.dart';
import 'package:facely/presentation/screens/compatibility/compatibility_screen.dart';
import 'package:facely/presentation/screens/chemistry/chemistry_screen.dart';
import 'package:facely/presentation/screens/physiognomy/physiognomy_screen.dart';
import 'package:facely/presentation/screens/settings/settings_screen.dart';
import 'package:facely/presentation/screens/update_gate_screen.dart';
import 'package:facely/presentation/widgets/ad_banner_dialog.dart';
import 'package:facely/presentation/widgets/onboarding_intro.dart';

/// 탭 화면 5개. 순서 = 인원수 위계: 1인 관상 → 2인 궁합 → 다인 교감 →
/// 그 결과물인 채팅 → 설정.
const List<Widget> _kTabScreens = [
  PhysiognomyScreen(),
  CompatibilityScreen(),
  ChemistryScreen(),
  ChatTabScreen(),
  SettingsScreen(),
];

/// 온보딩을 띄우기 전에 원격 설정 응답을 기다려 주는 최대 시간.
/// 첫 프레임 뒤에 뜨는 모달이라 이 정도 지연은 눈에 띄지 않는다.
const Duration _kRemoteConfigWait = Duration(milliseconds: 500);

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
    // 강제 업그레이드 게이트 — min_build 미달이면 닫을 수 없는 화면으로
    // 전부 덮는다 (딥링크 cold-start 도 MainApp 이 먼저 mount 되므로 관통).
    // 조회 자체는 부팅 중에 이미 시작됐다 (`main.dart` 의 `_bootstrap`) —
    // 여기서는 그 결과를 받아 쓴다.
    AppConfigService.instance.checkForceUpdate().then((r) {
      if (!mounted || !r.required) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => UpdateGateScreen(notice: r.notice),
        ),
      );
    });
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
    } else {
      // 온보딩 인트로 — 내 관상 등록 전까지 매 실행 노출 ("다시 보지 않기"만
      // 노출을 끈다). 공유 링크 cold-start 면 이번 실행은 양보.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _maybeShowOnboarding());
    }
  }

  Future<void> _maybeShowOnboarding() async {
    if (!mounted) return;
    final prefs = Hive.box<String>(HiveBoxes.prefs);
    if (prefs.get(kOnboardingNeverAgainKey) != null) return;
    // 내 관상이 등록돼 있으면 온보딩의 목적이 끝난 것 — 노출 종료.
    if (ref.read(historyProvider).any((r) => r.isMyFace)) return;
    // 온보딩 첫 장의 제목·이미지는 원격 코퍼스 버전에 따라 갈린다. 조회는
    // 부팅 중에 시작되지만 아직 안 왔을 수 있어 잠깐만 기다린다 — 넘기면
    // 그냥 띄운다 (온보딩을 네트워크에 인질로 잡지 않는다).
    await AppConfigService.instance.ready
        .timeout(_kRemoteConfigWait, onTimeout: () {});
    if (!mounted) return;
    final result = await showOnboardingIntro(context);
    if (!mounted) return;
    switch (result) {
      case OnboardingIntroResult.neverAgain:
        await prefs.put(kOnboardingNeverAgainKey, '1');
      case OnboardingIntroResult.later:
        break;
    }
    if (!mounted) return;
    // 온보딩을 보는 동안 딥링크 등으로 탭이 옮겨졌을 수 있어 케미로 되돌린다.
    // 시작 탭 자체는 `kInitialTabIndex` 가 정한다 — 온보딩은 "다시 보지 않기"
    // 를 눌렀거나 내 관상이 등록된 사용자에게는 뜨지 않으므로, 여기에만 두면
    // 그 조건에 가려진다.
    ref.read(selectedTabProvider.notifier).selectTab(kInitialTabIndex);
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
      TeamJoinShareLink(:final teamId) => '/g/$teamId',
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

  /// 채팅 탭의 IndexedStack index — 뱃지·밴드·탭 전환이 공유.
  static const _chatTabIndex = 3;

  /// 설정 탭 index — 진입 시 배너 광고 팝업 트리거.
  static const _settingsTabIndex = 4;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = ref.watch(selectedTabProvider);
    // 안읽음 뱃지·새 메시지 밴드 — 로드 전/실패 시엔 없는 것으로 취급.
    final chats =
        ref.watch(openChatsProvider).asData?.value ?? const <OpenChat>[];
    final unread = [for (final c in chats) if (c.hasUnread) c];

    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: selectedIndex,
              children: [
                // IndexedStack 은 보이지 않는 탭도 전부 build 한다. TickerMode
                // 로 감싸지 않으면 그 탭의 애니메이션이 사용자가 탭을 열기도
                // 전에 흘러가 끝나 버린다 (관상 빈 화면의 크레딧이 그 예).
                // 선택된 탭에서만 ticker 를 돌려 "화면이 보이는 순간" 부터
                // 애니메이션이 시작되게 한다.
                for (var i = 0; i < _kTabScreens.length; i++)
                  TickerMode(
                    enabled: i == selectedIndex,
                    child: _kTabScreens[i],
                  ),
              ],
            ),
          ),
          // 새 메시지 밴드 — 어느 탭에서든 바텀 탭바 위 같은 자리.
          // 채팅 탭에선 목록이 이미 보이므로 숨김.
          if (unread.isNotEmpty && selectedIndex != _chatTabIndex)
            _UnreadChatBand(
              unread: unread,
              onTap: () => _openUnread(unread),
            ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedIndex,
        onTap: _onTabSelected,
        backgroundColor: Colors.white,
        selectedItemColor: AppTheme.textPrimary,
        unselectedItemColor: AppTheme.textHint,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
        items: [
          const BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.person, size: 22),
            label: '관상',
          ),
          const BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.peoplePulling, size: 22),
            label: '궁합',
          ),
          const BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.peopleGroup, size: 22),
            label: '케미',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const FaIcon(FontAwesomeIcons.solidComment, size: 22),
                if (unread.isNotEmpty)
                  Positioned(
                    top: -2,
                    right: -4,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            label: '채팅',
          ),
          const BottomNavigationBarItem(
            icon: FaIcon(FontAwesomeIcons.gears, size: 22),
            label: '설정',
          ),
        ],
      ),
    );
  }

  void _onTabSelected(int i) {
    // 채팅 탭 진입마다 목록·안읽음 상태 재조회 (Realtime 미구독 보완).
    if (i == _chatTabIndex) ref.invalidate(openChatsProvider);
    // 설정 탭 진입 시 배너 광고 팝업 — 배너별 세션 1회·영구 제외 규칙은
    // AdBannerDialog 가 판정.
    if (i == _settingsTabIndex) AdBannerDialog.maybeShow(context);
    ref.read(selectedTabProvider.notifier).selectTab(i);
  }

  Future<void> _openUnread(List<OpenChat> unread) async {
    if (unread.length == 1) {
      await context.push('/chat/${unread.first.teamId}');
      if (mounted) ref.invalidate(openChatsProvider);
      return;
    }
    ref.invalidate(openChatsProvider);
    ref.read(selectedTabProvider.notifier).selectTab(_chatTabIndex);
  }
}

/// 전역 새 메시지 밴드 — 미니플레이어 패턴. 안읽은 채팅이 있을 때만 뜨고,
/// 탭하면 해당 채팅방(1개) 또는 채팅 탭(여러 개)으로 보낸다.
class _UnreadChatBand extends StatelessWidget {
  final List<OpenChat> unread;
  final VoidCallback onTap;
  const _UnreadChatBand({required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final first = unread.first;
    final preview = first.lastMessage?.body ?? '';
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.border)),
          ),
          child: Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.solidComment,
                size: 18,
                color: AppTheme.textPrimary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('새 메시지 ${unread.length}개', style: AppText.subTitle),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${first.otherNickname}: $preview',
                      style: AppText.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const FaIcon(
                FontAwesomeIcons.chevronRight,
                size: 14,
                color: AppTheme.textHint,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
