import type { Route } from './+types/api.analyze'

/**
 * POST /api/analyze — 웹 캡처의 DeepFace 추정 프록시.
 *
 * python(meta.facely.kr)은 CORS 를 열지 않으므로 브라우저가 직접 못 부른다.
 * 클라이언트는 presign(prefix=temp)으로 받은 {key, token} 만 보내고, Worker 가
 * 앱과 동일한 계약(X-Face-Token/X-Face-Key + {image_url})으로 대행 호출한다.
 * temp 원본은 python 이 분석 직후 삭제 (앱 경로와 동일).
 *
 * 응답: { age, gender, ethnicity } (python 계약 그대로 전달)
 */
const ANALYZE_URL = 'https://meta.facely.kr/analyze'

// 홈서버는 동시 처리 상한을 넘으면 즉시 503 을 주므로 정상 경로의 상한은 한 자리
// 초 수준. 이 값은 터널 단절·홈 인터넷 장애처럼 응답 자체가 안 오는 경우를 끊는다.
const UPSTREAM_TIMEOUT_MS = 20_000

export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  let key: string
  let token: string
  try {
    const body = (await request.json()) as { key?: string; token?: string }
    key = body.key ?? ''
    token = body.token ?? ''
  } catch {
    return new Response('Bad JSON', { status: 400 })
  }
  // presign 이 발급하는 temp 키 형태만 통과 — 임의 URL 분석 요청 차단.
  if (!/^temp\/[0-9a-f-]{36}\.jpe?g$/i.test(key) || !token) {
    return new Response('Bad Request', { status: 400 })
  }

  const env = context.cloudflare.env
  let res: Response
  try {
    res = await fetch(ANALYZE_URL, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'X-Face-Token': token,
        'X-Face-Key': key,
      },
      body: JSON.stringify({ image_url: `${env.R2_CDN_BASE}/${key}` }),
      signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
    })
  } catch {
    // 타임아웃(AbortError) 또는 홈서버 도달 불가. 무한정 매달리는 대신 즉시
    // 504 — 호출자가 로딩 스피너를 끝낼 수 있어야 한다.
    return new Response(
      JSON.stringify({ error: 'upstream_timeout', detail: 'analyze upstream did not respond in time' }),
      { status: 504, headers: { 'content-type': 'application/json' } },
    )
  }

  const text = await res.text()
  const headers: Record<string, string> = { 'content-type': 'application/json' }
  // 503 백프레셔의 재시도 힌트는 그대로 전달.
  const retryAfter = res.headers.get('retry-after')
  if (retryAfter) headers['retry-after'] = retryAfter
  return new Response(text, { status: res.status, headers })
}
