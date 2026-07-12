/// Compat 키 = unlocks.partner_id = **상대(album)의 supabaseId 단독**.
///
/// "나"는 항상 단일 isMyFace 라 unlock 식별에 내 id 가 필요 없다. 키에서 내
/// id 를 빼면, **내 사진을 바꿔도(= 새 supabaseId) 같은 상대의 unlock 이 그대로
/// 유지**된다(재결제 없음). 표시 점수는 현재 내 관상으로 매번 재계산되므로
/// 내 쪽은 live, 상대 body 는 unlocks.partner_body 로 동결(삭제 보호).
/// unlocks PK 는 (user_id=내 auth uid, partner_id=상대 id) — 상대당 1 unlock.
library;

import 'package:face_engine/domain/models/face_reading_report.dart';

/// 상대(album)의 supabaseId 를 unlocks.partner_id 로 반환. 상대 id 가 null 이면 null.
/// [my] 는 호출부 시그니처 유지를 위해 받되 키에는 쓰지 않는다.
String? tryPairKey(FaceReadingReport my, FaceReadingReport album) {
  return album.supabaseId;
}
