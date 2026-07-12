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

  /// 현 사용자의 unlock 된 상대 metrics id(partner_id) 집합. 비로그인이면 빈 set.
  Future<Set<String>> list() async {
    if (_client.auth.currentUser == null) return const {};
    try {
      final rows = await _client.from('unlocks').select('partner_id');
      return {for (final r in rows) r['partner_id'] as String};
    } catch (e) {
      debugPrint('[CompatUnlock] list error: $e');
      return const {};
    }
  }

  /// unlocks 의 `partner_body`(결제 시점 상대 스냅샷)를 [FaceReadingReport] 로 복원.
  ///
  /// body 는 `toBodyJson()` 출력이라 supabaseId 가 빠져 있으므로 partner_id 를
  /// supabaseId 로 주입하고, source/isMyFace/alias/thumbnailPath 를 override 한 뒤
  /// parse. metrics row·로컬 history 에 의존하지 않는 self-contained 복원.
  Future<List<FaceReadingReport>> reconstructUnlockedPartners() async {
    return (await partnerSnapshotsByPartnerId()).values.toList();
  }

  /// `partner_id → 결제 시점 partner 스냅샷(FaceReadingReport)` 맵.
  ///
  /// `unlocks.partner_body` 만 디코드하므로 로컬 history·metrics row 에 의존하지
  /// 않는다. ledger(코인 사용내역)·확인 리스트가 기기·재설치·eviction 무관하게
  /// 항상 상대 사진/인적정보를 띄우는 source of truth. 이름은 body 가 아니라
  /// `partner_alias` 컬럼 스냅샷(결제 시점 동결)에서 주입.
  Future<Map<String, FaceReadingReport>> partnerSnapshotsByPartnerId() async {
    if (_client.auth.currentUser == null) return const {};
    final List<dynamic> rows;
    try {
      rows = await _client
          .from('unlocks')
          .select('partner_id, partner_body, partner_alias');
    } catch (e) {
      debugPrint('[CompatUnlock] partner snapshot fetch error: $e');
      return const {};
    }
    final map = <String, FaceReadingReport>{};
    for (final r in rows) {
      final partnerId = r['partner_id'] as String?;
      final body = r['partner_body'] as String?;
      if (partnerId == null || body == null || body.isEmpty) continue;
      try {
        final original = jsonDecode(body) as Map<String, dynamic>;
        final overridden = <String, dynamic>{
          ...original,
          'supabaseId': partnerId,
          'source': AnalysisSource.received.name,
          'isMyFace': false,
          'alias': r['partner_alias'],
          'thumbnailPath': null,
        };
        map[partnerId] =
            FaceReadingReport.fromJsonString(jsonEncode(overridden));
      } catch (e) {
        debugPrint(
            '[CompatUnlock] partner snapshot decode failed partnerId=$partnerId: $e');
      }
    }
    return map;
  }

  /// unlock_compat RPC 호출. body·alias 를 결제 시점 스냅샷으로 동결.
  ///
  /// 반환:
  ///   - `>= 0` : 새 잔액 (이미 해제된 경우는 차감 없이 현재 잔액)
  ///   - `-1`   : 잔액 부족
  ///
  /// RPC 자체가 실패하면 [Exception] 을 그대로 throw — 호출부에서 try/catch
  /// 로 감싸 사용자 피드백을 띄울 것.
  Future<int> unlock(
    String partnerId, {
    required String userBody,
    required String partnerBody,
    String? userAlias,
    String? partnerAlias,
    double? totalScore,
  }) async {
    final result = await _client.rpc('unlock_compat', params: {
      'p_partner_id': partnerId,
      'p_total_score': ?totalScore,
      'p_user_body': userBody,
      'p_partner_body': partnerBody,
      'p_user_alias': ?userAlias,
      'p_partner_alias': ?partnerAlias,
    });
    debugPrint(
        '[CompatUnlock] unlock $partnerId → $result (${result.runtimeType})');
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is String) return int.parse(result);
    throw StateError(
        'unlock_compat returned unexpected type: ${result.runtimeType} ($result)');
  }

  /// 확인 리스트에서 "내 목록에서 제거" — unlock 행 삭제. RLS(`unlocks_self_delete`)
  /// 가 user_id 로 스코프하므로 partner_id 만으로 본인 행만 지운다. 코인 환불 없음.
  Future<void> deleteUnlock(List<String> partnerIds) async {
    for (final id in partnerIds) {
      await _client.from('unlocks').delete().eq('partner_id', id);
    }
  }
}
