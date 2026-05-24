import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/data/services/wallet_service.dart';
import 'package:facely/domain/models/coin_transaction.dart';
import 'package:facely/presentation/providers/auth_provider.dart';

/// Loads the current user's coin history. Re-runs whenever the auth user
/// changes (login, logout, coin balance refresh).
final walletHistoryProvider =
    FutureProvider.autoDispose<List<CoinTransaction>>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return const [];
  return WalletService().list();
});
