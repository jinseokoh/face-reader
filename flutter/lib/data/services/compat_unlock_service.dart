import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// compat_unlocks 테이블 + unlock_compat RPC 래퍼.
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
      final rows = await _client.from('compat_unlocks').select('pair_key');
      return rows.map<String>((r) => r['pair_key'] as String).toSet();
    } catch (e) {
      debugPrint('[CompatUnlock] list error: $e');
      return const {};
    }
  }

  /// unlock_compat RPC 호출.
  ///
  /// 반환:
  ///   - `>= 0` : 새 잔액 (이미 해제된 경우는 차감 없이 현재 잔액)
  ///   - `-1`   : 잔액 부족
  Future<int> unlock(String pairKey) async {
    final result = await _client.rpc('unlock_compat', params: {
      'p_pair_key': pairKey,
    });
    debugPrint('[CompatUnlock] unlock $pairKey → $result');
    return result as int;
  }
}
