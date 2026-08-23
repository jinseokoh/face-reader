import 'dart:io';

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path_provider/path_provider.dart';

/// 관상 thumbnail 의 절대→상대 경로 마이그레이션 helper.
///
/// **저장 규칙** — `report.thumbnailPath` 에는 filename 만 박는다
/// (e.g. `'{uuid}.jpg'`). 절대경로 박으면 iOS sandbox UUID 회전 / Android
/// applicationId 변경 / 단순 reinstall 마다 stale 되어 사진이 안 보인다.
///
/// **읽기 규칙** — 항상 [resolveFileSync] (또는 [resolveFile]) 로 현재 sandbox
/// 의 documents dir 와 조립한 File 을 얻는다. 절대경로가 들어와도 basename 만
/// 뽑아 같은 documents dir 와 재조립 — 옛 Hive entry 도 silent migrate.
///
/// **부트스트랩** — `main()` 에서 `runApp` 전에 `await ThumbnailPaths.initCache()`
/// 한 번 호출. 이후 sync 컨텍스트 (widget build) 에서 [resolveFileSync] 사용 가능.
class ThumbnailPaths {
  ThumbnailPaths._();

  static String? _cachedDocsPath;

  /// `main()` 에서 `runApp` 전에 await. 이후 모든 sync resolve 가 작동.
  static Future<void> initCache() async {
    final dir = await getApplicationDocumentsDirectory();
    _cachedDocsPath = dir.path;
  }

  /// async resolve — initCache 호출 안 됐어도 작동. widget build 밖에서 사용.
  static Future<File?> resolveFile(String? fileName) async {
    if (fileName == null || fileName.isEmpty) return null;
    final docs = _cachedDocsPath ??
        (await getApplicationDocumentsDirectory()).path;
    _cachedDocsPath ??= docs;
    return File('$docs/${_basenameOnly(fileName)}');
  }

  /// sync resolve — widget build 안에서 사용. [initCache] 가 await 안 됐으면 null.
  static File? resolveFileSync(String? fileName) {
    if (fileName == null || fileName.isEmpty) return null;
    final docs = _cachedDocsPath;
    if (docs == null) return null;
    return File('$docs/${_basenameOnly(fileName)}');
  }

  /// 절대경로면 마지막 `/` 뒤만 추출. 이미 filename 이면 그대로.
  static String _basenameOnly(String path) {
    final slashIdx = path.lastIndexOf('/');
    return slashIdx == -1 ? path : path.substring(slashIdx + 1);
  }

  /// 스윕에서 **지킬** 캐시 파일명 집합. null 이면 스윕 자체를 하지 않는다.
  ///
  /// 로컬 파일은 서버 원본의 캐시라 지워도 대개 손실이 없다. 예외가 하나 있다 —
  /// **아직 못 올린 사진.** 그건 이 기기의 파일이 유일한 사본이다. 그래서
  /// 카드뿐 아니라 대기열([pendingKeys])과 입양 목록([adoptFileNames])도 함께
  /// 본다.
  ///
  /// 셋 다 비어 있으면 "지킬 게 없다" 가 아니라 **"아직 모른다"** 이다 —
  /// 로그아웃이 방금 목록을 비웠거나 서버 복원 전이다. 그 상태에서 지우면
  /// 아직 못 올린 사진의 유일한 사본이 사라지고, 다음 재시도가 "원본이 없다"
  /// 며 키를 버린다. 근거가 없을 때의 정답은 삭제가 아니라 대기다.
  static Set<String>? cacheKeepSet({
    required Iterable<String?> cardKeys,
    required Iterable<String> pendingKeys,
    required Iterable<String> adoptFileNames,
  }) {
    final cards = cardKeys.whereType<String>().toList();
    final pending = pendingKeys.toList();
    final adopt = adoptFileNames.toList();
    if (cards.isEmpty && pending.isEmpty && adopt.isEmpty) return null;
    return {
      for (final k in cards) fileNameForKey(k),
      for (final k in pending) fileNameForKey(k),
      ...adopt,
    };
  }

