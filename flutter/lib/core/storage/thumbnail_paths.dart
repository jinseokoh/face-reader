import 'dart:io';

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
  static Future<File?> resolveFile(String? thumbnailPath) async {
    if (thumbnailPath == null || thumbnailPath.isEmpty) return null;
    final docs = _cachedDocsPath ??
        (await getApplicationDocumentsDirectory()).path;
    _cachedDocsPath ??= docs;
    return File('$docs/${_basenameOnly(thumbnailPath)}');
  }

  /// sync resolve — widget build 안에서 사용. [initCache] 가 await 안 됐으면 null.
  static File? resolveFileSync(String? thumbnailPath) {
    if (thumbnailPath == null || thumbnailPath.isEmpty) return null;
    final docs = _cachedDocsPath;
    if (docs == null) return null;
    return File('$docs/${_basenameOnly(thumbnailPath)}');
  }

  /// 절대경로면 마지막 `/` 뒤만 추출. 이미 filename 이면 그대로.
  static String _basenameOnly(String path) {
    final slashIdx = path.lastIndexOf('/');
    return slashIdx == -1 ? path : path.substring(slashIdx + 1);
  }
}
