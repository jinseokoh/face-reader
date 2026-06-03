import 'package:supabase_flutter/supabase_flutter.dart';

/// custom video 광고 1건 — 무료코인 3편 중 1편으로 노출.
class AdVideo {
  final String id;
  final String title;
  final String storagePath;
  final int? durationSec;
  AdVideo({
    required this.id,
    required this.title,
    required this.storagePath,
    required this.durationSec,
  });

  factory AdVideo.fromRow(Map<String, dynamic> r) => AdVideo(
        id: r['id'] as String,
        title: r['title'] as String,
        storagePath: r['storage_path'] as String,
        durationSec: (r['duration_sec'] as num?)?.toInt(),
      );

  /// supabase storage 'ad_videos' 버킷 public URL.
  String get videoUrl {
    final client = Supabase.instance.client;
    const prefix = 'ad_videos/';
    final name =
        storagePath.startsWith(prefix) ? storagePath.substring(prefix.length) : storagePath;
    return client.storage.from('ad_videos').getPublicUrl(name);
  }
}

/// `ad_videos` 테이블 reader. 시청 카운트·코인 지급은 무료코인 카운터
/// (free_coin_service → ad_reward_record_view) 가 AdMob 과 공통으로 담당하므로,
/// 여기서는 "재생할 활성 영상" 만 고른다. (per-video dedup·claim 없음.)
class AdService {
  static final AdService _instance = AdService._();
  factory AdService() => _instance;
  AdService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 활성 영상 광고 중 무작위 1건. 없으면 null.
  Future<AdVideo?> nextActiveVideo() async {
    final rows = await _client
        .from('ad_videos')
        .select('id,title,storage_path,duration_sec')
        .eq('active', true)
        .limit(50);
    if (rows.isEmpty) return null;
    rows.shuffle();
    return AdVideo.fromRow(rows.first);
  }
}
