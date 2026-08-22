import { AwsClient } from 'aws4fetch'

/**
 * Cron Triggers 잡 4종 — wrangler.jsonc `triggers.crons` 가 스케줄, 호출은
 * Cloudflare 플랫폼이 직접 (`workers/app.ts` 의 `scheduled` 핸들러).
 *
 *   매시    expireStaleTeams      — 모집 48h 초과 방 expired (시작은 cron 몫 아님).
 *   매시    completeOrphanReveals — revealing 24h 고아 방 completed 안전망.
 *   매일    cleanupStaleMetrics   — 90일 미활동 anon metrics 삭제.
 *   매일    purgeExpiredTeams     — 종료 후 30일 지난 teams 삭제 (멤버 cascade).
 *   매일    drainThumbnailGc      — 참조 끊긴 R2 썸네일 회수 (아웃박스 소비).
 *
 * 로컬 테스트: `pnpm wrangler dev` 후
 *   curl "http://localhost:8787/__scheduled?cron=0+*+*+*+*"
 */

type CronEnv = Env & {
  SUPABASE_SERVICE_ROLE_KEY?: string
  // 엣지 캐시 퍼지용 — 없으면 퍼지를 건너뛴다 (객체는 지워지고 캐시는 TTL 만료).
  CLOUDFLARE_API_TOKEN?: string
  CLOUDFLARE_ZONE_ID?: string
}

function serviceHeaders(env: CronEnv): Record<string, string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY
  if (!key) throw new Error('missing SUPABASE_SERVICE_ROLE_KEY')
  return { apikey: key, Authorization: `Bearer ${key}` }
}

const daysAgo = (d: number) =>
  new Date(Date.now() - d * 24 * 3600_000).toISOString()

/**
 * 48h 만료 — 시작 조건은 정원 충족 하나뿐이므로 cron 은 시작을 수행하지
 * 않는다. 모집 48h 안에 정원을 못 채운 방은 인원 무관 expired (모이면 굿,
 * 안 모이면 꽝). closed_at 을 찍어 30일 purge 수명주기에 진입시킨다.
 */
