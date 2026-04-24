/// Compat pair_key = my.supabaseId :: album.supabaseId.
///
/// 비대칭(나 × 상대) · 순서 고정. 두 report 모두 supabaseId 가 할당된 뒤에만
/// key 가 만들어짐 — 서버 UUID 를 앵커로 삼아 설치·기기 변경 후에도 unlock
/// 지불이 유효하게 유지된다. Hive local timestamp 기반 key 는 사용하지 않음.
library;

import '../../models/face_reading_report.dart';

/// 두 report 모두 supabaseId 가 있으면 pair_key 반환, 하나라도 null 이면 null.
String? tryPairKey(FaceReadingReport my, FaceReadingReport album) {
  final myId = my.supabaseId;
  final albumId = album.supabaseId;
  if (myId == null || albumId == null) return null;
  return '$myId::$albumId';
}
