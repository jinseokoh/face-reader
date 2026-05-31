import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';

/// pair_key → body 전체 맵. 다른 provider 들이 재사용.
final _unlocksRawProvider =
    FutureProvider.autoDispose<Map<String, String?>>((ref) {
  ref.watch(authProvider);
  return CompatUnlockService().listWithBody();
});

/// 현 사용자의 compat unlock pair_key 집합.
/// auth (로그인/로그아웃/잔액 리프레시) 변화에 재구독돼 자동 refetch.
final compatUnlocksProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  final raw = ref.watch(_unlocksRawProvider);
  return raw.when(
    data: (m) => m.keys.toSet(),
    loading: () => const <String>{},
    error: (_, _) => const <String>{},
  );
});

/// unlocks.body 에서 복원한 파트너 리포트 목록 (로컬에 없는 갭 메우기용).
/// auth 변화에 재구독.
final unlockedPartnerBodiesProvider =
    FutureProvider.autoDispose<List<FaceReadingReport>>((ref) async {
  ref.watch(authProvider);
  return CompatUnlockService().reconstructUnlockedPartners();
});
