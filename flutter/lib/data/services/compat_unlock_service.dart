import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';

/// unlocks 테이블 + unlock_compat RPC 래퍼.
///
/// RLS 가 user_id = auth.uid() 로 SELECT 를 제한 → `list()` 는 자동으로 현
/// 사용자 것만 반환. INSERT 정책은 없고 `unlock_compat` RPC (SECURITY DEFINER)
/// 만 쓰기를 수행해 코인 차감과 unlock 삽입을 한 트랜잭션으로 묶는다.
class CompatUnlockService {
  static final CompatUnlockService _instance = CompatUnlockService._();
  factory CompatUnlockService() => _instance;
  CompatUnlockService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 현 사용자의 unlock 된 pair_key 집합. 비로그인이면 빈 set.
  Future<Set<String>> list() async {
    if (_client.auth.currentUser == null) return const {};
    try {
      final rows = await _client.from('unlocks').select('pair_key');
      return {for (final r in rows) r['pair_key'] as String};
    } catch (e) {
      debugPrint('[CompatUnlock] list error: $e');
      return const {};
    }
  }

  /// unlocks 의 `partner_body`(결제 시점 상대 스냅샷)를 [FaceReadingReport] 로 복원.
  ///
  /// body 는 `toBodyJson()` 출력이라 supabaseId 가 빠져 있으므로 pair_key
  /// (`ownerUuid~partnerUuid`) 의 2번째 uuid 를 supabaseId 로 주입하고,
  /// source/isMyFace/alias/thumbnailPath 를 override 한 뒤 parse.
  /// metrics row·로컬 history 에 의존하지 않는 self-contained 복원.
  Future<List<FaceReadingReport>> reconstructUnlockedPartners() async {
    return (await partnerSnapshotsByPairKey()).values.toList();
  }

  /// `pair_key → 결제 시점 partner 스냅샷(FaceReadingReport)` 맵.
  ///
  /// `unlocks.partner_body` 만 디코드하므로 로컬 history·metrics row 에 의존하지
  /// 않는다. ledger(코인 사용내역)·확인 리스트가 기기·재설치·eviction 무관하게
  /// 항상 상대 사진/인적정보를 띄우는 source of truth. body 엔 alias 가 빠져
  /// 있어(소유 메타) null override — 인적정보(성별·나이·얼굴형·thumbnailKey)는 포함.
  Future<Map<String, FaceReadingReport>> partnerSnapshotsByPairKey() async {
    if (_client.auth.currentUser == null) return const {};
    final List<dynamic> rows;
    try {
      rows = await _client.from('unlocks').select('pair_key, partner_body');
    } catch (e) {
      debugPrint('[CompatUnlock] partner snapshot fetch error: $e');
      return const {};
    }
    final map = <String, FaceReadingReport>{};
    for (final r in rows) {
      final pairKey = r['pair_key'] as String?;
      final body = r['partner_body'] as String?;
      if (pairKey == null || body == null || body.isEmpty) continue;
      // pair_key 가 곧 상대 supabaseId (partner-only 키).
      try {
        final original = jsonDecode(body) as Map<String, dynamic>;
        final overridden = <String, dynamic>{
          ...original,
          'supabaseId': pairKey,
          'source': AnalysisSource.received.name,
          'isMyFace': false,
          'alias': null,
          'thumbnailPath': null,
        };
        map[pairKey] = FaceReadingReport.fromJsonString(jsonEncode(overridden));
      } catch (e) {
        debugPrint(
            '[CompatUnlock] partner snapshot decode failed pairKey=$pairKey: $e');
      }
    }
    return map;
  }

  /// unlock_compat RPC 호출. owner/partner body 를 결제 시점 스냅샷으로 동결.
  ///
  /// 반환:
  ///   - `>= 0` : 새 잔액 (이미 해제된 경우는 차감 없이 현재 잔액)
  ///   - `-1`   : 잔액 부족
  ///
  /// RPC 자체가 실패하면 [Exception] 을 그대로 throw — 호출부에서 try/catch
  /// 로 감싸 사용자 피드백을 띄울 것.
  Future<int> unlock(
    String pairKey, {
    required String ownerBody,
    required String partnerBody,
    double? totalScore,
  }) async {
    final result = await _client.rpc('unlock_compat', params: {
      'p_pair_key': pairKey,
      'p_total_score': ?totalScore,
      'p_owner_body': ownerBody,
      'p_partner_body': partnerBody,
    });
    debugPrint(
        '[CompatUnlock] unlock $pairKey → $result (${result.runtimeType})');
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is String) return int.parse(result);
    throw StateError(
        'unlock_compat returned unexpected type: ${result.runtimeType} ($result)');
  }

  /// 확인 리스트에서 "내 목록에서 제거" — unlock 행 삭제. RLS(`unlocks_self_delete`)
  /// 가 user_id 로 스코프하므로 pair_key 만으로 본인 행만 지운다. pair_key 는
  /// 방향성이 있어 정/역 둘 다 넘겨 어느 쪽으로 결제됐든 제거. 코인 환불 없음.
  Future<void> deleteUnlock(List<String> pairKeys) async {
    for (final key in pairKeys) {
      await _client.from('unlocks').delete().eq('pair_key', key);
    }
  }
}
