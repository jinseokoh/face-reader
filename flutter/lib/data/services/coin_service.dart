import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import 'package:face_reader/data/services/auth_service.dart';

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

  Future<void> initialize() async {
    if (_initialized) return;
    final apiKey = dotenv.env['REVENUECAT_API_KEY']!;
    await Purchases.configure(
      PurchasesConfiguration(apiKey),
    );
    _initialized = true;
    debugPrint('[CoinService] RevenueCat initialized');
  }

  /// Set RevenueCat user ID after Kakao login
  Future<void> setUserId(String userId) async {
    await Purchases.logIn(userId);
    debugPrint('[CoinService] RevenueCat user set: $userId');
  }

  /// Fetch available coin products from store
  Future<List<CoinProduct>> getProducts() async {
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
    try {
      await Purchases.purchase(PurchaseParams.storeProduct(product.storeProduct));
      final coins = _coinMap[product.id] ?? 0;

      // Add coins to Supabase
      if (AuthService().isLoggedIn) {
        await AuthService().addCoins(coins);
      }

      debugPrint('[CoinService] purchased ${product.id} → +$coins coins');
      return coins;
    } catch (e) {
      debugPrint('[CoinService] purchase error: $e');
      return 0;
    }
  }
}
