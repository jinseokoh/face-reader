import 'dart:io';

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart' hide Gender;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// `react/` share host (facely.kr) 와 1:1 계약 — UUID 기반, Worker 미경유.
///
/// publishSolo / publishCompat:
///   1) 해당 report 의 supabaseId 보장 (없으면 SupabaseService.saveMetrics 로 생성)
///   2) PNG bytes 를 임시 파일로 저장
///   3) share_plus 로 OS share sheet 호출 — text 에 https://{host}/r/{uuid}
///      또는 https://{host}/r/{uuidA}~{uuidB}, 첨부에 PNG
///
/// 받는 사람의 link 해석은 Worker SSR (`GET /r/:id`) 가 PAIR_SEP("~") split
/// 으로 1·2 UUID 케이스 모두 처리 (HOW-IT-WORKS §3.4 / §4.1).
class SharePublisher {
  static final SharePublisher instance = SharePublisher._();
  /// 궁합 URL 의 두 UUID 를 묶는 separator — Worker `app/lib/share-id.ts`
  /// 의 `PAIR_SEP` 와 동일 값 유지. 변경 시 양쪽 동시 PR.
  static const String pairSep = '~';

  /// thumbnailKey 가 없을 때 KakaoLink 카드의 fallback 이미지.
  static const String _fallbackImage =
      'https://cdn.facely.kr/assets/share-logo.png';

  SharePublisher._();

  /// R2 CDN base — KakaoLink Feed `imageUrl` 조립에 사용.
  String get _cdnBase =>
      dotenv.env['R2_CDN_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://cdn.facely.kr';

  /// `.env` 의 WEBAPP_BASE — Worker 의 WEBAPP_BASE 와 동일 값. fallback 'https://facely.kr'.
  String get _hostBase =>
      dotenv.env['WEBAPP_BASE']?.trim().replaceAll(RegExp(r'/$'), '') ??
      'https://facely.kr';

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

  /// 궁합 공유 — `/r/{A}~{B}` 두 UUID 묶음. 양쪽 metrics row 가 publish 된 상태
  /// 여야 Worker SSR 이 두 행 fetch 가능.
  Future<void> publishCompatViaKakao({
    required FaceReadingReport my,
    required FaceReadingReport album,
    required String title,
    required String description,
  }) async {
    final myId = await _ensureSupabaseId(my);
    final albumId = await _ensureSupabaseId(album);
    await _sendKakaoFeed(
      title: title,
      description: description,
      // og:image 는 Worker SSR 이 my thumbnail 을 사용. 카톡 안 카드 preview 도
      // my thumbnail (R2 직통) — 두 사람 합성은 Worker 책임이고 KakaoLink 는 단일 이미지.
      imageUrl: _resolveImageUrl(my.thumbnailKey),
      webUrl: '$_hostBase/r/$myId$pairSep$albumId',
      tag: 'compat',
    );
  }

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

  /// Solo 공유 — 카카오톡 친구 또는 채팅방에 KakaoLink Feed 발송.
  Future<void> publishSoloViaKakao({
    required FaceReadingReport report,
    required String title,
    required String description,
  }) async {
    final uuid = await _ensureSupabaseId(report);
    await _sendKakaoFeed(
      title: title,
      description: description,
      imageUrl: _resolveImageUrl(report.thumbnailKey),
      webUrl: '$_hostBase/r/$uuid',
      tag: 'solo',
    );
  }

  // ─── 카카오 공유 (KakaoLink Feed) ────────────────────────────────────────
  //
  // 이미지 첨부 share_plus 와 별개 경로. 카톡 안에서 풍부한 link preview 카드
  // (제목·설명·이미지·CTA 버튼) 를 보여주려면 KakaoLink Feed template 필수.
  // imageUrl 은 R2 영구 thumbnail (`cdn.facely.kr/{thumbnailKey}`) 또는 fallback.

  /// share 시점에 metrics row 가 반드시 Supabase 에 존재하도록 보장.
  ///
  /// 로컬 report.supabaseId 만으로는 충분하지 않다 — analyze 시점에 UUID 가
  /// 박혀도 demographic_confirm 의 fire-and-forget saveMetrics 가 (RLS·네트워크)
  /// 로 실패한 케이스가 있을 수 있고, 그러면 받는 사람의 /r/{uuid} 가 404 (공유
  /// 카드를 찾을 수 없습니다) 로 빠진다. saveMetrics 는 upsert 라 호출 비용이
  /// 낮으므로 share 마다 한 번 더 친다.
  Future<String> _ensureSupabaseId(FaceReadingReport report) async {
    final id = await SupabaseService().saveMetrics(report);
    report.supabaseId = id;
    return id;
  }

  String _resolveImageUrl(String? thumbnailKey) {
    if (thumbnailKey != null && thumbnailKey.isNotEmpty) {
      return '$_cdnBase/$thumbnailKey';
    }
    return _fallbackImage;
  }

  Future<void> _sendKakaoFeed({
    required String title,
    required String description,
    required String imageUrl,
    required String webUrl,
    required String tag,
  }) async {
    final link = Link(
      webUrl: Uri.parse(webUrl),
      mobileWebUrl: Uri.parse(webUrl),
    );
    final template = FeedTemplate(
      content: Content(
        title: title,
        description: description,
        imageUrl: Uri.parse(imageUrl),
        link: link,
      ),
      buttons: [
        Button(title: '결과 보기', link: link),
      ],
    );
    debugPrint('[SharePublisher.kakao] $tag url=$webUrl image=$imageUrl');
    await ShareClient.instance.shareDefault(template: template);
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
