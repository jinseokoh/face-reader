import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 일일 무료 코인 (AdMob rewarded 3편 = 1코인) 진행도 + 시청 기록.
/// SoT 는 서버 — `ad_rewards` table (KST 자정 기준 reset).
class FreeCoinStatus {
  final int progress;
  final int max;
  final bool claimedToday;
  /// 이번 호출로 코인이 지급된 경우 새 잔액. 아니면 null.
  final int? balanceAfter;

  const FreeCoinStatus({
    required this.progress,
    required this.max,
    required this.claimedToday,
    this.balanceAfter,
  });

  factory FreeCoinStatus.fromRpc(Map<String, dynamic> r) => FreeCoinStatus(
        progress: (r['progress'] as num).toInt(),
        max: (r['max'] as num).toInt(),
        claimedToday: r['claimed_today'] as bool,
        balanceAfter: (r['balance_after'] as num?)?.toInt(),
      );

  int get remaining => (max - progress).clamp(0, max);
}

class FreeCoinService {
  static final FreeCoinService _instance = FreeCoinService._();
  factory FreeCoinService() => _instance;
  FreeCoinService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<FreeCoinStatus> status() async {
    final r = await _client.rpc('ad_reward_status');
    return FreeCoinStatus.fromRpc(Map<String, dynamic>.from(r as Map));
  }

  Future<FreeCoinStatus> recordView() async {
    final r = await _client.rpc('ad_reward_record_view');
    debugPrint('[FreeCoin] recordView → $r');
    return FreeCoinStatus.fromRpc(Map<String, dynamic>.from(r as Map));
  }
}
