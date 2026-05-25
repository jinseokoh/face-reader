import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/core/theme.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/data/services/coin_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';

/// Bottom sheet that loads coin products from RevenueCat and lets the user
/// trigger a purchase. Refreshes auth coins on success.
class PurchaseSheet extends ConsumerStatefulWidget {
  final VoidCallback? onPurchased;
  const PurchaseSheet({super.key, this.onPurchased});

  @override
  ConsumerState<PurchaseSheet> createState() => _PurchaseSheetState();

  static Future<void> show(BuildContext context, {VoidCallback? onPurchased}) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => PurchaseSheet(onPurchased: onPurchased),
    );
  }
}

class _PurchaseSheetState extends ConsumerState<PurchaseSheet> {
  List<CoinProduct> _products = [];
  bool _isLoading = true;
  String? _purchasing;

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

  /// 빈 상품 list 의 구체 원인을 한 문장으로. 진단 / 디버그 용.
  String _emptyReason() {
    final svc = CoinService();
    if (!svc.isAvailable) {
      return '결제 시스템이 활성화되지 않았습니다.\n${svc.initError ?? "원인 미상"}';
    }
    if (svc.lastFetchError != null) {
      return '상품 정보를 불러오지 못했습니다.\n${svc.lastFetchError}';
    }
    return '스토어에 등록된 상품이 없습니다.\n'
        '(App Store Connect / Play Console 의 상품 ID·승인 상태 확인,\n'
        '시뮬레이터/에뮬레이터에서는 IAP 미작동)';
  }

  Future<void> _purchase(CoinProduct product) async {
    AnalyticsService.instance.logClickCoin(product.coins);
    setState(() => _purchasing = product.id);
    final coins = await CoinService().purchase(product);
    if (coins > 0) {
      await ref.read(authProvider.notifier).refreshCoins();
      widget.onPurchased?.call();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$coins 코인이 충전되었습니다!')),
        );
      }
    } else if (mounted) {
      setState(() => _purchasing = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구매에 실패했습니다')),
      );
    }
  }

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
            // 광고 보상 옵션 — 광고 SDK 미통합 상태의 placeholder. UI 자리만 잡고
            // SDK 연결되면 onPressed 만 실 reward 흐름으로 교체.
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _purchasing != null
                      ? null
                      : () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('광고 시청 기능은 곧 활성화됩니다'),
                            ),
                          );
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.surface,
                    foregroundColor: AppTheme.textPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppTheme.border),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('1 코인',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                      Text('광고보기',
                          style: TextStyle(
                              color: AppTheme.textSecondary, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              )
            else if (_products.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _emptyReason(),
                  style: TextStyle(color: AppTheme.textHint, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
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
}
