import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class Ad {
  final String id;
  final String title;
  final String storagePath;
  final int? durationSec;
  final int rewardCoins;
  Ad({
    required this.id,
    required this.title,
    required this.storagePath,
    required this.durationSec,
    required this.rewardCoins,
  });

  factory Ad.fromRow(Map<String, dynamic> r) => Ad(
        id: r['id'] as String,
        title: r['title'] as String,
        storagePath: r['storage_path'] as String,
        durationSec: (r['duration_sec'] as num?)?.toInt(),
        rewardCoins: (r['reward_coins'] as num).toInt(),
      );

  /// supabase storage public URL.
  String get videoUrl {
    final client = Supabase.instance.client;
    final name = storagePath.startsWith('ads/')
        ? storagePath.substring(4)
        : storagePath;
    return client.storage.from('ads').getPublicUrl(name);
  }
}

/// `ads` 테이블 + `claim_ad_reward` RPC wrapper.
class AdService {
  static final AdService _instance = AdService._();
  factory AdService() => _instance;
  AdService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 활성 광고 1건 — 24h 안에 본 적 없는 광고 중 random pick.
  /// 본 광고만 남았거나 active 광고가 0이면 null.
  Future<Ad?> nextAd() async {
    final uid = _client.auth.currentUser?.id;
    final excluded = <String>{};
    if (uid != null) {
      final since =
          DateTime.now().toUtc().subtract(const Duration(hours: 24)).toIso8601String();
      final views = await _client
          .from('ad_views')
          .select('ad_id')
          .eq('user_id', uid)
          .gte('created_at', since);
      for (final v in views) {
        excluded.add(v['ad_id'] as String);
      }
    }

    var query = _client
        .from('ads')
        .select('id,title,storage_path,duration_sec,reward_coins')
        .eq('active', true);
    if (excluded.isNotEmpty) {
      query = query.not('id', 'in', '(${excluded.join(",")})');
    }
    final rows = await query.limit(50);
    if (rows.isEmpty) return null;
    rows.shuffle();
    return Ad.fromRow(rows.first);
  }

  /// 끝까지 시청 후 호출. 새 잔액 반환.
  ///
  /// 실패 케이스 (서버 raise exception):
  ///   - 'daily ad cap reached'    24h 내 5건 초과
  ///   - 'already claimed this ad recently'  같은 ad 24h 재청구
  ///   - 'ad not found or inactive'
  ///   - 'not authenticated'
  Future<int> claim(String adId) async {
    final result =
        await _client.rpc('claim_ad_reward', params: {'p_ad_id': adId});
    debugPrint('[AdService] claim $adId → $result');
    if (result is int) return result;
    if (result is num) return result.toInt();
    throw StateError('claim_ad_reward returned ${result.runtimeType}');
  }
}
