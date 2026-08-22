#!/usr/bin/env node
/**
 * 1회 정리 도구 — 어떤 metrics 행도 참조하지 않는 R2 썸네일을 지운다.
 *
 * 왜 필요한가: 예전에는 정면 캡처 직후(사용자가 "정보 확인" 을 마치기 전에)
 * 썸네일을 올렸다. 거기서 취소하면 행이 안 생겨 그 얼굴 이미지가 주인 없이
 * 남았고, 소유자가 없으니 탈퇴에도 90일 정리에도 안 걸렸다. 지금은 카드를
 * 저장한 뒤에 올리므로 새로 생기지 않는다 — 이미 쌓인 것만 여기서 치운다.
 *
 * 상시 잡이 아니다. 평상시 회수는 metrics_thumbnail_gc 트리거 +
 * cron drainThumbnailGc 가 한다.
 *
 * 사용법 (web/ 에서):
 *   node scripts/purge-orphan-thumbnails.mjs           # 조회만 (기본)
 *   node scripts/purge-orphan-thumbnails.mjs --apply   # 실제 삭제
 *   node scripts/purge-orphan-thumbnails.mjs --days 30 # 유예 기간 (기본 7일)
 *
 * 유예 기간을 두는 이유: 방금 올라갔지만 아직 행이 저장되지 않은 객체를
 * 고아로 오판하지 않기 위해서다.
 */

import { readFileSync } from 'node:fs'
import { AwsClient } from 'aws4fetch'

const args = process.argv.slice(2)
const apply = args.includes('--apply')
const daysArg = args.includes('--days') ? Number(args[args.indexOf('--days') + 1]) : NaN
const days = Number.isFinite(daysArg) ? daysArg : 7   // --days 0 도 0 으로 산다

const vars = Object.fromEntries(
  readFileSync('.dev.vars', 'utf8')
    .split('\n')
    .filter((l) => l.includes('=') && !l.trim().startsWith('#'))
    .map((l) => {
      const i = l.indexOf('=')
      return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^["']|["']$/g, '')]
    }),
)
const wrangler = JSON.parse(
  readFileSync('wrangler.jsonc', 'utf8').replace(/^\s*\/\/.*$/gm, ''),
).vars

const SUPABASE_URL = vars.SUPABASE_URL
const SERVICE_KEY = vars.SUPABASE_SERVICE_ROLE_KEY
const ACCOUNT = wrangler.R2_ACCOUNT_ID
const BUCKET = wrangler.R2_BUCKET_NAME
if (!SUPABASE_URL || !SERVICE_KEY || !ACCOUNT || !BUCKET) {
  console.error('환경값 부족 — .dev.vars 와 wrangler.jsonc 를 확인하세요.')
  process.exit(1)
}

const r2 = new AwsClient({
  accessKeyId: vars.R2_ACCESS_KEY_ID,
  secretAccessKey: vars.R2_SECRET_ACCESS_KEY,
  service: 's3',
  region: 'auto',
})
const base = `https://${ACCOUNT}.r2.cloudflarestorage.com/${BUCKET}`
const svc = { apikey: SERVICE_KEY, Authorization: `Bearer ${SERVICE_KEY}` }

/** metrics.body 가 참조하는 썸네일 키 전부. */
async function referencedKeys() {
  const keys = new Set()
  const page = 1000
  for (let from = 0; ; from += page) {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/metrics?select=body`, {
      headers: { ...svc, Range: `${from}-${from + page - 1}` },
    })
    if (!res.ok) throw new Error(`metrics select ${res.status}`)
    const rows = await res.json()
    for (const r of rows) {
      try {
        const k = JSON.parse(r.body)?.thumbnailKey
        if (k) keys.add(k)
      } catch {
        /* body 가 깨진 행 — 참조 없음으로 본다 */
      }
    }
    if (rows.length < page) break
  }
  return keys
}

/** thumbnails/ 전체 객체 (key + lastModified). */
async function* listThumbnails() {
  let token = null
  do {
    const url = new URL(base)
    url.searchParams.set('list-type', '2')
    url.searchParams.set('prefix', 'thumbnails/')
    url.searchParams.set('max-keys', '1000')
    if (token) url.searchParams.set('continuation-token', token)
    const res = await fetch(await r2.sign(new Request(url)))
    if (!res.ok) throw new Error(`R2 list ${res.status}`)
    const xml = await res.text()
    for (const m of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
      const key = /<Key>([^<]+)<\/Key>/.exec(m[1])?.[1]
      const mod = /<LastModified>([^<]+)<\/LastModified>/.exec(m[1])?.[1]
      if (key) yield { key, lastModified: mod ? new Date(mod) : null }
    }
    token = /<NextContinuationToken>([^<]+)<\/NextContinuationToken>/.exec(xml)?.[1] ?? null
  } while (token)
}

const referenced = await referencedKeys()
console.log(`참조 중인 썸네일 키: ${referenced.size}개`)

const cutoff = new Date(Date.now() - days * 24 * 3600_000)
let total = 0
let orphans = 0
let deleted = 0

for await (const { key, lastModified } of listThumbnails()) {
  total++
  if (referenced.has(key)) continue
  if (lastModified && lastModified > cutoff) continue // 유예 기간 안 — 건너뛴다.
  orphans++
  if (!apply) {
    if (orphans <= 10) console.log(`  고아: ${key} (${lastModified?.toISOString()})`)
    continue
  }
  const res = await fetch(await r2.sign(new Request(`${base}/${key}`, { method: 'DELETE' })))
  if (res.ok || res.status === 404) deleted++
}

console.log(`
객체 ${total}개 중 고아 ${orphans}개 (유예 ${days}일 적용)`)
console.log(apply ? `삭제 완료: ${deleted}개` : '조회만 함 — 지우려면 --apply')
