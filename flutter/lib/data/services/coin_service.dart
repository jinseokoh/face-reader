import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:facely/data/services/auth_service.dart';
import 'package:facely/domain/models/coin_transaction.dart';

class CoinProduct {
  final String id;
  final int coins;
  final String price;
  final StoreProduct storeProduct;

  const CoinProduct({
    required this.id,
    required this.coins,
    required this.price,
    required this.storeProduct,
  });
}

class CoinService {
  static final CoinService _instance = CoinService._();
  factory CoinService() => _instance;
  CoinService._();

  static const _productIds = ['coin_3', 'coin_10'];
  static const _coinMap = {
    'coin_3': 3,
    'coin_10': 10,
  };

  bool _initialized = false;
  bool get isAvailable => _initialized;
  String? _initError;
  String? _lastFetchError;
  /// 초기화 실패 시 사유 (UI 진단용). 미설정도 별도 메시지.
  String? get initError => _initError;
  /// 마지막 `getProducts` 호출의 에러 메시지 (성공 시 null).
  String? get lastFetchError => _lastFetchError;

  /// RevenueCat key 종류 (prefix 로 구분):
  ///   `appl_` (iOS App Store) · `goog_` (Google Play) · `amzn_` (Amazon) ·
  ///   `strp_` (Stripe) · `test_` (RevenueCat "Test Store" — 실제 store
  ///   연결 없이 mock IAP 로 개발용)
  ///
  /// 정책:
  ///   1. `REVENUECAT_API_KEY_IOS` / `REVENUECAT_API_KEY_ANDROID` 가 있으면
  ///      플랫폼에 맞는 걸 사용. 없으면 fallback `REVENUECAT_API_KEY` (legacy
  ///      또는 Test Store).
  ///   2. key 가 비어있을 때만 init 건너뜀.
  ///   3. Purchases.configure 가 throw 해도 swallow + log — 결제는 부가
  ///      기능이고 앱 launch 자체를 막아선 안 됨.
  Future<void> initialize() async {
    if (_initialized) return;
    final apiKey = _resolveApiKey();
    if (apiKey == null) {
      _initError = 'RevenueCat API key 미설정 (또는 test_ placeholder)';
      debugPrint('[CoinService] $_initError — IAP disabled');
      return;
    }
    try {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _initialized = true;
      _initError = null;
      debugPrint('[CoinService] RevenueCat initialized (platform='
          '${Platform.isIOS ? "ios" : "android"})');
    } catch (e) {
      _initError = 'configure failed: $e';
      debugPrint('[CoinService] $_initError — IAP disabled');
    }
  }

  String? _resolveApiKey() {
    final platformKey = Platform.isIOS
        ? dotenv.env['REVENUECAT_API_KEY_IOS']
        : Platform.isAndroid
            ? dotenv.env['REVENUECAT_API_KEY_ANDROID']
            : null;
    final raw = (platformKey?.trim().isNotEmpty ?? false)
        ? platformKey!.trim()
        : (dotenv.env['REVENUECAT_API_KEY']?.trim() ?? '');
    if (raw.isEmpty) return null;
    return raw;
  }

  /// Set RevenueCat user ID after Kakao login
  Future<void> setUserId(String userId) async {
    if (!_initialized) return;
    await Purchases.logIn(userId);
    debugPrint('[CoinService] RevenueCat user set: $userId');
  }

  /// Fetch available coin products from store
  Future<List<CoinProduct>> getProducts() async {
    if (!_initialized) return [];
    try {
      final products = await Purchases.getProducts(_productIds);
      _lastFetchError = null;
      debugPrint('[CoinService] getProducts → ${products.length} item(s) '
          'for ids=$_productIds');
      return products
          .map((p) => CoinProduct(
                id: p.identifier,
                coins: _coinMap[p.identifier] ?? 0,
                price: p.priceString,
                storeProduct: p,
              ))
          .toList();
    } catch (e) {
      _lastFetchError = e.toString();
      debugPrint('[CoinService] getProducts error: $e');
      return [];
    }
  }

  /// Purchase a coin product. Returns number of coins purchased, or 0 on failure.
  Future<int> purchase(CoinProduct product) async {
    if (!_initialized) {
      debugPrint('[CoinService] purchase skipped — RevenueCat unavailable');
      return 0;
    }
    try {
      await Purchases.purchase(
        PurchaseParams.storeProduct(product.storeProduct),
      );
      final coins = _coinMap[product.id] ?? 0;

      if (AuthService().isLoggedIn) {
        await AuthService().addCoins(
          coins,
          kind: CoinTxKind.purchase,
          productId: product.id,
          description: '$coins 코인 충전',
        );
      }

      debugPrint('[CoinService] purchased ${product.id} → +$coins coins');
      return coins;
    } catch (e) {
      debugPrint('[CoinService] purchase error: $e');
      return 0;
    }
  }
}
