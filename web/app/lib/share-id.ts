/**
 * URL path 의 `:id` 를 1 또는 2 UUID 로 split.
 *
 *   /r/{uuid}              → 관상 (1 UUID)
 *   /r/{uuidA}~{uuidB}     → 궁합 (2 UUID)
 *
 * `PAIR_SEP` 은 RFC 3986 unreserved (percent-encode 안 됨) + UUID 표준 형태에
 * 없는 문자. 향후 변경 필요 시 이 한 곳만 수정.
 */
export const PAIR_SEP = "~";

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * 잘못된 형식이면 null. 호출자는 404 처리.
 * 정상이면 길이 1 또는 2 의 UUID 배열 반환.
 */
export function parsePairId(raw: string | undefined): string[] | null {
  if (!raw) return null;
  const parts = raw.split(PAIR_SEP);
  if (parts.length < 1 || parts.length > 2) return null;
  for (const p of parts) {
    if (!UUID_RE.test(p)) return null;
  }
  return parts;
}
