import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';

/// 현 사용자의 compat unlock pair_key 집합.
/// auth (로그인/로그아웃/잔액 리프레시) 변화에 재구독돼 자동 refetch.
final compatUnlocksProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(authProvider);
  return CompatUnlockService().list();
});

/// unlocks.body 에서 복원한 파트너 리포트 목록 (로컬에 없는 갭 메우기용).
/// auth 변화에 재구독.
final unlockedPartnerBodiesProvider =
    FutureProvider.autoDispose<List<FaceReadingReport>>((ref) async {
  ref.watch(authProvider);
  return CompatUnlockService().reconstructUnlockedPartners();
});
