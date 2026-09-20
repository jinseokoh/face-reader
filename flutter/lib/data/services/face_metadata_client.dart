import 'dart:convert';
import 'dart:io';

import 'package:facely/data/services/image_resizer.dart';
import 'package:facely/domain/models/face_metadata.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

/// 나이·성별·인종 추정 클라이언트 — 워커 `POST {WEBAPP_BASE}/api/analyze` 한 번.
///
/// 흐름:
///   1) UUID v4 한 번 발급 — 이후 metrics.id·share link 전부 같은 값
///   2) 정면 사진에서 384px 정사각 얼굴 크롭 (ML Kit 박스, 사방 여유 0.2 —
///      서버 CROP_MARGIN·MiVOLO 입력 규격과 동일, python/README.md)
///   3) multipart 로 워커에 POST → 워커가 HMAC 을 붙여 python 에 중계
///      → {age, gender, ethnicity, ageModel}
///
/// 예전엔 presign → R2 temp/ PUT → python 이 다시 다운로드, 왕복 4번이었다.
/// 지금은 1번이고 앱에 비밀키가 없다 (인증은 워커가 한다). R2 temp/ 는 더
/// 쓰지 않는다 — 스토어의 옛 앱이 전부 갱신되면 서버의 image_url 경로도 지운다.
///
/// 발급한 uuid 는 caller 가 [FaceReadingReport.supabaseId] 에 즉시 assign 해야
/// 한다. 그래야 publish 시점에 SupabaseService.saveMetrics 가 metrics.id 로
/// 그대로 사용 → metrics.id·/r/uuid 가 단일 trace id 로 묶인다.
///
/// **썸네일은 여기서 올리지 않는다.** 사용자가 정보 확인을 마치고 카드를 저장할
/// 때 올린다 — 여기서 올리면 확인 화면에서 취소한 사람의 얼굴 이미지가 참조하는
/// 행 없이 R2 에 영구히 남는다 (소유자가 없어 탈퇴·90일 정리에도 안 걸린다).
class FaceMetadataClient {
  static const _kAnalyzePath = '/api/analyze';
  static const _kAnalyzeTimeout = Duration(seconds: 30);

  /// 추정용 얼굴 크롭 규격 — 서버 `CROP_MARGIN`(0.2)·MiVOLO 입력(384)과 같다.
  /// 웹 JoinWizard 의 FACE_CROP_PX / FACE_CROP_MARGIN 과도 같은 값.
  static const int kFaceCropPx = 384;
  static const double kFaceCropMargin = 0.2;

  /// ML Kit 가 얼굴을 못 잡았을 때의 대안 — 720px 전체 사진을 보내고 서버가 검출.
  static const int _kFallbackWidth = 720;

  /// `.env` 의 WEBAPP_BASE — 워커 호스트. R2Uploader·SharePublisher 와 같은 값.
  static String get _apiBase =>
      dotenv.env['WEBAPP_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://facely.kr';

  final http.Client _http;
  final Uuid _uuid;

  FaceMetadataClient({
    http.Client? httpClient,
    Uuid? uuid,
  })  : _http = httpClient ?? http.Client(),
        _uuid = uuid ?? const Uuid();

  Future<FaceMetadata> analyze(File originalImage) async {
    final originalBytes = await originalImage.readAsBytes();
    final uuid = _uuid.v4();

    // ── 1) 384px 얼굴 크롭. ML Kit 검출 실패(박스 없음)면 이미지 중앙 crop 이
    //       되므로 그때는 서버 검출로 돌린다 — 잘못 자른 크롭을 얼굴로 믿게
    //       하지 않는다.
    Uint8List payload;
    bool faceCrop;
    final crop = await ImageResizer.faceCenterSquareCropDetected(
      originalBytes,
      mlKitPath: originalImage.path,
      outSize: kFaceCropPx,
      padding: kFaceCropMargin,
    );
    if (crop != null) {
      payload = crop;
      faceCrop = true;
    } else {
      payload = await ImageResizer.resizeToWidth(originalBytes, width: _kFallbackWidth);
      faceCrop = false;
    }
    debugPrint('[FaceMetadataClient] uuid=$uuid faceCrop=$faceCrop bytes=${payload.length}');

    // ── 2) 워커에 multipart POST ──────────────────────────────────────────
    final req = http.MultipartRequest('POST', Uri.parse('$_apiBase$_kAnalyzePath'))
      ..files.add(http.MultipartFile.fromBytes('image', payload, filename: 'face.jpg'))
      ..fields['face_crop'] = faceCrop ? '1' : '0';
    final streamed = await _http.send(req).timeout(_kAnalyzeTimeout);
    final res = await http.Response.fromStream(streamed);

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
