import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/supabase_service.dart';

/// 카톡 등으로 받은 share URL (https://facely.kr/r/{uuid}) 을 받아
/// Supabase metrics row 를 fetch 한 뒤 받는 사람 관점의 FaceReadingReport 로
/// rehydrate 한다.
///
/// 핵심 변환:
///   * Supabase metrics row 자체는 **읽기만** — user_id 도, body 도 안 건드린다.
///   * body JSON 을 받아 `source=received`, `isMyFace=false`,
///     `alias=null`, `thumbnailPath=null` 로 override 한 뒤 fromJsonString 으로
///     parse. 원본 alias·thumbnailPath 는 leak 차단.
///   * `thumbnailKey` 와 `supabaseId` 는 그대로 둔다 — CDN 직통 read-only,
///     향후 궁합 unlock 키(partner_id) 후보.
///
/// 받는 사람이 Hive 에 저장하면 본문이 영구 박힘 — Supabase row 가 만료·삭제
/// 돼도 view 가능 (offline·resilient).
class ShareReceiveService {
  ShareReceiveService({SupabaseService? supabase})
      : _supabase = supabase ?? SupabaseService();

  final SupabaseService _supabase;

  /// uuid 로 fetch. row 없거나 body parse 실패 시 null.
  /// 호출자가 UI 에 "잘못된 link" snackbar 등 노출.
  Future<FaceReadingReport?> fetchByUuid(String uuid) async {
    debugPrint('[ShareReceiveService] fetch uuid=$uuid');
    final row = await _supabase.getMetrics(uuid);
    if (row == null) {
      debugPrint('[ShareReceiveService] row not found uuid=$uuid');
      return null;
    }
    final body = row['body'];
    if (body is! String || body.isEmpty) {
      debugPrint('[ShareReceiveService] body null/empty uuid=$uuid');
      return null;
    }
    try {
      final original = jsonDecode(body) as Map<String, dynamic>;
      final overridden = <String, dynamic>{
        ...original,
        'source': AnalysisSource.received.name,
        // isMyFace 는 row 컬럼에서 읽지만, 받는 사람 입장에서는 항상 false.
        'isMyFace': false,
        // 받는 사람 시점에선 alias·local thumbnail 초기화.
        'alias': null,
        'thumbnailPath': null,
        // supabaseId 는 URL 의 uuid 와 동일해야 함.
        'supabaseId': uuid,
      };
      final report =
          FaceReadingReport.fromJsonString(jsonEncode(overridden));
      debugPrint('[ShareReceiveService] OK uuid=$uuid '
          'thumbKey=${report.thumbnailKey}');
      return report;
    } catch (e, st) {
      debugPrint('[ShareReceiveService] parse failed uuid=$uuid error=$e');
      debugPrint('$st');
      return null;
    }
  }

  /// share URL string 에서 UUID 추출. 받아들이는 형식:
  ///   * https://facely.kr/r/{uuid}
  ///   * https://www.facely.kr/r/{uuid}
  ///   * facely.kr/r/{uuid} (scheme 생략)
  ///   * {uuid} 단독 (사용자가 UUID 만 복붙한 경우)
  /// 궁합 pair URL (`{uuid1}~{uuid2}`) 은 첫 UUID 만 반환.
  static String? extractUuid(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final uuidRe = RegExp(
      r'([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})',
      caseSensitive: false,
    );
    final match = uuidRe.firstMatch(trimmed);
    return match?.group(1)?.toLowerCase();
  }
}
