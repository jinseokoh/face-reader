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

  /// 200×200 jpeg bytes → R2 object key. **서버 `api.r2.presign.ts` 의
  /// buildKey 와 같은 규칙이어야 한다** (`thumbnails/{앞2자}/{sha256}.jpg`).
  ///
  /// 내용 주소라 같은 바이트는 같은 키다. 재업로드가 멱등하고, 재촬영은 바이트가
  /// 달라 URL 자체가 바뀌므로 CDN 캐시가 옛 얼굴을 내줄 수 없다.
  static String contentKey(Uint8List bytes) {
    final h = sha256.convert(bytes).toString();
    return 'thumbnails/${h.substring(0, 2)}/$h.jpg';
  }

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
