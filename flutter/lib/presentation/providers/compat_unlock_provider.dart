import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';

/// 현 사용자의 compat unlock pair_key 집합.
/// auth (로그인/로그아웃/잔액 리프레시) 변화에 재구독돼 자동 refetch.
final compatUnlocksProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(authProvider);
  return CompatUnlockService().list();
});
