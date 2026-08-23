#!/usr/bin/env node
/**
 * 구매한 궁합의 사진을 구매자 폴더로 백필한다.
 *
 * 왜 필요한가 — 구매 사본(2026-08-23) 이전에 팔린 궁합은 스냅샷이 **상대의**
 * 썸네일 키를 직접 가리킨다. 그 사람이 재촬영하거나(구 앱) 운영자가 콘솔에서
 * 사진을 교체하면 그 객체가 사라져 산 사람 화면이 깨진다. 앱을 열면
 * `_reconcileThumbnails` 가 고치지만, 그건 구매자가 앱을 열어야 닫히는 창이다.
 * 이 스크립트가 그 창을 서버에서 한 번에 닫는다.
 *
 * **지우는 것이 없다.** 사본을 올리고 스냅샷의 키를 그 사본으로 바꾼다.
 * 키 교체는 업로드 성공을 확인한 뒤에만 한다 — 순서가 반대면 살아있는
 * 스냅샷을 빈 주소로 만든다.
 *
 * 실행:
 *   SUPABASE_SERVICE_ROLE_KEY=... node scripts/backfill-compat-thumbnails.mjs
 *   SUPABASE_SERVICE_ROLE_KEY=... node scripts/backfill-compat-thumbnails.mjs --apply
 *
 * 인자 없이 돌리면 조사만 하고 아무것도 바꾸지 않는다.
 *
 * `--fallback-current` 를 더하면, 원본이 이미 사라진 면을 **그 사람의 현재
 * 사진**으로 채운다. 구매 당시 얼굴이 아니라 지금 얼굴이다 — 정확성을 한 칸
 * 내주고 실루엣을 면하는 선택이라 기본값이 아니다.
 */
import { createHash } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { AwsClient } from 'aws4fetch'

const APPLY = process.argv.includes('--apply')
// 원본이 사라진 면을 **그 사람의 현재 사진**으로 채운다. 구매 당시 얼굴이
// 아니므로 기본값이 아니다 — 실루엣보다 낫다고 판단할 때만 명시적으로 켠다.
const FALLBACK = process.argv.includes('--fallback-current')

