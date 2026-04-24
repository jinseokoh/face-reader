import 'package:face_reader/core/theme.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/screens/wallet/wallet_page.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
import 'package:face_reader/presentation/widgets/purchase_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final isLoggedIn = user != null;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('설정'),
        actions: [
          IconButton(
            tooltip: '지갑',
            icon: const Icon(Icons.account_balance_wallet_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const WalletPage()),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (isLoggedIn)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  // User row
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.white,
                        backgroundImage: user.profileImageUrl != null
                            ? NetworkImage(user.profileImageUrl!)
                            : null,
                        child: user.profileImageUrl == null
                            ? Icon(Icons.person, color: AppTheme.textHint)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(user.nickname ?? '사용자',
                                style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text('카카오 계정으로 로그인됨',
                                style: TextStyle(
                                    color: AppTheme.textHint, fontSize: 13)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () async {
                          await ref.read(authProvider.notifier).logout();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('로그아웃되었습니다')),
                            );
                          }
                        },
                        child: Text('로그아웃',
                            style: TextStyle(
                                color: AppTheme.textHint, fontSize: 13)),
                      ),
                    ],
                  ),
                  Divider(color: AppTheme.border, height: 24),
                  // Coin row
                  Row(
                    children: [
                      Icon(Icons.toll_outlined,
                          color: AppTheme.textSecondary, size: 28),
                      const SizedBox(width: 12),
                      Text('남은 코인',
                          style: TextStyle(
                              color: AppTheme.textPrimary, fontSize: 15)),
                      const SizedBox(width: 8),
                      Text(
                        '${user.coins}개',
                        style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showPurchaseSheet(context, ref),
                        child: Text('충전하기',
                            style: TextStyle(
                                color: AppTheme.textHint, fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                children: [
                  // Login button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: () => showLoginBottomSheet(context, ref),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFEE500),
                        foregroundColor: const Color(0xFF3C1E1E),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('카카오로 로그인',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  // 로그인 전엔 "남은 코인 --" 표시 안 함 (로그인 후에만 의미 있음)
                ],
              ),
            ),
          const SizedBox(height: 24),

          _menuItem(
            icon: Icons.description_outlined,
            title: '이용약관 보기',
            onTap: () {},
          ),
          _menuItem(
            icon: Icons.shield_outlined,
            title: '개인정보 약관 보기',
            onTap: () {},
          ),
          if (isLoggedIn) ...[
            _menuItem(
              icon: Icons.person_remove_outlined,
              title: '회원 탈퇴',
              onTap: () {},
            ),
          ],
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.hasData
                  ? '${snapshot.data!.version}+${snapshot.data!.buildNumber}'
                  : '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppTheme.surface,
                  borderRadius: BorderRadius.circular(14),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: AppTheme.textSecondary, size: 24),
                        const SizedBox(width: 16),
                        Text('앱 정보',
                            style: TextStyle(
                                color: AppTheme.textPrimary, fontSize: 15)),
                        const Spacer(),
                        Text(version,
                            style: TextStyle(
                                color: AppTheme.textHint, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _menuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Icon(icon, color: AppTheme.textSecondary, size: 24),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: TextStyle(
                              color: titleColor ?? AppTheme.textPrimary,
                              fontSize: 15)),
                      if (subtitle != null)
                        Text(subtitle,
                            style: TextStyle(
                                color: AppTheme.textHint, fontSize: 13)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.textHint),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPurchaseSheet(BuildContext context, WidgetRef ref) {
    PurchaseSheet.show(context);
  }
}
