import { AwsClient } from 'aws4fetch'
import type { Route } from './+types/api.account.delete'

/**
 * POST /api/account/delete — 회원 탈퇴 (탈퇴 후 복구 불가).
 *
 * 클라이언트는 자기 JWT 만 보내면 됨.
 *
 * 흐름:
 *   1) JWT 검증 + user_id 추출 (Supabase /auth/v1/user)
 *   2) RLS-scoped SELECT 으로 user 의 metrics.body → thumbnailKey 수집
 *   3) R2 thumbnails 일괄 DELETE
 *   4) service_role 로 DELETE FROM metrics WHERE user_id — FK 가 cascade 라
 *      5)에서 어차피 지워지지만, R2 정리(3) 와의 순서 보장 + auth DELETE 가
 *      중간 실패해도 metrics 부터 확실히 사라지게 명시 삭제 유지
 *   5) service_role 로 owner 의 **모집 중(open) teams** DELETE — 초대 링크가
 *      주인 없는 좀비 방으로 남지 않게. 발표된(closed) 팀은 30일 수명주기
 *      cron 이 정리 (참여자들이 결과를 계속 볼 수 있어야 하므로 즉시 삭제 X)
 *   6) service_role admin API 로 auth.users DELETE → cascade 로
 *      users/coins/unlocks/metrics 자동 삭제, teams.owner_id 는 set null
 *
 * 재가입 보너스 farming 방지: handle_new_user 트리거가 bonus_recipients 영구
 * 테이블을 조회하므로 같은 email/kakao_id 로 재가입해도 보너스 0.
 */
export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }

  const auth = request.headers.get('authorization')
  if (!auth?.startsWith('Bearer ')) {
    return new Response('Unauthorized', { status: 401 })
  }

  const env = context.cloudflare.env as Env & {
    SUPABASE_SERVICE_ROLE_KEY?: string
  }
  const serviceKey = env.SUPABASE_SERVICE_ROLE_KEY
  if (!serviceKey) {
    return new Response('Server misconfigured: missing service role key', {
      status: 500,
    })
  }

  // 1) JWT → user_id
  const userRes = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: auth },
  })
  if (!userRes.ok) {
    return new Response('Invalid token', { status: 401 })
  }
  const user = (await userRes.json()) as { id: string }

  // 2) thumbnailKey 수집 (RLS-scoped, user 본인 row 만)
  const metricsRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/metrics?user_id=eq.${user.id}&select=body`,
    {
      headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: auth },
    },
  )
  const rows = metricsRes.ok
    ? ((await metricsRes.json()) as Array<{ body: string }>)
    : []
  const thumbnailKeys: string[] = []
  for (const r of rows) {
    try {
      const b = JSON.parse(r.body) as { thumbnailKey?: string }
      if (b.thumbnailKey) thumbnailKeys.push(b.thumbnailKey)
    } catch {
      /* malformed body — skip */
    }
  }

  // 3) R2 DELETE — 병렬, 실패해도 계속 진행 (이미 삭제됐을 수도)
  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: 's3',
    region: 'auto',
  })
  const r2Base = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}`
  let deletedThumbnails = 0
  await Promise.all(
    thumbnailKeys.map(async (key) => {
      const url = `${r2Base}/${key}`
      const signed = await r2.sign(new Request(url, { method: 'DELETE' }))
      const r = await fetch(signed)
      if (r.ok || r.status === 404) deletedThumbnails++
    }),
  )

  // 4) metrics 명시적 DELETE — cascade 의 선행 보장 (헤더 주석 참조)
  const metricsDel = await fetch(
    `${env.SUPABASE_URL}/rest/v1/metrics?user_id=eq.${user.id}`,
    {
      method: 'DELETE',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        Prefer: 'return=minimal',
      },
    },
  )
  if (!metricsDel.ok) {
    return Response.json(
      { error: 'metrics delete failed', status: metricsDel.status },
      { status: 500 },
    )
  }

  // 5) 모집 중(recruiting) teams DELETE — 내 그룹만. team_members 는
  // FK cascade. closed 팀은 owner_id 만 null 이 되고 30일 cron 이 정리.
  const teamsDel = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?owner_id=eq.${user.id}&status=eq.recruiting`,
    {
      method: 'DELETE',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        Prefer: 'return=minimal',
      },
    },
  )
  if (!teamsDel.ok) {
    return Response.json(
      { error: 'open teams delete failed', status: teamsDel.status },
      { status: 500 },
    )
  }

  // 6) auth.users DELETE (admin) — cascade: users/coins/unlocks/metrics
  const authDel = await fetch(
    `${env.SUPABASE_URL}/auth/v1/admin/users/${user.id}`,
    {
      method: 'DELETE',
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
      },
    },
  )
  if (!authDel.ok) {
    return Response.json(
      { error: 'auth user delete failed', status: authDel.status },
      { status: 500 },
    )
  }

  return Response.json({
    success: true,
    deletedThumbnails,
    totalThumbnails: thumbnailKeys.length,
  })
}
