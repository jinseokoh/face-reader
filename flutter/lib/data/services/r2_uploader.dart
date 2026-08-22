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
  /// 서버가 409(이미 존재)로 답했으면 null — PUT 할 것이 없다.
  final Uri? uploadUrl;
  final Uri publicUrl;
  final String key;
  final String? token;

  /// PUT 시 그대로 실어 보낼 값. 내용 주소 키는 불변이라 무기한 캐시가 안전하다.
  final String? cacheControl;

  /// 같은 바이트가 이미 저장돼 있다 — 업로드는 성공으로 취급한다.
  final bool alreadyExists;

  const PresignedUpload({
    required this.uploadUrl,
    required this.publicUrl,
    required this.key,
    this.token,
    this.cacheControl,
    this.alreadyExists = false,
  });
}

/// Cloudflare R2 업로더 — Flutter 가 R2 secret 을 직접 들고 있지 않도록,
/// 서버(WEBAPP_BASE) 의 presign 엔드포인트를 호출해 단기 PUT URL 을 받은 뒤
/// 그 URL 로 binary PUT.
///
/// 서버측 contract (별도 구현 필요):
///   POST {WEBAPP_BASE}/api/r2/presign
///   body: { "prefix": "temp",       "uuid": "...", "ext", "contentType" }
///         { "prefix": "thumbnails", "hash": "`sha256 hex`", ... }
///   resp 200: { uploadUrl, publicUrl, key, cacheControl, token? }
///   resp 409: { key, publicUrl, exists: true }
///
/// 서버 책임:
///   * temp/ prefix 는 R2 lifecycle 룰로 자동 삭제 (orphan 정리)
///   * thumbnails/ prefix 는 영구 보관, 키는 내용 주소로 서버가 조립
///   * 이미 있는 thumbnails/ 객체엔 PUT URL 을 발급하지 않는다 (409) — 이
///     엔드포인트는 인증이 없어서, 발급하면 남의 썸네일을 덮어쓸 수 있다
///   * SigV4 signed URL TTL 은 5~10분 권장
class R2Uploader {
  static const _kPathPresign = '/api/r2/presign';

  static String get _hostBase =>
      dotenv.env['WEBAPP_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://facely.kr';

  final http.Client _client;

  R2Uploader({http.Client? client}) : _client = client ?? http.Client();

  /// 서버에 prefix 와 키 재료를 알리고 단기 PUT URL 을 받아온다. 키 조립은
  /// 서버 몫이다 (`thumbnails/` 는 [hash], `temp/` 는 [uuid]).
  Future<PresignedUpload> presign({
    required String prefix, // "temp" | "thumbnails"
    String? uuid, // temp/ 경로
    String? hash, // thumbnails/ 내용 주소 (sha256 hex)
    required String contentType,
    String ext = 'jpg',
  }) async {
    assert(uuid != null || hash != null, 'uuid 나 hash 중 하나는 있어야 한다');
    final res = await _client.post(
      Uri.parse('$_hostBase$_kPathPresign'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'prefix': prefix,
        'hash': ?hash,
        if (hash == null) 'uuid': ?uuid,
        'ext': ext,
        'contentType': contentType,
      }),
    );
    // 상태 확인이 파싱보다 먼저 — 5xx 본문은 JSON 이 아니라 HTML·텍스트다.
    if (res.statusCode != 200 && res.statusCode != 409) {
      throw R2UploadException(
        'presign failed: ${res.statusCode} ${res.body}',
      );
    }
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    // 409 = 같은 바이트가 이미 저장돼 있다. 실패가 아니다.
    if (res.statusCode == 409) {
      return PresignedUpload(
        uploadUrl: null,
        publicUrl: Uri.parse(body['publicUrl'] as String),
        key: body['key'] as String,
        alreadyExists: true,
      );
    }
    return PresignedUpload(
      uploadUrl: Uri.parse(body['uploadUrl'] as String),
      publicUrl: Uri.parse(body['publicUrl'] as String),
      key: body['key'] as String,
      token: body['token'] as String?,
      cacheControl: body['cacheControl'] as String?,
    );
  }

  /// 받은 presign URL 로 raw binary PUT. SigV4 signature 는 URL 안에 포함됨.
  /// Content-Type 헤더는 presign 시 서명한 값과 정확히 일치해야 한다 — 안 그러면 403.
  Future<void> putBytes({
    required Uri uploadUrl,
    required Uint8List bytes,
    required String contentType,
    String? cacheControl,
  }) async {
    final res = await _client.put(
      uploadUrl,
      headers: {
        'content-type': contentType,
        'cache-control': ?cacheControl,
      },
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
    String? uuid,
    String? hash,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
    String ext = 'jpg',
  }) async {
    final p = await presign(
      prefix: prefix,
      uuid: uuid,
      hash: hash,
      contentType: contentType,
      ext: ext,
    );
    final url = p.uploadUrl;
    if (url == null) return p; // 409 — 같은 바이트가 이미 저장돼 있다.
    await putBytes(
      uploadUrl: url,
      bytes: bytes,
      contentType: contentType,
      cacheControl: p.cacheControl,
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
