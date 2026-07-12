import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

/// 결과: presign 받은 PUT URL, 업로드 완료 후 공개 접근 가능한 URL,
/// 그리고 Python /analyze 호출에 함께 보낼 단기 HMAC token.
///
/// token 은 `prefix == 'temp'` 케이스에만 의미 있음 (그 객체에 대해 분석
/// 요청 권한을 증명). thumbnails/ presign 응답엔 null 일 수 있음.
class PresignedUpload {
  final Uri uploadUrl;
  final Uri publicUrl;
  final String key;
  final String? token;

  const PresignedUpload({
    required this.uploadUrl,
    required this.publicUrl,
    required this.key,
    this.token,
  });
}

/// Cloudflare R2 업로더 — Flutter 가 R2 secret 을 직접 들고 있지 않도록,
/// 서버(WEBAPP_BASE) 의 presign 엔드포인트를 호출해 단기 PUT URL 을 받은 뒤
/// 그 URL 로 binary PUT.
///
/// 서버측 contract (별도 구현 필요):
///   POST {WEBAPP_BASE}/api/r2/presign
///   body: { "prefix": "temp" | "thumbnails", "uuid": "...", "ext": "jpg",
///           "contentType": "image/jpeg" }
///   resp: { "uploadUrl": "[short-lived signed PUT]",
///           "publicUrl": "[eventual GET URL]", "key": "temp/uuid.jpg" }
///
/// 서버 책임:
///   * temp/ prefix 는 R2 lifecycle 룰로 자동 삭제 (orphan 정리)
///   * thumbnails/ prefix 는 영구 보관 (YYYYMM 디렉토리는 서버가 자동 산출 OK)
///   * SigV4 signed URL TTL 은 5~10분 권장
class R2Uploader {
  static const _kPathPresign = '/api/r2/presign';

  static String get _hostBase =>
      dotenv.env['WEBAPP_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://facely.kr';

  final http.Client _client;

  R2Uploader({http.Client? client}) : _client = client ?? http.Client();

  /// 서버에 prefix·uuid·contentType 을 알리고 단기 PUT URL 을 받아온다.
  /// 서버가 YYYYMM 같은 동적 segment 를 직접 조립.
  Future<PresignedUpload> presign({
    required String prefix, // "temp" | "thumbnails"
    required String uuid,
    required String contentType,
    String ext = 'jpg',
  }) async {
    final res = await _client.post(
      Uri.parse('$_hostBase$_kPathPresign'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'prefix': prefix,
        'uuid': uuid,
        'ext': ext,
        'contentType': contentType,
      }),
    );
    if (res.statusCode != 200) {
      throw R2UploadException(
        'presign failed: ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return PresignedUpload(
      uploadUrl: Uri.parse(body['uploadUrl'] as String),
      publicUrl: Uri.parse(body['publicUrl'] as String),
      key: body['key'] as String,
      token: body['token'] as String?,
    );
  }

  /// 받은 presign URL 로 raw binary PUT. SigV4 signature 는 URL 안에 포함됨.
  /// Content-Type 헤더는 presign 시 서명한 값과 정확히 일치해야 한다 — 안 그러면 403.
  Future<void> putBytes({
    required Uri uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final res = await _client.put(
      uploadUrl,
      headers: {'content-type': contentType},
      body: bytes,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw R2UploadException(
        'PUT failed: ${res.statusCode} ${res.body}',
      );
    }
  }

  /// presign + putBytes 한 번에. 가장 흔한 경로.
  Future<PresignedUpload> upload({
    required String prefix,
    required String uuid,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String ext = 'jpg',
  }) async {
    final p = await presign(
      prefix: prefix,
      uuid: uuid,
      contentType: contentType,
      ext: ext,
    );
    await putBytes(
      uploadUrl: p.uploadUrl,
      bytes: bytes,
      contentType: contentType,
    );
    return p;
  }
}

class R2UploadException implements Exception {
  final String message;
  R2UploadException(this.message);
  @override
  String toString() => 'R2UploadException: $message';
}
