import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

/// face.kr 의 universal/app link 진입 처리.
///
/// 현재 단계: 들어온 URI 의 path segment 만 추출해 stream 으로 흘려준다.
/// 라우팅 (token decode → ReportPage) 은 share host 의 `/api/decode` endpoint
/// 가 추가된 뒤 한 번에 wiring 한다 — 지금은 logging + 단순 path 분리만.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  final _shareTokenController = StreamController<String>.broadcast();

  /// `/r/{token}` 경로로 들어온 token 만 흘려준다.
  Stream<String> get shareTokenStream => _shareTokenController.stream;

  StreamSubscription<Uri>? _sub;

  /// app boot 시 한 번 호출. cold start (initialUri) + warm (uriLinkStream)
  /// 양쪽을 같은 handler 로 처리.
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
    final segs = uri.pathSegments;
    if (uri.host == 'face.kr' && segs.length == 2 && segs[0] == 'r') {
      final token = segs[1];
      debugPrint('[DeepLink] share token = $token');
      _shareTokenController.add(token);
    }
  }

  void dispose() {
    _sub?.cancel();
    _shareTokenController.close();
  }
}