// ── 환경값 ────────────────────────────────────────────────────────────────
const vars = {}
for (const line of readFileSync('.dev.vars', 'utf8').split('\n')) {
  const t = line.trim()
  if (!t || t.startsWith('#') || !t.includes('=')) continue
  const [k, ...rest] = t.split('=')
  vars[k.trim()] = rest.join('=').trim().replace(/^["']|["']$/g, '')
}
const wrangler = JSON.parse(
  readFileSync('wrangler.jsonc', 'utf8').replace(/^\s*\/\/.*$/gm, ''),
).vars

const SUPABASE_URL = vars.SUPABASE_URL
const SERVICE_KEY =
  process.env.SUPABASE_SERVICE_ROLE_KEY || vars.SUPABASE_SERVICE_ROLE_KEY
const ACCOUNT = wrangler.R2_ACCOUNT_ID
const BUCKET = wrangler.R2_BUCKET_NAME

if (!SUPABASE_URL || !SERVICE_KEY || !ACCOUNT || !BUCKET) {
  console.error(
    'SUPABASE_SERVICE_ROLE_KEY 환경변수가 필요하다 (.dev.vars 에는 없다).\n' +
      'Supabase 대시보드 → Project Settings → API → service_role.',
  )
  process.exit(1)
}

const svc = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` }
const r2 = new AwsClient({
  accessKeyId: vars.R2_ACCESS_KEY_ID,
  secretAccessKey: vars.R2_SECRET_ACCESS_KEY,
  service: 's3',
  region: 'auto',
})
const base = `https://${ACCOUNT}.r2.cloudflarestorage.com/${BUCKET}`

// ── R2 ───────────────────────────────────────────────────────────────────
async function getObject(key) {
  const res = await fetch(await r2.sign(new Request(`${base}/${key}`)))
  if (res.status === 404) return null
  if (!res.ok) throw new Error(`GET ${key} → ${res.status}`)
  return Buffer.from(await res.arrayBuffer())
}

async function putObject(key, bytes) {
  const res = await fetch(
    await r2.sign(
      new Request(`${base}/${key}`, {
        method: 'PUT',
        body: bytes,
        headers: {
          'content-type': 'image/jpeg',
          'cache-control': 'public, max-age=31536000, immutable',
        },
      }),
    ),
  )
  if (!res.ok) throw new Error(`PUT ${key} → ${res.status}`)
}

async function objectExists(key) {
  const res = await fetch(
    await r2.sign(new Request(`${base}/${key}`, { method: 'HEAD' })),
  )
  return res.ok
}

// ── 대상 조사 ─────────────────────────────────────────────────────────────
async function allPairs() {
  const rows = []
  const page = 1000
  for (let from = 0; ; from += page) {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/compatibilities?select=user_id,a_id,b_id,a_body,b_body`,
      { headers: { ...svc, Range: `${from}-${from + page - 1}` } },
    )
    if (!res.ok) throw new Error(`compatibilities select ${res.status}`)
    const chunk = await res.json()
    rows.push(...chunk)
    if (chunk.length < page) break
  }
  return rows
}

function keyOf(body) {
  if (!body) return null
  try {
    return JSON.parse(body)?.thumbnailKey ?? null
  } catch {
    return null
  }
}

/** 그 사람의 **현재** 썸네일 키 — metrics.id 는 스냅샷의 a_id/b_id 와 같다. */
const currentKeyCache = new Map()
async function currentKeyOf(metricsId) {
  if (currentKeyCache.has(metricsId)) return currentKeyCache.get(metricsId)
  let key = null
  try {
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/metrics?id=eq.${metricsId}&select=body`,
      { headers: svc },
    )
    if (res.ok) {
      const rows = await res.json()
      key = keyOf(rows[0]?.body)
    }
  } catch {
    /* 행이 없거나 조회 실패 — 대체할 사진이 없다 */
  }
  currentKeyCache.set(metricsId, key)
  return key
}

async function patchSide(row, side, key) {
  const body = JSON.parse(row[`${side}_body`])
  body.thumbnailKey = key
  const q =
    `user_id=eq.${row.user_id}&a_id=eq.${row.a_id}&b_id=eq.${row.b_id}`
  const res = await fetch(`${SUPABASE_URL}/rest/v1/compatibilities?${q}`, {
    method: 'PATCH',
    headers: { ...svc, 'Content-Type': 'application/json', Prefer: 'return=minimal' },
    body: JSON.stringify({ [`${side}_body`]: JSON.stringify(body) }),
  })
  if (!res.ok) throw new Error(`PATCH ${row.a_id}~${row.b_id}.${side} → ${res.status}`)
}

// ── 본체 ─────────────────────────────────────────────────────────────────
const pairs = await allPairs()
console.log(`compatibilities ${pairs.length}행\n`)

const stat = { own: 0, noKey: 0, copied: 0, fallback: 0, lost: 0, failed: 0, todo: 0 }
const lost = []

for (const row of pairs) {
  for (const side of ['a', 'b']) {
    const key = keyOf(row[`${side}_body`])
    if (!key) {
      stat.noKey++
      continue
    }
    const mine = `thumbnails/${row.user_id}/`
    if (key.startsWith(mine)) {
      stat.own++
      continue
    }
    stat.todo++
    const label = `${row.a_id.slice(0, 8)}~${row.b_id.slice(0, 8)}.${side}`

    if (!APPLY) {
      if (await objectExists(key)) {
        console.log(`  복사 대상  ${label}  ${key}`)
        continue
      }
      const alt = FALLBACK ? await currentKeyOf(row[`${side}_id`]) : null
      if (alt && (await objectExists(alt))) {
        stat.fallback++
        console.log(`  대체 가능  ${label}  ${key}  →  현재 사진 ${alt}`)
      } else {
        stat.lost++
        lost.push(`${label}  ${key}`)
        console.log(`  원본 없음  ${label}  ${key}`)
      }
      continue
    }

    try {
      let bytes = await getObject(key)
      let substituted = false
      if (!bytes && FALLBACK) {
        // 구매 당시 사진이 사라졌다 — 그 사람의 현재 사진으로 채운다.
        const alt = await currentKeyOf(row[`${side}_id`])
        if (alt) bytes = await getObject(alt)
        substituted = Boolean(bytes)
      }
      if (!bytes) {
        stat.lost++
        lost.push(`${label}  ${key}`)
        continue
      }
      const hash = createHash('sha256').update(bytes).digest('hex')
      const dest = `thumbnails/${row.user_id}/${hash}.jpg`
      // 이미 있으면 PUT 을 건너뛰지 않는다 — 같은 바이트라 덮어써도 무해하고,
      // 존재 확인과 키 교체 사이의 틈을 만들지 않는 쪽이 안전하다.
      await putObject(dest, bytes)
      await patchSide(row, side, dest)
      if (substituted) stat.fallback++
      else stat.copied++
      console.log(`  ${substituted ? '대체됨' : '복사됨'}  ${label}  →  ${dest}`)
    } catch (e) {
      stat.failed++
      console.log(`  실패    ${label}  ${e.message}`)
    }
  }
}

console.log(`
─────────────────────────────────────────
이미 구매자 사본        ${stat.own}
사진 없는 면            ${stat.noKey}
대상                    ${stat.todo}
${APPLY ? `  복사 완료             ${stat.copied}` : ''}
${FALLBACK ? `  현재 사진으로 대체    ${stat.fallback}` : ''}
  원본 소실(복구 불가)  ${stat.lost}
${APPLY ? `  실패(재실행 가능)     ${stat.failed}` : ''}
─────────────────────────────────────────`)

if (lost.length > 0) {
  console.log('\n원본이 이미 사라진 면 — 이 쌍은 실루엣으로 남는다:')
  for (const l of lost) console.log(`  ${l}`)
}
if (!APPLY) console.log('\n조사만 했다. 실제 반영은 --apply.')
