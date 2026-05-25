import 'package:dio/dio.dart';
import 'package:facely/core/http/http_client.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 약관/개인정보 md 를 facely.kr (react/public) 에서 fetch — react 와 단일 SSOT.
/// 메모리 캐시 → 같은 세션 내 두번째 open 은 즉시.
class LegalDocService {
  LegalDocService(this._dio);

  static const _termsUrl = 'https://facely.kr/terms.md';
  static const _privacyUrl = 'https://facely.kr/privacy.md';

  final Dio _dio;
  final Map<String, String> _cache = {};

  Future<String> fetchTerms() => _fetch(_termsUrl);
  Future<String> fetchPrivacy() => _fetch(_privacyUrl);

  Future<String> _fetch(String url) async {
    final cached = _cache[url];
    if (cached != null) return cached;
    final res = await _dio.get<String>(
      url,
      options: Options(responseType: ResponseType.plain),
    );
    final body = res.data ?? '';
    _cache[url] = body;
    return body;
  }
}

final legalDocServiceProvider = Provider<LegalDocService>((ref) {
  return LegalDocService(ref.watch(dioProvider));
});
