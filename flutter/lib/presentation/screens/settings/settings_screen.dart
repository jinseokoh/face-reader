import 'package:face_reader/core/theme.dart';
import 'package:face_reader/data/services/coin_service.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';
import 'package:face_reader/presentation/widgets/login_bottom_sheet.dart';
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
                      Icon(Icons.paid_outlined,
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _PurchaseSheet(
        onPurchased: () => ref.read(authProvider.notifier).refreshCoins(),
      ),
    );
  }
}

class _PurchaseSheet extends StatefulWidget {
  final VoidCallback onPurchased;
  const _PurchaseSheet({required this.onPurchased});

  @override
  State<_PurchaseSheet> createState() => _PurchaseSheetState();
}

class _PurchaseSheetState extends State<_PurchaseSheet> {
  List<CoinProduct> _products = [];
  bool _isLoading = true;
  String? _purchasing;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('코인 충전',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 20),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_products.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text('상품을 불러올 수 없습니다.\n스토어 설정 후 이용 가능합니다.',
                    style: TextStyle(color: AppTheme.textHint, fontSize: 14),
                    textAlign: TextAlign.center),
              )
            else
              ..._products.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            _purchasing != null ? null : () => _purchase(p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.surface,
                          foregroundColor: AppTheme.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: AppTheme.border),
                          ),
                        ),
                        child: _purchasing == p.id
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('${p.coins} 코인',
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                  Text(p.price,
                                      style: TextStyle(
                                          color: AppTheme.textSecondary,
                                          fontSize: 14)),
                                ],
                              ),
                      ),
                    ),
                  )),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final products = await CoinService().getProducts();
    if (mounted) {
      setState(() {
        _products = products;
        _isLoading = false;
      });
    }
  }

  Future<void> _purchase(CoinProduct product) async {
    setState(() => _purchasing = product.id);
    final coins = await CoinService().purchase(product);
    if (coins > 0) {
      widget.onPurchased();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$coins 코인이 충전되었습니다!')),
        );
      }
    } else {
      if (mounted) {
        setState(() => _purchasing = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('구매에 실패했습니다')),
        );
      }
    }
  }
}
