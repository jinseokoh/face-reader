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
    final data = await listWithBody();
    return data.keys.toSet();
  }

  /// pair_key → body(JSON string, nullable) 맵. 비로그인이면 빈 맵.
  Future<Map<String, String?>> listWithBody() async {
    if (_client.auth.currentUser == null) return const {};
    try {
      final rows =
          await _client.from('unlocks').select('pair_key, body');
      return {
        for (final r in rows)
          r['pair_key'] as String: r['body'] as String?,
      };
    } catch (e) {
      debugPrint('[CompatUnlock] listWithBody error: $e');
      return const {};
    }
  }

  /// `listWithBody()` 의 non-null body 를 [FaceReadingReport] 로 복원.
  ///
  /// body 는 `toBodyJson()` 출력이므로 supabaseId 가 빠져 있다.
  /// pair_key(`myUuid~albumUuid`) 에서 album uuid 를 추출해 주입하고,
  /// [ShareReceiveService.fetchByUuid] 와 동일하게 source/isMyFace/alias/
  /// thumbnailPath 를 override 한 뒤 fromJsonString 으로 parse.
  Future<List<FaceReadingReport>> reconstructUnlockedPartners() async {
    final data = await listWithBody();
    final results = <FaceReadingReport>[];
    for (final entry in data.entries) {
      final body = entry.value;
      if (body == null || body.isEmpty) continue;
      final parts = entry.key.split('~');
      if (parts.length != 2) continue;
      final albumUuid = parts[1];
      try {
        final original = jsonDecode(body) as Map<String, dynamic>;
        final overridden = <String, dynamic>{
          ...original,
          'supabaseId': albumUuid,
          'source': AnalysisSource.received.name,
          'isMyFace': false,
          'alias': null,
          'thumbnailPath': null,
        };
        final report =
            FaceReadingReport.fromJsonString(jsonEncode(overridden));
        results.add(report);
      } catch (e) {
        debugPrint('[CompatUnlock] reconstruct failed '
            'pairKey=${entry.key}: $e');
      }
    }
    return results;
  }

  /// unlock_compat RPC 호출.
  ///
  /// 반환:
  ///   - `>= 0` : 새 잔액 (이미 해제된 경우는 차감 없이 현재 잔액)
  ///   - `-1`   : 잔액 부족
  ///
  /// RPC 자체가 실패하면 [Exception] 을 그대로 throw — 호출부에서 try/catch
  /// 로 감싸 사용자 피드백을 띄울 것.
  Future<int> unlock(String pairKey, {double? totalScore}) async {
    final result = await _client.rpc('unlock_compat', params: {
      'p_pair_key': pairKey,
      if (totalScore != null) 'p_total_score': totalScore,
    });
    debugPrint(
        '[CompatUnlock] unlock $pairKey → $result (${result.runtimeType})');
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is String) return int.parse(result);
    throw StateError(
        'unlock_compat returned unexpected type: ${result.runtimeType} ($result)');
  }
}
