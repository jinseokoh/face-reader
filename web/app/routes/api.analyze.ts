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
  const res = await fetch(ANALYZE_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      'X-Face-Token': token,
      'X-Face-Key': key,
    },
    body: JSON.stringify({ image_url: `${env.R2_CDN_BASE}/${key}` }),
  })
  const text = await res.text()
  return new Response(text, {
    status: res.status,
    headers: { 'content-type': 'application/json' },
  })
}
