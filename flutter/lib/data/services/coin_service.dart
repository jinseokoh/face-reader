import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:face_reader/data/services/auth_service.dart';
import 'package:face_reader/domain/models/coin_transaction.dart';

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

  /// RevenueCat key 는 플랫폼별로 발급된다 — iOS 는 `appl_…`, Android 는
  /// `goog_…` prefix. 단일 key 를 양 플랫폼에 박으면 release 빌드에서 wrong
  /// API key 로 throw → main.dart 의 await 가 propagate → 앱 자체가 안 뜸.
  ///
  /// 정책:
  ///   1. `REVENUECAT_API_KEY_IOS` / `REVENUECAT_API_KEY_ANDROID` 가 있으면
  ///      플랫폼에 맞는 걸 사용. 없으면 fallback `REVENUECAT_API_KEY` (legacy).
  ///   2. key 가 비었거나 placeholder (`test_` prefix) 면 init 건너뜀 — 결제
  ///      미동작이지만 앱은 정상 launch. Phase 3 유료화 (TODO Roadmap-C)
  ///      실키 발급 후 본격 가동.
  ///   3. Purchases.configure 가 throw 해도 swallow + log — 결제는 부가
  ///      기능이고 앱 launch 자체를 막아선 안 됨.
  Future<void> initialize() async {
    if (_initialized) return;
    final apiKey = _resolveApiKey();
    if (apiKey == null) {
      debugPrint('[CoinService] RevenueCat key 미설정/placeholder — IAP disabled');
      return;
    }
    try {
      await Purchases.configure(PurchasesConfiguration(apiKey));
      _initialized = true;
      debugPrint('[CoinService] RevenueCat initialized (platform='
          '${Platform.isIOS ? "ios" : "android"})');
    } catch (e) {
      debugPrint('[CoinService] RevenueCat.configure failed — IAP disabled. '
          'error=$e');
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
    if (raw.startsWith('test_')) return null;
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
      return products.map((p) => CoinProduct(
        id: p.identifier,
        coins: _coinMap[p.identifier] ?? 0,
        price: p.priceString,
        storeProduct: p,
      )).toList();
    } catch (e) {
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
