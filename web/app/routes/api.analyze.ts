import type { Route } from './+types/api.analyze'
import { issueFaceToken } from '../lib/face-token.server'

/**
 * POST /api/analyze — 얼굴 크롭을 python(meta.facely.kr) 으로 중계한다.
 *
 * 앱과 웹이 같은 문으로 들어온다. 클라이언트는 multipart/form-data 로
 * `image`(384px 정사각 얼굴 크롭 JPEG, 사방 여유 0.2)와 `face_crop`("1")
 * 만 보낸다. R2 temp/ 와 presign 을 거치지 않는다 — 왕복이 4번(presign·PUT·
 * analyze·python 의 재다운로드)에서 1번으로 준다.
 *
 * 인증: python 은 워커가 서명한 HMAC(X-Face-Token/X-Face-Key)만 받는다. 워커가
 * 요청마다 `upload/{uuid}` 키로 토큰을 만들어 붙이므로 클라이언트에 비밀이
 * 없다. python 은 `upload/` 키에 대해 R2 정리를 하지 않는다.
 *
 * 응답: { age, gender, ethnicity, ageModel } (python 계약 그대로 전달).
 *   age·gender = MiVOLO v2, ethnicity = DeepFace race (python/README.md).
 */
const ANALYZE_URL = 'https://meta.facely.kr/analyze'
// 384px 크롭은 20~35KB. python 의 MAX_UPLOAD_MB=1 과 같은 상한.
const MAX_IMAGE_BYTES = 1024 * 1024
// 홈서버는 동시 처리 상한을 넘으면 즉시 503 을 주므로 정상 경로의 상한은 한 자리
// 초 수준. 이 값은 터널 단절·홈 인터넷 장애처럼 응답 자체가 안 오는 경우를 끊는다.
const UPSTREAM_TIMEOUT_MS = 20_000

export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }
  if (!request.headers.get('content-type')?.startsWith('multipart/form-data')) {
    return new Response('Bad Request', { status: 400 })
  }
  let image: File
  let faceCrop: string
  try {
    const form = await request.formData()
    const f = form.get('image')
    if (!(f instanceof File) || f.size === 0) {
      return new Response('Bad Request', { status: 400 })
    }
    image = f
    faceCrop = String(form.get('face_crop') ?? '1')
  } catch {
    return new Response('Bad Request', { status: 400 })
  }
  if (image.size > MAX_IMAGE_BYTES) {
    return new Response('Payload Too Large', { status: 413 })
  }
  const env = context.cloudflare.env
  const secret = env.FACE_API_SECRET
  if (!secret) return new Response('Server misconfigured', { status: 500 })
  const key = `upload/${crypto.randomUUID()}`
  const token = await issueFaceToken(
    secret,
    Number(env.FACE_TOKEN_TTL_SEC || '300'),
    key,
  )

  const upstream = new FormData()
  upstream.set('image', image, 'face.jpg')
  upstream.set('face_crop', faceCrop)
  let res: Response
  try {
    res = await fetch(ANALYZE_URL, {
      method: 'POST',
      headers: { 'X-Face-Token': token, 'X-Face-Key': key },
      body: upstream,
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
