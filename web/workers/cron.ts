/**
 * Cron Triggers 잡 4종 — wrangler.jsonc `triggers.crons` 가 스케줄, 호출은
 * Cloudflare 플랫폼이 직접 (`workers/app.ts` 의 `scheduled` 핸들러).
 *
 *   매시    expireStaleTeams      — 모집 7일 초과 방 expired (시작은 cron 몫 아님).
 *   매시    completeOrphanReveals — revealing 24h 고아 방 completed 안전망.
 *   매일    cleanupStaleMetrics   — 90일 미활동 anon metrics 삭제.
 *   매일    purgeExpiredTeams     — 종료 후 30일 지난 teams 삭제 (멤버 cascade).
 *
 * 로컬 테스트: `pnpm wrangler dev` 후
 *   curl "http://localhost:8787/__scheduled?cron=0+*+*+*+*"
 */

import { deleteKeys, deleteOwnerThumbnails, readR2Cfg } from '../app/lib/r2-thumbnails'

type CronEnv = Env & {
  SUPABASE_SERVICE_ROLE_KEY?: string
}

function serviceHeaders(env: CronEnv): Record<string, string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  if (!key) throw new Error('missing SUPABASE_SERVICE_ROLE_KEY')
  return { apikey: key, Authorization: `Bearer ${key}` }
}

const daysAgo = (d: number) =>
  new Date(Date.now() - d * 24 * 3600_000).toISOString()

/**
 * 7일 만료 — 시작 조건은 정원 충족 하나뿐이므로 cron 은 시작을 수행하지
 * 않는다. 모집 7일 안에 정원을 못 채운 방은 인원 무관 expired (모이면 굿,
 * 안 모이면 꽝). closed_at 을 찍어 30일 purge 수명주기에 진입시킨다.
 */
export async function expireStaleTeams(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?status=eq.recruiting&created_at=lt.${daysAgo(7)}&select=id`,
    {
      method: 'PATCH',
      headers: {
        ...serviceHeaders(env),
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        status: 'expired',
        closed_at: new Date().toISOString(),
      }),
    },
  )
  if (!res.ok) throw new Error(`expireStaleTeams failed: ${res.status}`)
  const expired = ((await res.json()) as unknown[]).length
  if (expired > 0) console.log(`[cron] expireStaleTeams: expired ${expired}`)
  return expired
}

/**
 * revealing 고아 안전망 — 시작됐지만 전 참가자 이탈 등으로 24h 내
 * result_payload 가 backfill 되지 않은 방을 completed 로 닫는다.
 * payload 는 null 로 남고 쇼케이스가 "결과 미생성" 을 렌더.
 */
export async function completeOrphanReveals(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?status=eq.revealing&result_payload=is.null&started_at=lt.${daysAgo(1)}&select=id`,
    {
      method: 'PATCH',
      headers: {
        ...serviceHeaders(env),
        'Content-Type': 'application/json',
        Prefer: 'return=representation',
      },
      body: JSON.stringify({
        status: 'completed',
        closed_at: new Date().toISOString(),
      }),
    },
  )
  if (!res.ok) throw new Error(`completeOrphanReveals failed: ${res.status}`)
  const closed = ((await res.json()) as unknown[]).length
  if (closed > 0) console.log(`[cron] completeOrphanReveals: closed ${closed}`)
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
): Promise<{ rows: number }> {
  const svc = serviceHeaders(env)
  const sel = await fetch(
    `${env.SUPABASE_URL}/rest/v1/metrics?user_id=is.null&updated_at=lt.${daysAgo(90)}&select=id,body&limit=500`,
    { headers: svc },
  )
  if (!sel.ok) throw new Error(`cleanupStaleMetrics select failed: ${sel.status}`)
  const rows = (await sel.json()) as Array<{ id: string; body: string | null }>
  if (rows.length === 0) return { rows: 0 }

  // 익명 사진은 `thumbnails/anon-{metrics_id}/` 에 있다 — 행과 함께 폴더를
  // 지운다. 소유자가 폴더에 박혀 있어서 다른 사람 사진을 건드릴 수가 없다.
  // 소유자 스코프 이전에 저장된 레거시 키는 폴더에 안 잡히므로 body 에서
  // 따로 걷는다.
  const cfg = readR2Cfg(env)
  if (cfg) {
    const legacy: string[] = []
    for (const r of rows) {
      try {
        await deleteOwnerThumbnails(cfg, `anon-${r.id}`)
      } catch (e) {
        console.log(`[cron] anon 썸네일 삭제 실패 id=${r.id}: ${e}`)
      }
      if (!r.body) continue
      try {
        const k = (JSON.parse(r.body) as { thumbnailKey?: string }).thumbnailKey
        if (k && !k.startsWith('thumbnails/anon-')) legacy.push(k)
      } catch {
        /* body 가 깨진 행 — 키를 알 수 없다 */
      }
    }
    await deleteKeys(cfg, legacy)
  }

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
  console.log(`[cron] cleanupStaleMetrics: rows ${ids.length}`)
  return { rows: ids.length }
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
