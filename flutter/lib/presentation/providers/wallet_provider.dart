import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/data/services/wallet_service.dart';
import 'package:face_reader/domain/models/coin_transaction.dart';
import 'package:face_reader/presentation/providers/auth_provider.dart';

/// Loads the current user's coin history. Re-runs whenever the auth user
/// changes (login, logout, coin balance refresh).
final walletHistoryProvider =
    FutureProvider.autoDispose<List<CoinTransaction>>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return const [];
  return WalletService().list();
});
