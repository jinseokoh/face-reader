/// Compat unlock 키 = **무방향 쌍** — 두 인물의 supabaseId 를 정렬해 `lo~hi`.
///
/// 규칙 하나: "1코인 = 두 사람의 궁합 풀이, 구매자에게 영구" — 내 쌍이든
/// 케미 배틀의 제3자 쌍이든 동일 키 공간을 쓴다 (compatibilities PK =
/// (user_id, a_id, b_id), a<b 정규화). 같은 두 사람은 어디서 만나든 한 번만
/// 결제된다.
///
/// 내 사진 재촬영에도 unlock 이 유지되는 기존 성질은 그대로다 — 로그인
/// 유저의 my-face row id 는 영구 고정(재촬영은 같은 row 덮어쓰기)이라 내
/// supabaseId 가 변하지 않는다.
///
/// 정렬은 소문자 canonical uuid 문자열 비교 — Postgres uuid 비교(바이트순)와
/// 동일한 순서다 (hex 문자 사전순 = 바이트순, 하이픈 위치 동일).
library;

import 'package:face_engine/domain/models/face_reading_report.dart';

/// 정규화된 쌍 id 목록 `[lo, hi]`. 어느 한쪽 id 가 없거나 동일 인물이면 null.
List<String>? tryPairIds(FaceReadingReport a, FaceReadingReport b) {
  final x = a.supabaseId?.toLowerCase();
  final y = b.supabaseId?.toLowerCase();
  if (x == null || y == null || x == y) return null;
  return x.compareTo(y) < 0 ? [x, y] : [y, x];
}

/// unlock 상태 조회용 합성 키 `lo~hi`. [tryPairIds] 가 null 이면 null.
String? tryPairKey(FaceReadingReport a, FaceReadingReport b) {
  final ids = tryPairIds(a, b);
  return ids == null ? null : '${ids[0]}~${ids[1]}';
}
