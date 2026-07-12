import { AwsClient } from 'aws4fetch'
import type { Route } from './+types/api.r2.delete'

/**
 * POST /api/r2/delete — 웹 재촬영 시 옛 썸네일 **즉시** 삭제.
 *
 * 재촬영은 새 R2 키로 업로드하므로 (CDN 캐시 스테일 회피) 옛 객체가 고아로
 * 남는다 — cron 스윕 대신 교체 시점에 바로 지우는 것이 정석.
 *
 * 요청: { key: "thumbnails/YYYYMM/uuid.jpg" } + Authorization: Bearer <user JWT>
 *
 * 인가: 요청자의 JWT 를 검증하고, 그 사용자의 metrics.body 중 하나가
 * **아직 이 key 를 참조하고 있을 때만** 삭제 허용 — 남의 썸네일이나 임의
 * 키 삭제 불가. (클라이언트는 body 를 새 키로 upsert 하기 **전에** 호출한다.)
 */
export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  const auth = request.headers.get('authorization')
  if (!auth?.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 })
  }

  let key: string
  try {
    const body = (await request.json()) as { key?: string }
    key = body.key ?? ''
  } catch {
    return new Response('Bad JSON', { status: 400 })
  }
  // thumbnails/ 하위의 uuid 파일명만 — 그 외 prefix·경로 조작 차단.
  if (!/^thumbnails\/\d{6}\/[0-9a-f-]{36}\.jpe?g$/i.test(key)) {
    return new Response('Bad key', { status: 400 })
  }

  const env = context.cloudflare.env

  // 1) JWT → user_id
  const userRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: auth },
  })
  if (!userRes.ok) {
    return new Response('Invalid token', { status: 401 })
  }
  const user = (await userRes.json()) as { id: string }

  // 2) 소유 검증 — 내 metrics 중 하나가 이 key 를 참조해야 한다.
  const metricsRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/metrics?user_id=eq.${user.id}&select=body`,
    { headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: auth } },
  )
  const rows = metricsRes.ok
    ? ((await metricsRes.json()) as Array<{ body: string }>)
    : []
  const owns = rows.some((r) => {
    try {
      return (JSON.parse(r.body) as { thumbnailKey?: string }).thumbnailKey === key
    } catch {
      return false
    }
  })
  if (!owns) {
    return new Response('Forbidden', { status: 403 })
  }

  // 3) R2 DELETE (SigV4) — 404 도 성공 취급 (이미 없음).
  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: 's3',
    region: 'auto',
  })
  const url = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}/${key}`
  const signed = await r2.sign(new Request(url, { method: 'DELETE' }))
  const res = await fetch(signed)
  if (!res.ok && res.status !== 404) {
    return Response.json({ error: 'r2 delete failed', status: res.status }, { status: 500 })
  }

  return Response.json({ success: true })
}