  /// [keep] 에 없는 캐시 파일(`*.jpg`)을 지운다. 사진 파일명이 키에서 나오므로
  /// 그 집합에 없는 파일은 어떤 카드도 다시 찾지 않는다 — 지우지 않으면 재촬영
  /// 때마다 옛 파일이 그대로 쌓인다. 지워도 손실은 없다 (CDN 에 원본이 있다).
  static Future<int> sweepCache(Set<String> keep) async {
    final docs =
        _cachedDocsPath ?? (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(docs);
    if (!await dir.exists()) return 0;
    var removed = 0;
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.endsWith('.jpg')) continue;
      if (keep.contains(_basenameOnly(entity.path))) continue;
      try {
        await entity.delete();
        removed++;
      } catch (_) {
        // 사용 중이거나 권한 문제 — 다음 실행에서 다시 시도한다.
      }
    }
    return removed;
  }

  /// R2 CDN 공개 read URL. `thumbnailKey`(예: `thumbnails/YYYYMM/{uuid}.jpg`)를
  /// `cdn.facely.kr` base 와 조립. 로컬 thumbnail 파일이 없는 카드(받은 카드·
  /// 결제 궁합 복원 파트너 등)의 이미지 경로.
  /// base 는 `.env` 의 `R2_CDN_BASE` override, 없으면 기본값.
  static const _kCdnDefault = 'https://cdn.facely.kr';

  static String get _cdnBase =>
      dotenv.maybeGet('R2_CDN_BASE')?.trim().replaceAll(RegExp(r'/$'), '') ??
      _kCdnDefault;

  /// 200×200 jpeg bytes → sha256 hex.
  static String hashBytes(Uint8List bytes) => sha256.convert(bytes).toString();

  /// 사진의 소유자 — 키의 첫 칸. 로그인 사용자는 uid, 익명 촬영분은
  /// `anon-{metrics_id}`.
  ///
  /// 사진의 수명이 카드가 아니라 **사람**에게 묶이는 지점이다. 재촬영도 카드
  /// 삭제도 사진을 지우지 않는다 — 지우는 건 탈퇴뿐이고, 그건 이 prefix 를
  /// 통째로 지우는 한 번의 연산이다.
  static String? owner({String? userId, String? metricsId}) {
    if (userId != null && userId.isNotEmpty) return userId;
    if (metricsId != null && metricsId.isNotEmpty) return 'anon-$metricsId';
    return null;
  }

  /// 소유자 + 해시 → R2 object key. **서버 `api.r2.presign.ts` 의 buildKey 와
  /// 같은 규칙이어야 한다** (`thumbnails/{owner}/{sha256}.jpg`).
  ///
  /// 같은 사진을 두 사람이 가져도 객체가 둘이다. dedup 을 일부러 포기한 것 —
  /// 10KB 를 아끼려다 "정확한 참조 계수가 없으면 사진이 죽는" 모델을 샀던 게
  /// 실제 데이터 손실로 돌아왔다.
  static String keyFor(String hash, String owner) =>
      'thumbnails/$owner/$hash.jpg';

  /// 바이트에서 바로 키. 해시가 같으면 키도 같아 재업로드가 멱등하고,
  /// 재촬영은 바이트가 달라 URL 이 바뀌므로 CDN 이 옛 얼굴을 못 내준다.
  static String contentKey(Uint8List bytes, {required String owner}) =>
      keyFor(hashBytes(bytes), owner);

  /// 키에서 로컬 캐시 파일명을 뽑는다. 로컬 파일은 키의 함수이지 별개의
  /// 사실이 아니다 — 키가 바뀌면 파일명도 바뀐다.
  static String fileNameForKey(String key) => _basenameOnly(key);

  /// 키가 가리키는 로컬 캐시 파일. 파일명이 키에서 파생되므로 카드에 경로를
  /// 따로 들고 있을 필요가 없다 — 키가 사진의 유일한 필드다.
  /// [initCache] 가 await 안 됐으면 null (widget build 밖에선 [cacheFile]).
  static File? cacheFileSync(String? thumbnailKey) => thumbnailKey == null
      ? null
      : resolveFileSync(fileNameForKey(thumbnailKey));

  static Future<File?> cacheFile(String? thumbnailKey) async =>
      thumbnailKey == null ? null : resolveFile(fileNameForKey(thumbnailKey));

  /// 키가 익명 소유자 스코프면 그 값 (presign 의 `scope` 인자). 로그인 소유자나
  /// 레거시 키면 null — 그 경우 소유자는 서버가 JWT 에서 읽거나 없다.
  static String? anonScopeOfKey(String key) {
    final parts = key.split('/');
    if (parts.length != 3 || parts[0] != 'thumbnails') return null;
    return parts[1].startsWith('anon-') ? parts[1] : null;
  }

  /// 내용 주소 키에서 sha256 hex 를 되뽑는다 (presign 요청용).
  /// 내용 주소가 아닌 키면 null — 그 키는 바이트에서 다시 계산해야 한다.
  static String? hashFromKey(String key) {
    final name = _basenameOnly(key);
    final dot = name.lastIndexOf('.');
    final h = dot == -1 ? name : name.substring(0, dot);
    return RegExp(r'^[0-9a-f]{64}$').hasMatch(h) ? h : null;
  }

  static String? cdnUrl(String? thumbnailKey) {
    if (thumbnailKey == null || thumbnailKey.isEmpty) return null;
    final key =
        thumbnailKey.startsWith('/') ? thumbnailKey.substring(1) : thumbnailKey;
    return '$_cdnBase/$key';
  }
}
