import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/data/services/supabase_service.dart';

/// `react/` share host (facely.kr) 와 1:1 계약 — UUID 기반, Worker 미경유.
///
/// publishSolo / publishCompat:
///   1) 해당 report 의 supabaseId 보장 (없으면 SupabaseService.saveMetrics 로 생성)
///   2) PNG bytes 를 임시 파일로 저장
///   3) share_plus 로 OS share sheet 호출 — text 에 https://{host}/r/{uuid}
///      또는 https://{host}/r/{uuidA}~{uuidB}, 첨부에 PNG
///
/// 폐기됨: 구 `POST /api/share` 호출. Worker 가 `/api/share` 라우트를 의도적
/// 미구현. 받는 사람의 link 해석은 Worker SSR (`GET /r/:id`) 가 PAIR_SEP("~")
/// split 으로 1·2 UUID 케이스 모두 처리 (HOW-IT-WORKS §3.4 / §4.1).
class SharePublisher {
  SharePublisher._();
  static final SharePublisher instance = SharePublisher._();

  /// 궁합 URL 의 두 UUID 를 묶는 separator — Worker `app/lib/share-id.ts`
  /// 의 `PAIR_SEP` 와 동일 값 유지. 변경 시 양쪽 동시 PR.
  static const String pairSep = '~';

  /// `.env` 의 WEBAPP_BASE — Worker 의 WEBAPP_BASE 와 동일 값. fallback 'https://facely.kr'.
  String get _hostBase =>
      dotenv.env['WEBAPP_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://facely.kr';

  Future<void> publishSolo({
    required FaceReadingReport report,
    required Uint8List pngBytes,
  }) async {
    final uuid = await _ensureSupabaseId(report);
    await _shareFile(
      pngBytes: pngBytes,
      url: '$_hostBase/r/$uuid',
      tag: 'solo',
    );
  }

  Future<void> publishCompat({
    required FaceReadingReport my,
    required FaceReadingReport album,
    required Uint8List pngBytes,
  }) async {
    final myId = await _ensureSupabaseId(my);
    final albumId = await _ensureSupabaseId(album);
    await _shareFile(
      pngBytes: pngBytes,
      url: '$_hostBase/r/$myId$pairSep$albumId',
      tag: 'compat',
    );
  }

  Future<String> _ensureSupabaseId(FaceReadingReport report) async {
    final existing = report.supabaseId;
    if (existing != null && existing.isNotEmpty) return existing;
    final newId = await SupabaseService().saveMetrics(report);
    report.supabaseId = newId;
    return newId;
  }

  Future<void> _shareFile({
    required Uint8List pngBytes,
    required String url,
    required String tag,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/face_${tag}_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(pngBytes);
    debugPrint('[SharePublisher] $tag url=$url');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: url,
      ),
    );
  }
}
