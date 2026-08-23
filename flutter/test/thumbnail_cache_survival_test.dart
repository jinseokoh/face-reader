// 로그아웃 → 로그인 왕복에 사진이 살아남는가.
//
// 로그아웃은 계정 각인 불변식에 따라 로컬 history 를 통째로 비운다. 그 직후
// 캐시 스윕이 "지킬 카드가 하나도 없다" 를 "다 지워도 된다" 로 읽으면, 아직
// R2 에 못 올린 사진의 **유일한 사본**이 사라지고 다음 재시도가 키까지 버린다.
// 그 얼굴은 서버에도 기기에도 남지 않는다.

import 'dart:typed_data';

import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const uid = '11111111-2222-3333-4444-555555555555';
  final keyA = ThumbnailPaths.contentKey(Uint8List.fromList([1]), owner: uid);
  final keyB = ThumbnailPaths.contentKey(Uint8List.fromList([2]), owner: uid);

  group('캐시 스윕 keep 집합', () {
    test('카드가 가진 키의 파일은 지킨다', () {
      final keep = ThumbnailPaths.cacheKeepSet(
        cardKeys: [keyA],
        pendingKeys: const [],
        adoptFileNames: const [],
      );
      expect(keep, contains(ThumbnailPaths.fileNameForKey(keyA)));
      expect(keep, isNot(contains(ThumbnailPaths.fileNameForKey(keyB))));
    });

    test('아직 못 올린 사진을 지킨다 — 기기의 파일이 유일한 사본이다', () {
      final keep = ThumbnailPaths.cacheKeepSet(
        cardKeys: [keyA],
        pendingKeys: [keyB],
        adoptFileNames: const [],
      );
      expect(keep, contains(ThumbnailPaths.fileNameForKey(keyB)));
    });

    test('입양 대기 중인 옛 파일명도 지킨다', () {
      final keep = ThumbnailPaths.cacheKeepSet(
        cardKeys: const [],
        pendingKeys: const [],
        adoptFileNames: const ['legacy-uuid.jpg'],
      );
      expect(keep, contains('legacy-uuid.jpg'));
    });

    test('키 없는 카드는 keep 에 기여하지 않는다', () {
      final keep = ThumbnailPaths.cacheKeepSet(
        cardKeys: [null, keyA],
        pendingKeys: const [],
        adoptFileNames: const [],
      );
      expect(keep, {ThumbnailPaths.fileNameForKey(keyA)});
    });

    test('로그아웃 직후처럼 셋 다 비면 스윕하지 않는다 (null)', () {
      // 이 케이스가 사진을 잃던 지점 — "지킬 게 없다" 가 아니라 "아직 모른다".
      expect(
        ThumbnailPaths.cacheKeepSet(
          cardKeys: const [],
          pendingKeys: const [],
          adoptFileNames: const [],
        ),
        isNull,
      );
    });

    test('카드는 비었지만 대기열이 남았으면 스윕하되 그 파일은 지킨다', () {
      // 로그아웃이 Hive 를 비워도 prefs 의 대기열은 남는다. 재로그인 후
      // rehydrate 가 행을 되살리면 이 파일이 그 행의 사진이 된다.
      final keep = ThumbnailPaths.cacheKeepSet(
        cardKeys: const [],
        pendingKeys: [keyA],
        adoptFileNames: const [],
      );
      expect(keep, {ThumbnailPaths.fileNameForKey(keyA)});
    });
  });

  group('소유자가 바뀌어도 캐시 파일은 그대로', () {
    test('익명 → 로그인 재지정에 파일 이관이 없다', () {
      final bytes = Uint8List.fromList([3, 3, 3]);
      final anon = ThumbnailPaths.contentKey(bytes, owner: 'anon-m1');
      final mine = ThumbnailPaths.contentKey(bytes, owner: uid);
      expect(anon, isNot(mine));
      // 파일명은 해시라 같다 — 키만 갈아끼우면 화면이 계속 같은 파일을 찾는다.
      expect(
        ThumbnailPaths.fileNameForKey(anon),
        ThumbnailPaths.fileNameForKey(mine),
      );
    });
  });
}
