import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/compat_unlock_service.dart';
import 'package:facely/presentation/providers/auth_provider.dart';
import 'package:facely/presentation/providers/history_provider.dart';

/// 현 사용자의 unlock 쌍 키(`lo~hi`) 집합.
/// auth (로그인/로그아웃/잔액 리프레시) 변화에 재구독돼 자동 refetch.
final compatUnlocksProvider = FutureProvider.autoDispose<Set<String>>((ref) {
  ref.watch(authProvider);
  return CompatUnlockService().list();
});

/// 내 my-face 의 supabaseId — unlock 행에서 "내 쌍/상대 쪽" 판별 키.
String? _myFaceId(Ref ref) =>
    ref.watch(historyProvider).where((r) => r.isMyFace).firstOrNull?.supabaseId;

/// unlocks 스냅샷에서 복원한 **내 쌍** 파트너 리포트 목록 (로컬에 없는 갭
/// 메우기용 — 매칭 제3자 쌍은 제외). auth 변화에 재구독.
final unlockedPartnerBodiesProvider =
    FutureProvider.autoDispose<List<FaceReadingReport>>((ref) async {
      ref.watch(authProvider);
      return CompatUnlockService().reconstructUnlockedPartners(
        myFaceId: _myFaceId(ref),
      );
    });

/// `상대 id → 결제 시점 상대 스냅샷` 맵 — 내 쌍만. ledger(코인 사용내역)가
/// 로컬 히스토리 의존 없이 항상 상대 사진·인적정보를 띄우는 source.
/// auth 변화에 재구독.
final compatPartnerSnapshotsProvider =
    FutureProvider.autoDispose<Map<String, FaceReadingReport>>((ref) async {
      ref.watch(authProvider);
      return CompatUnlockService().partnerSnapshotsByPartnerId(
        myFaceId: _myFaceId(ref),
      );
    });

/// 구매한 쌍 전체 (내 쌍 + 매칭 제3자 쌍) — 궁합 확인 리스트의 source of
/// truth. auth 변화에 재구독.
final unlockedPairsProvider = FutureProvider.autoDispose<List<UnlockedPair>>((
  ref,
) async {
  ref.watch(authProvider);
  return CompatUnlockService().unlockedPairs();
});
