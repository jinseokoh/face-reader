import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/services/auth_service.dart';
import 'package:face_reader/data/services/deep_link_service.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:face_reader/presentation/screens/compatibility/compatibility_detail_screen.dart';
import 'package:face_reader/presentation/screens/compatibility/compatibility_screen.dart';
import 'package:face_reader/presentation/screens/home/home_screen.dart';
import 'package:face_reader/presentation/screens/home/report_page.dart';
import 'package:face_reader/presentation/screens/physiognomy/physiognomy_screen.dart';
import 'package:face_reader/presentation/screens/settings/settings_screen.dart';

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  StreamSubscription<void>? _bonusSkippedSub;
  StreamSubscription<ShareLink>? _shareLinkSub;

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

  Future<void> _handleShareLink(ShareLink link) async {
    debugPrint('[ShareLink] handling $link');
    switch (link) {
      case SoloShareLink(:final uuid):
        final report = await _fetchReport(uuid);
        if (report == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReportPage(report: report)),
        );
      case CompatShareLink(:final uuidA, :final uuidB):
        final both = await Future.wait([
          _fetchReport(uuidA),
          _fetchReport(uuidB),
        ]);
        final my = both[0];
        final album = both[1];
        if (my == null || album == null || !mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompatibilityDetailScreen(my: my, album: album),
          ),
        );
    }
  }

  Future<FaceReadingReport?> _fetchReport(String uuid) async {
    try {
      final row = await SupabaseService().getMetrics(uuid);
      if (row == null) {
        _showSnack('카드를 찾을 수 없어요');
        return null;
      }
      final raw = row['body'];
      // jsonb / text 어느 쪽으로 돌아와도 fromJsonString 이 string 만 받으므로 정규화.
      final jsonStr = raw is String ? raw : raw?.toString();
      if (jsonStr == null || jsonStr.isEmpty) {
        _showSnack('카드 데이터가 비어있어요');
        return null;
      }
      return FaceReadingReport.fromJsonString(jsonStr);
    } catch (e, st) {
      debugPrint('[ShareLink] fetch fail uuid=$uuid: $e\n$st');
      _showSnack('카드를 불러오지 못했어요');
      return null;
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
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
      body: IndexedStack(
        index: selectedIndex,
        children: const [
          HomeScreen(),
          PhysiognomyScreen(),
          CompatibilityScreen(),
          SettingsScreen(),
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
