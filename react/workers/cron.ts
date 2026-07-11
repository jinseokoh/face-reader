import { AwsClient } from 'aws4fetch'

/**
 * Cron Triggers 잡 3종 — wrangler.jsonc `triggers.crons` 가 스케줄, 호출은
 * Cloudflare 플랫폼이 직접 (`workers/app.ts` 의 `scheduled` 핸들러).
 *
 *   매시    closeStaleTeams     — 생성 48h 지난 모집 중 팀 자동 발표(마감).
 *   매일    cleanupStaleMetrics — 90일 미활동 anon metrics + R2 썸네일 삭제.
 *   매일    purgeExpiredTeams   — 발표 후 30일 지난 teams 삭제 (멤버 cascade).
 *
 * 로컬 테스트: `pnpm wrangler dev` 후
 *   curl "http://localhost:8787/__scheduled?cron=0+18+*+*+*"
 */

type CronEnv = Env & { SUPABASE_SERVICE_ROLE_KEY?: string }

function serviceHeaders(env: CronEnv): Record<string, string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  if (!key) throw new Error('missing SUPABASE_SERVICE_ROLE_KEY')
  return { apikey: key, Authorization: `Bearer ${key}` }
}

const daysAgo = (d: number) =>
  new Date(Date.now() - d * 24 * 3600_000).toISOString()

/**
 * 48h 자동 발표 — 전원 등록 트리거·방장 수동 발표가 둘 다 안 일어난 방치
 * 그룹을 서버가 대신 닫는다. closed_at 이 찍혀야 30일 수명주기에도 진입.
 * matrix_payload 는 앱만 계산 가능 — owner 앱이 다음 refresh 에서 backfill
 * (team_provider.refreshFromServer). 3명 미만 그룹은 웹이 "인원 미달" 렌더.
 */
export async function closeStaleTeams(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?closed_at=is.null&created_at=lt.${daysAgo(2)}&select=id`,
    {
      method: 'PATCH',
      headers: {
        ...serviceHeaders(env),
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify({ closed_at: new Date().toISOString() }),
    },
  )
  if (!res.ok) throw new Error(`closeStaleTeams failed: ${res.status}`)
  const closed = ((await res.json()) as unknown[]).length
  if (closed > 0) console.log(`[cron] closeStaleTeams: closed ${closed}`)
  return closed
}

/**
 * 90일 미활동 anon metrics 정리 — `user_id IS NULL` 행만. 로그인 유저 소유
 * 행은 계정 삭제(api.account.delete)가 담당하므로 여기서 건드리지 않는다
 * (오래 안 연 유저의 "내 관상" 백업 오삭제 방지). 공유 링크 조회는
 * increment_metrics_views 가 updated_at 을 touch — 아직 보는 카드는 생존.
 * 배치 500 — 초과분은 다음 실행이 이어서 (자연 수렴).
 */
export async function cleanupStaleMetrics(
  env: CronEnv,
): Promise<{ rows: number; thumbnails: number }> {
  const svc = serviceHeaders(env)
  const sel = await fetch(
    `${env.SUPABASE_URL}/rest/v1/metrics?user_id=is.null&updated_at=lt.${daysAgo(90)}&select=id,body&limit=500`,
    { headers: svc },
  )
  if (!sel.ok) throw new Error(`cleanupStaleMetrics select failed: ${sel.status}`)
  const rows = (await sel.json()) as Array<{ id: string; body: string }>
  if (rows.length === 0) return { rows: 0, thumbnails: 0 }

  // R2 썸네일 먼저 — row 를 먼저 지우면 key 를 잃어 고아 이미지가 남는다.
  const thumbnailKeys: string[] = []
  for (const r of rows) {
    try {
      const b = JSON.parse(r.body) as { thumbnailKey?: string }
      if (b.thumbnailKey) thumbnailKeys.push(b.thumbnailKey)
    } catch {
      /* malformed body — skip */
    }
  }
  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: 's3',
    region: 'auto',
  })
  const r2Base = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}`
  let thumbnails = 0
  await Promise.all(
    thumbnailKeys.map(async (key) => {
      const signed = await r2.sign(
        new Request(`${r2Base}/${key}`, { method: 'DELETE' }),
      )
      const r = await fetch(signed)
      if (r.ok || r.status === 404) thumbnails++
    }),
  )

  // rows 삭제 — id in-list 를 100개씩 끊어 URL 길이 한도 회피.
  const ids = rows.map((r) => r.id)
  for (let i = 0; i < ids.length; i += 100) {
    const chunk = ids.slice(i, i + 100)
    const del = await fetch(
      `${env.SUPABASE_URL}/rest/v1/metrics?id=in.(${chunk.join(',')})`,
      { method: 'DELETE', headers: { ...svc, Prefer: 'return=minimal' } },
    )
    if (!del.ok) throw new Error(`cleanupStaleMetrics delete failed: ${del.status}`)
  }
  console.log(
    `[cron] cleanupStaleMetrics: rows ${ids.length}, thumbnails ${thumbnails}`,
  )
  return { rows: ids.length, thumbnails }
}

/**
 * 발표 후 30일 지난 teams 삭제 — matrix_payload 에 멤버 실명이 들어 있어
 * (웹 noindex 와 같은 이유) 보존 기한이 개인정보 정리의 본체. team_members 는
 * FK cascade. "만료됐다" 표시 자체는 cron 이 아니라 closed_at+30d 를 각
 * 클라이언트가 계산 — 여기는 데이터 실삭제만 담당.
 */
export async function purgeExpiredTeams(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?closed_at=lt.${daysAgo(30)}&select=id`,
    {
      method: 'DELETE',
      headers: { ...serviceHeaders(env), Prefer: 'return=representation' },
    },
  )
  if (!res.ok) throw new Error(`purgeExpiredTeams failed: ${res.status}`)
  const purged = ((await res.json()) as unknown[]).length
  if (purged > 0) console.log(`[cron] purgeExpiredTeams: purged ${purged}`)
  return purged
}
