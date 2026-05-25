import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/data/services/free_coin_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';

/// 오늘의 무료 코인 진행도. login 상태 변할 때마다 재호출.
/// 광고 시청 후 invalidate 로 refresh.
final freeCoinStatusProvider =
    FutureProvider.autoDispose<FreeCoinStatus?>((ref) async {
  final user = ref.watch(authProvider);
  if (user == null) return null;
  return FreeCoinService().status();
});
