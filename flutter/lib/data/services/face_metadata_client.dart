import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:facely/data/services/image_resizer.dart';
import 'package:facely/data/services/r2_uploader.dart';
import 'package:facely/domain/models/face_metadata.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// 옵션 F (with 0 orphan strategy) 전체 파이프라인의 client-side orchestrator.
///
/// 흐름:
///   1) UUID v4 한 번 발급 — 이후 temp/thumbnails/metrics/share link 전부 같은 값
///   2) Flutter 가 원본을 720px 로 리사이즈 → R2 temp/{uuid}.jpg 로 PUT
///   3) Python /analyze 호출 → {age, gender, ethnicity}
///   4) **분석 성공한 경우에만** 200 리사이즈 → R2 thumbnails/{YYYYMMDD}/{uuid}.jpg 로 PUT
///   5) FaceMetadata 반환 (uuid + thumbnailUrl 포함)
///
/// 발급한 uuid 는 caller 가 [FaceReadingReport.supabaseId] 에 즉시 assign 해야
/// 한다. 그래야 publish 시점에 SupabaseService.saveMetrics 가 metrics.id 로
/// 그대로 사용 → temp/uuid·thumbnails/uuid·metrics.id·/r/uuid 가 단일 trace id
/// 로 묶인다.
///
/// orphan 정책:
///   * temp/ : R2 lifecycle 1일 자동 삭제 — 분석 실패해도 깨끗
///   * thumbnails/ : 영구 — 단, 분석 성공 케이스에만 업로드되므로 orphan 0
class FaceMetadataClient {
  static const _kAnalyzePath = '/analyze';
  static const _kAnalyzeTimeout = Duration(seconds: 30);

  static String get _apiBase =>
      dotenv.env['FACE_META_API_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'http://localhost:8000';

  final R2Uploader _uploader;
  final http.Client _http;
  final Uuid _uuid;

  FaceMetadataClient({
    R2Uploader? uploader,
    http.Client? httpClient,
    Uuid? uuid,
  })  : _uploader = uploader ?? R2Uploader(),
        _http = httpClient ?? http.Client(),
        _uuid = uuid ?? const Uuid();

  /// 전체 파이프라인 실행. analyze 실패 → 예외, thumbnail 단계 실패 → 로그만
  /// (이미 analyze 결과는 받았으므로 사용자에겐 metadata 반환, thumbnail null).
  Future<FaceMetadata> analyze(File originalImage) async {
    final originalBytes = await originalImage.readAsBytes();
    final uuid = _uuid.v4();

    // ── 1) 720px → temp/ 업로드 ────────────────────────────────────────────
    final wide = await ImageResizer.resizeToWidth(originalBytes, width: 720);
    final tempUpload = await _uploader.upload(
      prefix: 'temp',
      uuid: uuid,
      bytes: wide,
    );

    // ── 2) Python /analyze 호출 ───────────────────────────────────────────
    // HMAC token + key 를 헤더로 전달 — Worker 가 presign 발급시 함께 발행.
    // uuid 는 응답 파싱 시 FaceMetadata 에 그대로 주입 (서버는 모름).
    final metadata = await _callAnalyze(
      tempUpload.publicUrl,
      uuid: uuid,
      token: tempUpload.token,
      key: tempUpload.key,
    );

    // ── 3) 분석 성공 → 200×200 얼굴 중심 square crop thumbnail 업로드 ────
    // (실패해도 metadata 는 반환 — orphan-zero 정책: 실패 시 thumbnail null)
    String? thumbnailUrl;
    String? thumbnailKey;
    try {
      final small = await ImageResizer.faceCenterSquareCrop(
        originalImage,
        outSize: 200,
      );
      final thumbUpload = await _uploader.upload(
        prefix: 'thumbnails',
        uuid: uuid,
        bytes: small,
      );
      thumbnailUrl = thumbUpload.publicUrl.toString();
      thumbnailKey = thumbUpload.key;
    } catch (e) {
      // ignore: avoid_print
      print('[FaceMetadataClient] thumbnail upload failed (non-fatal): $e');
    }

    return metadata.copyWith(
      thumbnailUrl: thumbnailUrl,
      thumbnailKey: thumbnailKey,
    );
  }

  Future<FaceMetadata> _callAnalyze(
    Uri imageUrl, {
    required String uuid,
    String? token,
    required String key,
  }) async {
    final headers = <String, String>{
      'content-type': 'application/json',
      'x-face-key': key,
    };
    if (token != null) headers['x-face-token'] = token;

    final res = await _http
        .post(
          Uri.parse('$_apiBase$_kAnalyzePath'),
          headers: headers,
          body: jsonEncode({'image_url': imageUrl.toString()}),
        )
        .timeout(_kAnalyzeTimeout);

    if (res.statusCode != 200) {
      throw FaceAnalyzeException(
        'analyze failed: ${res.statusCode} ${res.body}',
        statusCode: res.statusCode,
      );
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return FaceMetadata.fromJson(body, uuid: uuid);
  }

  /// 외부 호출자가 진행도 표시 등 위해 직접 사용할 수 있는 building block.
  Future<Uint8List> resizeForUpload(File file, {required int width}) async {
    final bytes = await file.readAsBytes();
    return ImageResizer.resizeToWidth(bytes, width: width);
  }
}

class FaceAnalyzeException implements Exception {
  final String message;
  final int? statusCode;
  FaceAnalyzeException(this.message, {this.statusCode});
  @override
  String toString() => 'FaceAnalyzeException($statusCode): $message';
}
