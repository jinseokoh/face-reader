import 'package:facely/core/theme.dart';
import 'package:facely/data/services/admob_service.dart';
import 'package:facely/data/services/analytics_service.dart';
import 'package:facely/data/services/coin_service.dart';
import 'package:facely/data/services/free_coin_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/free_coin_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom sheet that loads coin products from RevenueCat and lets the user
/// trigger a purchase. Also exposes the AdMob rewarded-video free-coin track
/// (3편 시청 = 1코인, 1일 1회). Refreshes auth coins on success.
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

/// 오늘의 무료 코인 버튼 — IAP 상품 버튼과 시각적으로 동일한 surface/border 톤.
/// 좌측 label = "1 코인 무료 (가능 X/3)", 우측 trailing = "광고 보기" / 진행 상태.
class _FreeCoinCard extends StatelessWidget {
  static const _subLabel = '광고 3편을 보면 1코인 충전';
  final FreeCoinStatus status;
  final bool busy;
  final VoidCallback? onTap;

  const _FreeCoinCard(
      {required this.status, required this.busy, required this.onTap});

  String get _mainLabel {
    if (status.claimedToday) return '오늘의 무료 1코인 (충전 완료)';
    return '오늘의 무료1코인 (${status.progress}/${status.max})';
  }

  String get _rightLabel {
    if (status.claimedToday) return '내일 다시';
    return '광고 보기';
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 64,
      child: ElevatedButton(
        onPressed: busy ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.lg - 2),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_mainLabel, style: AppText.subTitle),
                      const SizedBox(height: 2),
                      const Text(_subLabel, style: AppText.hint),
                    ],
                  ),
                  Text(_rightLabel,
                      style: AppText.body
                          .copyWith(color: AppColors.textSecondary)),
                ],
              ),
      ),
    );
  }
}

class _FreeCoinSkeleton extends StatelessWidget {
  const _FreeCoinSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(width: double.infinity, height: 64);
  }
}

class _PurchaseSheetState extends ConsumerState<PurchaseSheet> {
  List<CoinProduct> _products = [];
  bool _isLoading = true;
  String? _purchasing;
  bool _watchingAd = false;

  @override
  Widget build(BuildContext context) {
    final freeCoinAsync = ref.watch(freeCoinStatusProvider);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xxl, AppSpacing.xxl, AppSpacing.xxl, AppSpacing.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('코인 충전', style: AppText.modalTitle),
            const SizedBox(height: AppSpacing.xl),
            // 무료 코인 카드 (AdMob rewarded 3편 = 1코인).
            // 비로그인이면 null → 카드 미노출.
            freeCoinAsync.when(
              data: (status) => status == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: _FreeCoinCard(
                        status: status,
                        busy: _watchingAd,
                        onTap: status.claimedToday || _purchasing != null
                            ? null
                            : _watchAd,
                      ),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: _FreeCoinSkeleton(),
              ),
              error: (_, _) => const SizedBox.shrink(),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.xxl),
                child: CircularProgressIndicator(),
              )
            else if (_products.isEmpty)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xxl),
                child: Text(
                  _emptyReason(),
                  style: AppText.caption.copyWith(color: AppColors.textHint),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ..._products.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm + 2),
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed:
                            _purchasing != null ? null : () => _purchase(p),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.surface,
                          foregroundColor: AppColors.textPrimary,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(AppRadius.lg - 2),
                            side: const BorderSide(color: AppColors.border),
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
                                      style: AppText.subTitle),
                                  Text(p.price,
                                      style: AppText.body.copyWith(
                                          color: AppColors.textSecondary)),
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

  Future<void> _watchAd() async {
    setState(() => _watchingAd = true);
    final earned = await AdMobService().showRewarded();
    if (!mounted) {
      return;
    }
    if (!earned) {
      setState(() => _watchingAd = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('광고 시청이 완료되지 않았어요')),
      );
      return;
    }
    try {
      final s = await FreeCoinService().recordView();
      if (!mounted) return;
      ref.invalidate(freeCoinStatusProvider);
      if (s.balanceAfter != null) {
        await ref.read(authProvider.notifier).refreshCoins();
        if (!mounted) return;
        widget.onPurchased?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('1 코인이 무료 충전되었습니다!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${s.remaining}편 더 보면 충전됩니다'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('진행도 저장 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _watchingAd = false);
    }
  }
}
