import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/services/auth_service.dart';
import 'package:face_reader/presentation/providers/tab_provider.dart';
import 'package:face_reader/presentation/screens/home/home_screen.dart';
import 'package:face_reader/presentation/screens/compatibility/compatibility_screen.dart';
import 'package:face_reader/presentation/screens/physiognomy/physiognomy_screen.dart';
import 'package:face_reader/presentation/screens/settings/settings_screen.dart';

class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  StreamSubscription<void>? _bonusSkippedSub;

  @override
  void initState() {
    super.initState();
    _bonusSkippedSub =
        AuthService().signupBonusSkippedNotice.listen((_) {
      if (!mounted) return;
      _showBonusSkippedDialog();
    });
  }

  @override
  void dispose() {
    _bonusSkippedSub?.cancel();
    super.dispose();
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
            fontFamily: 'SongMyung',
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        content: const Text(
          '보너스 코인은 이미 지급했었기 때문에 더이상 지급되지 않습니다.',
          style: TextStyle(
            fontFamily: 'SongMyung',
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
            icon: Icon(Icons.home),
            label: '홈',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.face_retouching_natural),
            label: '관상',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: '궁합',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
