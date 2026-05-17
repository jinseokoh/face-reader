import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// `https://facely.kr/r/{id}` universal/app link 수신.
///
/// `{id}` 는:
///   - 단일 UUID 36자       → 관상 카드 (`SoloShareLink`)
///   - `{uuidA}~{uuidB}` 73자 → 궁합 카드 (`CompatShareLink`)
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
    if (uri.host != _host) return;
    final segs = uri.pathSegments;
    if (segs.length != 2 || segs[0] != 'r') return;

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
    debugPrint('[DeepLink] emit $link');
    _shareLinkController.add(link);
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
