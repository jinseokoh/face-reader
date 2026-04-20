import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:face_reader/domain/models/coin_transaction.dart';

/// All RPCs derive the user from `auth.uid()` — caller must be a signed-in
/// Supabase Auth session. RLS on `public.coins` filters rows by owner, so
/// `list()` naturally returns only the caller's own ledger.
class WalletService {
  static final WalletService _instance = WalletService._();
  factory WalletService() => _instance;
  WalletService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Fetch latest transactions for the signed-in user, newest first.
  Future<List<CoinTransaction>> list({int limit = 100}) async {
    try {
      final rows = await _client
          .from('coins')
          .select()
          .order('created_at', ascending: false)
          .limit(limit);
      return rows
          .map<CoinTransaction>((r) => CoinTransaction.fromRow(r))
          .toList();
    } catch (e) {
      debugPrint('[Wallet] list error: $e');
      return const [];
    }
  }

  /// Credit coins via RPC (atomic update + tx insert). Returns new balance.
  Future<int> grant({
    required int amount,
    required CoinTxKind kind,
    String? productId,
    String? storeTransactionId,
    String? description,
  }) async {
    assert(kind != CoinTxKind.spend);
    final balance = await _client.rpc('grant_coins', params: {
      'p_amount': amount,
      'p_kind': kind.wire,
      'p_product_id': productId,
      'p_store_transaction_id': storeTransactionId,
      'p_description': description,
    });
    debugPrint('[Wallet] grant $amount ($kind) → $balance');
    return balance as int;
  }

  /// Debit coins via RPC. Returns new balance, or -1 if insufficient.
  Future<int> spend({
    required int amount,
    String? referenceId,
    String? description,
  }) async {
    final balance = await _client.rpc('spend_coins', params: {
      'p_amount': amount,
      'p_reference_id': referenceId,
      'p_description': description,
    });
    debugPrint('[Wallet] spend $amount → $balance');
    return balance as int;
  }
}
