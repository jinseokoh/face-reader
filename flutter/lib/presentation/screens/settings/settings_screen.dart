import 'package:facely/core/theme.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/widgets/account_deletion_dialog.dart';
import 'package:facely/presentation/widgets/legal_doc_sheet.dart';
import 'package:facely/presentation/widgets/login_entry_button.dart';
import 'package:facely/presentation/widgets/purchase_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:go_router/go_router.dart';
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
            tooltip: '코인 사용내역',
            icon: const FaIcon(FontAwesomeIcons.receipt, size: 20),
            onPressed: () => context.push('/main/ledger'),
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
                            ? FaIcon(FontAwesomeIcons.user, color: AppTheme.textHint, size: 22)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(user.nickname ?? '사용자',
                                      style: AppText.sectionTitle,
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 8),
                                // 카카오 로그인이 준 기본 이름 수정 진입점.
                                GestureDetector(
                                  onTap: () => _showNicknameDialog(
                                      context, ref, user.nickname ?? ''),
                                  child: FaIcon(FontAwesomeIcons.pen,
                                      size: 12, color: AppTheme.textHint),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                                switch (user.provider) {
                                  'kakao' => '카카오 계정으로 로그인됨',
                                  'email' => '이메일 계정으로 로그인됨',
                                  'google' => '구글 계정으로 로그인됨',
                                  _ => '로그인됨',
                                },
                                style: AppText.caption
                                    .copyWith(color: AppColors.textHint)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _confirmLogout(context, ref),
                        child: Text('로그아웃',
                            style: AppText.caption
                                .copyWith(color: AppColors.textHint)),
                      ),
                    ],
                  ),
                  Divider(color: AppTheme.border, height: 24),
                  // Coin row
                  Row(
                    children: [
                      FaIcon(FontAwesomeIcons.coins,
                          color: AppTheme.textSecondary, size: 22),
                      const SizedBox(width: 12),
                      Text('남은 코인',
                          style: AppText.body
                              .copyWith(color: AppColors.textPrimary)),
                      const SizedBox(width: 8),
                      Text(
                        '${user.coins}개',
                        style: AppText.sectionTitle,
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => _showPurchaseSheet(context, ref),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.background,
                            border: Border.all(color: AppColors.textPrimary),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text('충전하기',
                              style: AppText.caption.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          else
            const LoginEntryButton(),
          const SizedBox(height: 24),

          _menuItem(
            icon: FontAwesomeIcons.fileLines,
            title: '이용약관 보기',
            onTap: () => LegalDocSheet.showTerms(context, ref),
          ),
          _menuItem(
            icon: FontAwesomeIcons.shieldHalved,
            title: '개인정보 약관 보기',
            onTap: () => LegalDocSheet.showPrivacy(context, ref),
          ),
          if (isLoggedIn) ...[
            _menuItem(
              icon: FontAwesomeIcons.userXmark,
              title: '회원 탈퇴',
              onTap: () => AccountDeletionDialog.show(context, ref),
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
                        FaIcon(FontAwesomeIcons.circleInfo, color: AppTheme.textSecondary, size: 20),
                        const SizedBox(width: 16),
                        Text('앱 정보',
                            style: AppText.body
                                .copyWith(color: AppColors.textPrimary)),
                        const Spacer(),
                        Text(version,
                            style: AppText.caption
                                .copyWith(color: AppColors.textHint)),
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
    required FaIconData icon,
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
                FaIcon(icon, color: AppTheme.textSecondary, size: 20),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: AppText.body.copyWith(
                              color: titleColor ?? AppColors.textPrimary)),
                      if (subtitle != null)
                        Text(subtitle,
                            style: AppText.caption
                                .copyWith(color: AppColors.textHint)),
                    ],
                  ),
                ),
                FaIcon(FontAwesomeIcons.chevronRight, color: AppTheme.textHint, size: 14),
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

  /// 프로필 이름 변경 — 관상 탭 '이름 변경' 다이얼로그와 동일 레시피.
  void _showNicknameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) {
    final controller = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('이름 변경', style: AppText.modalTitle),
        content: TextField(
          controller: controller,
          maxLength: 64,
          autofocus: true,
          decoration: const InputDecoration(hintText: '이름을 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              '취소',
              style: AppText.body.copyWith(color: AppColors.textHint),
            ),
          ),
          TextButton(
            onPressed: () async {
              final name = controller.text.trim();
              Navigator.pop(ctx);
              if (name.isEmpty || name == currentName) return;
              final ok = await ref
                  .read(authProvider.notifier)
                  .updateNickname(name);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('이름 변경에 실패했습니다')),
                );
              }
            },
            child: Text(
              '저장',
              style: AppText.body.copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        title: const Text('로그아웃 하시겠습니까?', style: AppText.modalTitle),
        content: const Text(
          '로그아웃하면 코인 잔액과 개인 정보에 접근할 수 없습니다.',
          style: AppText.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소',
                style: TextStyle(color: AppColors.textHint)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('로그아웃되었습니다')),
                );
              }
            },
            child: const Text('로그아웃',
                style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
  }
}
