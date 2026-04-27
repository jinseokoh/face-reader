import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/data/services/supabase_service.dart';

/// `react/` share host (face.kr) 와 1:1 계약.
///
/// publishSolo / publishCompat 가 호출되면:
///   1) 해당 report 의 supabaseId 보장 (없으면 saveMetrics 로 생성)
///   2) POST {SHARE_HOST_BASE}/api/share { type, userA, userB? } → shortId
///   3) PNG bytes 를 임시 파일로 저장
///   4) share_plus 로 OS share sheet — text 에 https://{host}/r/{shortId}, 첨부에 PNG
class SharePublisher {
  SharePublisher._();
  static final SharePublisher instance = SharePublisher._();

  /// `.env` 의 SHARE_HOST_BASE — fallback 'https://face.kr'.
  String get _hostBase =>
      dotenv.env['SHARE_HOST_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://face.kr';

  Future<void> publishSolo({
    required FaceReadingReport report,
    required Uint8List pngBytes,
  }) async {
    final uuid = await _ensureSupabaseId(report);
    final shortId = await _requestShortId(type: 'solo', userA: uuid);
    await _shareFile(
      pngBytes: pngBytes,
      url: '$_hostBase/r/$shortId',
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
    final shortId = await _requestShortId(
      type: 'compat',
      userA: myId,
      userB: albumId,
    );
    await _shareFile(
      pngBytes: pngBytes,
      url: '$_hostBase/r/$shortId',
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

  Future<String> _requestShortId({
    required String type,
    required String userA,
    String? userB,
  }) async {
    final res = await http.post(
      Uri.parse('$_hostBase/api/share'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'type': type,
        'userA': userA,
        if (userB != null) 'userB': userB,
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('share host ${res.statusCode}: ${res.body}');
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final shortId = body['shortId'] as String?;
    if (shortId == null || shortId.isEmpty) {
      throw Exception('share host returned empty shortId: ${res.body}');
    }
    debugPrint('[SharePublisher] $type shortId=$shortId');
    return shortId;
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
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        text: url,
      ),
    );
  }
}
