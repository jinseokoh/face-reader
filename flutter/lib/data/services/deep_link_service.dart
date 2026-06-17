import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// `https://facely.kr/r/{id}` (관상·궁합) · `/g/{teamId}` (교감도 그룹 초대)
/// universal/app link 수신.
///
/// `/r/{id}` 의 `{id}` 는:
///   - 단일 UUID 36자       → 관상 카드 (`SoloShareLink`)
///   - `{uuidA}~{uuidB}` 73자 → 궁합 카드 (`CompatShareLink`)
/// `/g/{teamId}` 단일 UUID → 그룹 초대 (`TeamJoinShareLink`).
///
/// SEP 은 `PAIR_SEP = "~"` — Worker `app/lib/share-id.ts` 의 같은 상수와 일치.
/// 변경 시 양쪽 동시 PR.
///
/// cold start (`getInitialLink`) + warm (`uriLinkStream`) 양쪽을 같은
/// handler 로 처리. 라우팅 (ReportPage / CompatReportPage navigate) 은 stream
/// 구독자가 책임.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  static const String _host = 'facely.kr';
  static const String pairSep = '~';
  static final RegExp _uuidRe = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  final _appLinks = AppLinks();
  final _shareLinkController = StreamController<ShareLink>.broadcast();

  Stream<ShareLink> get shareLinkStream => _shareLinkController.stream;

  /// cold-start 시 MainApp 이 build 되기 전에 받은 link 를 버리지 않게 caching.
  /// MainApp 의 initState 가 subscription 등록 직후 [consumePending] 으로 회수.
  ShareLink? _pending;
  ShareLink? get pendingLink => _pending;
  void consumePending() => _pending = null;

  StreamSubscription<Uri>? _sub;

  Future<void> initialize() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (e, st) {
      debugPrint('[DeepLink] initialUri error: $e\n$st');
    }
    _sub = _appLinks.uriLinkStream.listen(
      _handle,
      onError: (Object e, StackTrace st) =>
          debugPrint('[DeepLink] stream error: $e\n$st'),
    );
  }

  void _handle(Uri uri) {
    debugPrint('[DeepLink] received: $uri');

    // 카카오 메시지 '참여하기'의 앱 직접 실행 — `kakao{appkey}://kakaolink?g={teamId}`.
    // 카톡 인앱 브라우저를 거치지 않고 앱을 바로 띄운다 (Link.androidExecutionParams
    // / iosExecutionParams). 그룹 합류는 https `/g/` 와 동일하게 TeamJoinShareLink 로.
    if (uri.scheme.startsWith('kakao') && uri.host == 'kakaolink') {
      final teamId = uri.queryParameters['g'];
      if (teamId != null && _uuidRe.hasMatch(teamId)) {
        _emit(TeamJoinShareLink(teamId: teamId.toLowerCase()));
      } else {
        debugPrint('[DeepLink] kakaolink missing/bad g param: $uri');
      }
      return;
    }

    if (uri.host != _host) return;
    final segs = uri.pathSegments;
    if (segs.isEmpty) return;

    // 2-seg `/g/{teamId}` 또는 3-seg `/g/{teamId}/open` (CTA bridge) — 교감도
    // 그룹 초대 (P3). App Link 검증 상태에선 OS 가 `/open` 까지 앱으로 직접
    // 라우팅하므로 `/r/` 와 동일하게 3-seg 도 받아야 화면 전환이 된다.
    if (segs[0] == 'g') {
      if (segs.length == 3 && segs[2] != 'open') return;
      if (segs.length != 2 && segs.length != 3) return;
      final teamId = segs[1];
      if (!_uuidRe.hasMatch(teamId)) {
        debugPrint('[DeepLink] malformed uuid in /g/$teamId');
        return;
      }
      _emit(TeamJoinShareLink(teamId: teamId.toLowerCase()));
      return;
    }

    // 2-seg `/r/{id}` (readable preview) or 3-seg `/r/{id}/open` (CTA bridge).
    // 둘 다 같은 SoloShareLink/CompatShareLink emit — Flutter 입장에서 동일
    // 라우팅. open sub-path 는 Safari same-URL guard 회피용 web 측 trick 일
    // 뿐 native handler 에선 구분 의미 없음.
    if (segs[0] != 'r') return;
    if (segs.length == 3 && segs[2] != 'open') return;
    if (segs.length != 2 && segs.length != 3) return;

    final id = segs[1];
    final parts = id.split(pairSep);
    if (parts.isEmpty || parts.length > 2) return;
    for (final p in parts) {
      if (!_uuidRe.hasMatch(p)) {
        debugPrint('[DeepLink] malformed uuid in /r/$id');
        return;
      }
    }

    final link = parts.length == 2
        ? CompatShareLink(uuidA: parts[0], uuidB: parts[1])
        : SoloShareLink(uuid: parts[0]);
    _emit(link);
  }

  /// 구독자(MainApp)가 이미 있으면 stream 으로 즉시 전달만 한다. _pending 은
  /// **cold-start 시 MainApp build 이전에 도착한 링크**를 버리지 않으려는
  /// 1회용 버퍼이므로, 구독자가 없을 때만 채운다. warm 흐름에서도 _pending 을
  /// 세팅하면 그 값이 계속 남아, X 로 닫은 뒤 MainApp state 가 재생성되며
  /// initState 가 stale _pending 을 재push → 같은 화면 2장 뜨는 버그.
  void _emit(ShareLink link) {
    debugPrint('[DeepLink] emit $link');
    if (_shareLinkController.hasListener) {
      _shareLinkController.add(link);
    } else {
      _pending = link;
    }
  }

  void dispose() {
    _sub?.cancel();
    _shareLinkController.close();
  }
}

/// 받은 link 의 종류 분기 — 구독자가 sealed switch 로 안전하게 라우팅.
sealed class ShareLink {
  const ShareLink();
}

final class SoloShareLink extends ShareLink {
  final String uuid;
  const SoloShareLink({required this.uuid});

  @override
  String toString() => 'SoloShareLink($uuid)';
}

final class CompatShareLink extends ShareLink {
  final String uuidA;
  final String uuidB;
  const CompatShareLink({required this.uuidA, required this.uuidB});

  @override
  String toString() => 'CompatShareLink($uuidA, $uuidB)';
}

/// `/g/{teamId}` — 교감도 그룹 초대 (P3). 구독자가 TeamJoinScreen 으로 라우팅.
final class TeamJoinShareLink extends ShareLink {
  final String teamId;
  const TeamJoinShareLink({required this.teamId});

  @override
  String toString() => 'TeamJoinShareLink($teamId)';
}