export async function expireStaleTeams(env: CronEnv): Promise<number> {
  const res = await fetch(
    `${env.SUPABASE_URL}/rest/v1/teams?status=eq.recruiting&created_at=lt.${daysAgo(2)}&select=id`,
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
    `${env.SUPABASE_URL}/rest/v1/metrics?user_id=is.null&updated_at=lt.${daysAgo(90)}&select=id&limit=500`,
    { headers: svc },
  )
  if (!sel.ok) throw new Error(`cleanupStaleMetrics select failed: ${sel.status}`)
  const rows = (await sel.json()) as Array<{ id: string }>
  if (rows.length === 0) return { rows: 0 }

  // 썸네일 회수는 여기서 하지 않는다 — 행을 지우면 metrics_thumbnail_gc
  // 트리거가 키를 아웃박스에 넣고 drainThumbnailGc 가 지운다. 이 함수가 직접
  // 지우면 "행보다 객체를 먼저" 라는 순서 제약을 여기서도 지켜야 한다.

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
 * 참조가 끊긴 R2 썸네일 회수 — `thumbnail_gc` 아웃박스를 비운다.
 *
 * 큐에 든 키를 그냥 지우지 않고 두 가지를 확인한다:
 *   1. 다른 metrics 행이 아직 이 키를 참조하는가 — 내용 주소라 서로 다른 카드가
 *      한 객체를 가리킬 수 있다(공유받은 카드 등). 참조가 있으면 객체는 두고
 *      큐에서만 뺀다.
 *   2. 객체가 큐에 들어온 뒤에 다시 올라왔는가 — 같은 사진을 지웠다가 다시
 *      등록하면 같은 키로 새 객체가 생긴다. last-modified 가 queued_at 보다
 *      나중이면 살아있는 객체이므로 건드리지 않는다.
 *
 * 실패한 키는 큐에 남아 다음 실행이 재시도한다 — queued_at 이 오래된 키가
 * 곧 계속 실패하는 키다.
 */
export async function drainThumbnailGc(
  env: CronEnv,
): Promise<{ deleted: number; kept: number }> {
  const svc = serviceHeaders(env)
  const sel = await fetch(
    `${env.SUPABASE_URL}/rest/v1/thumbnail_gc?select=key,queued_at&order=queued_at.asc&limit=200`,
    { headers: svc },
  )
  if (!sel.ok) throw new Error(`drainThumbnailGc select failed: ${sel.status}`)
  const queued = (await sel.json()) as Array<{ key: string; queued_at: string }>
  if (queued.length === 0) return { deleted: 0, kept: 0 }

  const r2 = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: 's3',
    region: 'auto',
  })
  const r2Base = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}`

  let deleted = 0
  let kept = 0
  const purged: string[] = []
  const done: string[] = []

  for (const { key, queued_at } of queued) {
    try {
      // 1) 아직 참조되는가.
      const refRes = await fetch(
        `${env.SUPABASE_URL}/rest/v1/metrics?body=like.*${encodeURIComponent(key)}*&select=id&limit=1`,
        { headers: svc },
      )
      if (!refRes.ok) continue // 다음 실행에서 재시도.
      if (((await refRes.json()) as unknown[]).length > 0) {
        kept++
        done.push(key)
        continue
      }

      // 2) 큐에 들어온 뒤 다시 올라온 객체인가.
      const head = await fetch(
        await r2.sign(new Request(`${r2Base}/${key}`, { method: 'HEAD' })),
      )
      if (head.status === 404) {
        done.push(key) // 이미 없다 — 큐에서만 뺀다.
        continue
      }
      if (!head.ok) continue
      const lastModified = head.headers.get('last-modified')
      if (lastModified && new Date(lastModified) > new Date(queued_at)) {
        kept++
        done.push(key)
        continue
      }

      const del = await fetch(
        await r2.sign(new Request(`${r2Base}/${key}`, { method: 'DELETE' })),
      )
      if (del.ok || del.status === 404) {
        deleted++
        done.push(key)
        purged.push(key)
      }
    } catch (e) {
      console.log(`[cron] drainThumbnailGc key=${key} 실패: ${e}`)
    }
  }

  await purgeCdnCache(env, purged)

  if (done.length > 0) {
    for (let i = 0; i < done.length; i += 50) {
      const chunk = done.slice(i, i + 50).map((k) => `"${k}"`)
      await fetch(
        `${env.SUPABASE_URL}/rest/v1/thumbnail_gc?key=in.(${chunk.join(',')})`,
        { method: 'DELETE', headers: { ...svc, Prefer: 'return=minimal' } },
      )
    }
  }
  // 남은 키는 다음 실행 몫 — 재시도 횟수를 올려 계속 실패하는 키를 드러낸다.
  const stuck = queued.filter((q) => !done.includes(q.key)).map((q) => q.key)
  if (stuck.length > 0) {
    console.log(`[cron] drainThumbnailGc: ${stuck.length}건 다음 실행으로 이월`)
  }

  console.log(
    `[cron] drainThumbnailGc: deleted ${deleted}, kept ${kept}, queued ${queued.length}`,
  )
  return { deleted, kept }
}

/**
 * 지운 객체의 엣지 캐시 무효화. 썸네일은 `immutable` 로 오래 캐시되므로 원본을
 * 지워도 엣지가 계속 내줄 수 있다 — 삭제 약속을 지키려면 퍼지가 필요하다.
 * 토큰·zone 이 설정돼 있지 않으면 건너뛴다 (그 경우 TTL 만료를 기다린다).
 */
async function purgeCdnCache(env: CronEnv, keys: string[]): Promise<void> {
  const token = env.CLOUDFLARE_API_TOKEN
  const zone = env.CLOUDFLARE_ZONE_ID
  if (!token || !zone || keys.length === 0) return
  const cdnBase = (env.R2_CDN_BASE || '').replace(/\/$/, '')
  // purge-by-URL 은 호출당 건수 한도가 있다 — 30개씩 끊는다.
  for (let i = 0; i < keys.length; i += 30) {
    const files = keys.slice(i, i + 30).map((k) => `${cdnBase}/${k}`)
    try {
      await fetch(
        `https://api.cloudflare.com/client/v4/zones/${zone}/purge_cache`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({ files }),
        },
      )
    } catch (e) {
      console.log(`[cron] purgeCdnCache 실패: ${e}`)
    }
  }
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
