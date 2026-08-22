// 썸네일 업로드 계약 테스트.
// 키는 내용 주소 — 같은 바이트는 같은 키, 다른 바이트는 다른 URL. 서버
// (`api.r2.presign.ts`)의 buildKey 와 같은 규칙이어야 한다.
// 이미 있는 객체면 서버가 409 를 주고, 그건 "같은 바이트가 저장돼 있다" 는
// 뜻이므로 클라이언트는 성공으로 취급한다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/data/services/r2_uploader.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 빈 바이트열의 sha256 — 외부에서 검증 가능한 표준 벡터.
const _kEmptySha256 =
    'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

void main() {
  // R2Uploader 가 presign host 를 dotenv 에서 읽는다. MockClient 가 모든 요청을
  // 가로채므로 값 자체는 의미 없지만 로드는 돼 있어야 한다.
  setUpAll(() => dotenv.loadFromString(envString: 'WEBAPP_BASE=https://test.local'));

  group('내용 주소 키', () {
    test('sha256 표준 벡터로 키가 조립된다 (앞 2자 샤딩)', () {
      expect(
        ThumbnailPaths.contentKey(Uint8List(0)),
        'thumbnails/e3/$_kEmptySha256.jpg',
      );
    });

    test('로컬 파일명은 키의 basename 이다', () {
      final key = ThumbnailPaths.contentKey(Uint8List.fromList([1, 2, 3]));
      expect(ThumbnailPaths.fileNameForKey(key), key.split('/').last);
      expect(ThumbnailPaths.fileNameForKey(key), endsWith('.jpg'));
    });

    test('바이트가 다르면 키가 다르다 — 재촬영이 캐시를 밟지 않는다', () {
      final a = ThumbnailPaths.contentKey(Uint8List.fromList([1, 2, 3]));
      final b = ThumbnailPaths.contentKey(Uint8List.fromList([1, 2, 4]));
      expect(a, isNot(b));
    });
  });

  group('R2Uploader', () {
    final bytes = Uint8List.fromList([9, 9, 9]);

    test('hash 를 presign 에 싣고, 200 이면 Cache-Control 과 함께 PUT 한다', () async {
      Map<String, dynamic>? presignBody;
      http.Request? put;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          presignBody = jsonDecode(req.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'uploadUrl': 'https://r2.example/put',
              'publicUrl': 'https://cdn.example/thumbnails/ab/x.jpg',
              'key': 'thumbnails/ab/x.jpg',
              'cacheControl': 'public, max-age=31536000, immutable',
            }),
            200,
          );
        }
        put = req;
        return http.Response('', 200);
      });

      final res = await R2Uploader(client: client).upload(
        prefix: 'thumbnails',
        hash: 'abc123',
        bytes: bytes,
      );

      expect(presignBody?['hash'], 'abc123');
      expect(presignBody?.containsKey('uuid'), isFalse);
      expect(put, isNotNull);
      expect(put!.headers['cache-control'], 'public, max-age=31536000, immutable');
      expect(res.key, 'thumbnails/ab/x.jpg');
      expect(res.alreadyExists, isFalse);
    });

    test('409 면 PUT 하지 않고 서버가 준 키를 성공으로 돌려준다', () async {
      var putCount = 0;
      final client = MockClient((req) async {
        if (req.method == 'POST') {
          return http.Response(
            jsonEncode({
              'key': 'thumbnails/ab/x.jpg',
              'publicUrl': 'https://cdn.example/thumbnails/ab/x.jpg',
              'exists': true,
            }),
            409,
          );
        }
        putCount++;
        return http.Response('', 200);
      });

      final res = await R2Uploader(client: client).upload(
        prefix: 'thumbnails',
        hash: 'abc123',
        bytes: bytes,
      );

      expect(putCount, 0);
      expect(res.alreadyExists, isTrue);
      expect(res.key, 'thumbnails/ab/x.jpg');
      expect(res.uploadUrl, isNull);
    });

    test('presign 이 실패하면 예외 — 호출부가 대기열에 남긴다', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      await expectLater(
        R2Uploader(client: client)
            .upload(prefix: 'thumbnails', hash: 'abc123', bytes: bytes),
        throwsA(isA<R2UploadException>()),
      );
    });
  });
}
