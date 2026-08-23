/// Compat unlock 키 = **무방향 쌍**. 순서 규칙 하나:
///
///   구매자가 쌍에 포함 → 구매자 카드가 앞
///   포함되지 않음      → uuid 오름차순
///
/// 저장 순서가 곧 표시 순서다. 예전엔 항상 uuid 정렬이라 구매자가 뒤로 갈 수
/// 있었고, 그러면 화면마다 좌우 재배치 규칙을 따로 들고 있어야 했다 — 앱엔
/// 있고 admin 콘솔엔 없어서 같은 궁합이 두 화면에서 다르게 보였다.
///
/// 어느 경우든 **같은 입력이면 같은 키**라 중복 결제 검사는 여전히
/// `(user_id, a_id, b_id)` 한 번이다. 구매자가 포함된 쌍은 구매자 카드가
/// 고정으로 앞이라 순서가 흔들릴 수 없고, 포함되지 않은 쌍(케미 결과표에서
/// 남의 쌍을 사는 경우)은 매트릭스의 (i,j)·(j,i) 어느 칸을 눌러도 uuid 정렬이
/// 같은 키로 모아준다.
///
/// 규칙 하나: "1코인 = 두 사람의 궁합 풀이, 구매자에게 영구" — 내 쌍이든
/// 케미 배틀의 제3자 쌍이든 동일 키 공간을 쓴다
/// (compatibilities PK = (user_id, a_id, b_id)).
///
/// 내 사진 재촬영에도 unlock 이 유지되는 기존 성질은 그대로다 — 로그인
/// 유저의 my-face row id 는 영구 고정(재촬영은 같은 row 덮어쓰기)이라 내
/// supabaseId 가 변하지 않는다.
///
/// 정렬은 소문자 canonical uuid 문자열 비교 — Postgres uuid 비교(바이트순)와
/// 동일한 순서다 (hex 문자 사전순 = 바이트순, 하이픈 위치 동일).
library;

import 'package:face_engine/domain/models/face_reading_report.dart';

/// 정규화된 쌍 id 목록. 어느 한쪽 id 가 없거나 동일 인물이면 null.
///
/// [buyerFaceId] 는 구매자의 my-face supabaseId. 그게 쌍의 한쪽이면 그쪽이
/// 앞으로 온다 — 저장 순서가 화면 순서이므로, 산 사람이 언제나 왼쪽이다.
/// 없거나 쌍에 없으면 uuid 오름차순으로 떨어진다.
List<String>? tryPairIds(
  FaceReadingReport a,
  FaceReadingReport b, {
  String? buyerFaceId,
}) {
  final x = a.supabaseId?.toLowerCase();
  final y = b.supabaseId?.toLowerCase();
  if (x == null || y == null || x == y) return null;
  final buyer = buyerFaceId?.toLowerCase();
  if (buyer != null) {
    if (buyer == x) return [x, y];
    if (buyer == y) return [y, x];
  }
  return x.compareTo(y) < 0 ? [x, y] : [y, x];
}

/// unlock 상태 조회용 합성 키 `a~b`. [tryPairIds] 가 null 이면 null.
String? tryPairKey(
  FaceReadingReport a,
  FaceReadingReport b, {
  String? buyerFaceId,
}) {
  final ids = tryPairIds(a, b, buyerFaceId: buyerFaceId);
  return ids == null ? null : '${ids[0]}~${ids[1]}';
}
