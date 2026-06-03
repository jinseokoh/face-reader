import 'package:supabase_flutter/supabase_flutter.dart';

/// 외부 광고주 배너 1건 — 홈 탭 상단 rotation 노출, 탭 시 linkUrl 이동.
class AdImageBanner {
  final String id;
  final String title;
  final String storagePath;
  final String? linkUrl;
  AdImageBanner({
    required this.id,
    required this.title,
    required this.storagePath,
    required this.linkUrl,
  });

  factory AdImageBanner.fromRow(Map<String, dynamic> r) => AdImageBanner(
        id: r['id'] as String,
        title: r['title'] as String,
        storagePath: r['storage_path'] as String,
        linkUrl: r['link_url'] as String?,
      );

  /// supabase storage 'ad_images' 버킷 public URL.
  String get imageUrl {
    final client = Supabase.instance.client;
    const prefix = 'ad_images/';
    final name = storagePath.startsWith(prefix)
        ? storagePath.substring(prefix.length)
        : storagePath;
    return client.storage.from('ad_images').getPublicUrl(name);
  }
}

class AdImageService {
  static final AdImageService _instance = AdImageService._();
  factory AdImageService() => _instance;
  AdImageService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 활성 배너를 sort_order 오름차순(동순위는 최신순)으로. 없으면 빈 리스트.
  Future<List<AdImageBanner>> activeBanners() async {
    final rows = await _client
        .from('ad_images')
        .select('id,title,storage_path,link_url')
        .eq('active', true)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);
    return [
      for (final r in rows)
        AdImageBanner.fromRow(Map<String, dynamic>.from(r as Map)),
    ];
  }
}
