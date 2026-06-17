import 'dart:io';
import 'dart:ui' show Rect;

import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:facely/data/services/supabase_service.dart';
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

  SharePublisher._();

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
  /// 궁합 카드 공유 — KakaoLink Feed 발송.
  ///
  /// [compositeCardPng] 은 caller (CompatibilityDetailScreen) 가 off-screen
  /// `_CompatShareCardComposite` 를 RepaintBoundary 로 캡처해 전달. 본 메서드가
  /// Kakao 의 image CDN 으로 업로드해 URL 을 받고 FeedTemplate 에 박는다 —
  /// publishSoloViaKakao 와 동일 패턴.
  Future<void> publishCompatViaKakao({
    required FaceReadingReport my,
    required FaceReadingReport album,
    required String title,
    required String description,
    required Uint8List compositeCardPng,
  }) async {
    final myId = await _ensureSupabaseId(my);
    final albumId = await _ensureSupabaseId(album);
    final webUrl = '$_hostBase/r/$myId$pairSep$albumId';

    final upload =
        await ShareClient.instance.uploadImage(byteData: compositeCardPng);
    final kakaoCdnUrl = upload.infos.original.url;
    debugPrint(
        '[SharePublisher.kakao] compat composite uploaded to kakao cdn=$kakaoCdnUrl');

    await _sendKakaoFeed(
      title: title,
      description: description,
      imageUrl: kakaoCdnUrl,
      webUrl: webUrl,
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

  /// 카카오톡 설치 여부. 호출부가 share 버튼을 누른 사용자에게 미설치 안내를
  /// 띄우거나, 합성 카드 생성 같은 비용 큰 작업을 피하기 위해 사전 체크.
  Future<bool> isKakaoTalkInstalled() =>
      ShareClient.instance.isKakaoTalkSharingAvailable();

  /// Solo 공유 — KakaoLink Feed 발송.
  ///
  /// `compositeCardPng` 가 link preview 의 hero 이미지로 들어간다. 호출부가
  /// Flutter widget tree 를 RepaintBoundary 로 캡처해 PNG bytes 로 전달한다.
  /// 본 메서드가 Kakao 의 image CDN 으로 업로드해 URL 을 받은 뒤 FeedTemplate
  /// 에 박는다 — 우리 R2/Worker 에는 흔적이 남지 않는다.
  ///
  /// 카카오톡 미설치 시 동작은 caller 책임 (사전에 [isKakaoTalkInstalled] 로
  /// 가드하라). 미설치 상태에서 본 메서드를 호출하면 `uploadImage` 가 throw.
  Future<void> publishSoloViaKakao({
    required FaceReadingReport report,
    required String title,
    required String description,
    required Uint8List compositeCardPng,
  }) async {
    final uuid = await _ensureSupabaseId(report);
    final webUrl = '$_hostBase/r/$uuid';

    // 1) PNG bytes → Kakao 의 image CDN (kakao_flutter_sdk_share 2.0 의
    // byteData 직접 업로드 — 임시 파일 안 거침).
    final upload =
        await ShareClient.instance.uploadImage(byteData: compositeCardPng);
    final kakaoCdnUrl = upload.infos.original.url;
    debugPrint(
        '[SharePublisher.kakao] composite uploaded to kakao cdn=$kakaoCdnUrl');

    // 2) 그 URL 을 FeedTemplate imageUrl 로.
    await _sendKakaoFeed(
      title: title,
      description: description,
      imageUrl: kakaoCdnUrl,
      webUrl: webUrl,
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
    debugPrint('[SharePublisher._ensureSupabaseId] report.supabaseId='
        '${report.supabaseId} alias=${report.alias} isMyFace=${report.isMyFace}');
    final id = await SupabaseService().saveMetrics(report);
    report.supabaseId = id;
    debugPrint('[SharePublisher._ensureSupabaseId] resolved id=$id');
    return id;
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

  /// 진실의 방 초대 — 카카오 공유 시트. friends scope 불필요 (받을 친구는
  /// 카톡 안에서 사용자가 직접 고른다). 카톡 미설치면 OS 공유 시트로 fallback.
  /// 받는 사람의 합류 처리(/g/{id} 라우트 + 서버 groups)는 P3 — 현재는 링크 전송까지.
  String teamInviteUrl(String roomId) => '$_hostBase/g/$roomId';

  Future<void> publishTeamInvite({
    required String teamTitle,
    required String roomId,
    Rect? sharePositionOrigin,
  }) async {
    final url = teamInviteUrl(roomId);
    final text =
        '[$teamTitle] 관상학으로 풀어보는 우리 그룹내에서 나랑 가장 케미가 좋은 사람찾기에 참여해 보세요.';
    if (await isKakaoTalkInstalled()) {
      // executionParams: 앱 설치 시 '참여하기' 가 카톡 인앱 브라우저를 거치지 않고
      // 앱을 바로 실행한다 (`kakao{appkey}://kakaolink?g={roomId}`). 미설치면
      // mobileWebUrl 로 fallback. 받는 처리는 DeepLinkService 의 kakaolink 분기.
      final link = Link(
        webUrl: Uri.parse(url),
        mobileWebUrl: Uri.parse(url),
        androidExecutionParams: {'g': roomId},
        iosExecutionParams: {'g': roomId},
      );
      await ShareClient.instance.shareDefault(
        template: TextTemplate(
          text: text,
          link: link,
          buttonTitle: '참여하기',
        ),
      );
    } else {
      // iOS 는 공유 시트(popover) anchor 로 sharePositionOrigin 을 요구한다.
      // 누락 시 PlatformException 으로 시트가 안 뜬다.
      await SharePlus.instance.share(
        ShareParams(
          text: '$text\n$url',
          sharePositionOrigin: sharePositionOrigin,
        ),
      );
    }
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
