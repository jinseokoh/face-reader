import { AwsClient } from 'aws4fetch'

/**
 * 썸네일 객체 삭제 — 소유자 폴더 단위.
 *
 * 키의 첫 칸이 소유자(`thumbnails/{owner}/{sha256}.jpg`)라, "이 사람의 사진을
 * 전부 지운다" 가 prefix 하나를 지우는 일이 된다. 참조 계수도, 아웃박스도,
 * "행보다 객체를 먼저" 라는 순서 제약도 필요 없다 — 어떤 객체도 두 사람에게
 * 속하지 않기 때문이다.
 */
export interface R2Cfg {
  accountId: string
  bucket: string
  accessKeyId: string
  secretAccessKey: string
}

export function readR2Cfg(env: Env): R2Cfg | null {
  if (
    !env.R2_ACCOUNT_ID || !env.R2_BUCKET_NAME ||
    !env.R2_ACCESS_KEY_ID || !env.R2_SECRET_ACCESS_KEY
  ) return null
  return {
    accountId: env.R2_ACCOUNT_ID,
    bucket: env.R2_BUCKET_NAME,
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
  }
}

function client(cfg: R2Cfg): { r2: AwsClient; base: string } {
  return {
    r2: new AwsClient({
      accessKeyId: cfg.accessKeyId,
      secretAccessKey: cfg.secretAccessKey,
      service: 's3',
      region: 'auto',
    }),
    base: `https://${cfg.accountId}.r2.cloudflarestorage.com/${cfg.bucket}`,
  }
}

/** prefix 아래 객체 키 전부 (ListObjectsV2, 이어받기 포함). */
async function listKeys(cfg: R2Cfg, prefix: string): Promise<string[]> {
  const { r2, base } = client(cfg)
  const keys: string[] = []
  let token: string | null = null
  do {
    const url = new URL(base)
    url.searchParams.set('list-type', '2')
    url.searchParams.set('prefix', prefix)
    if (token) url.searchParams.set('continuation-token', token)
    const res = await fetch(await r2.sign(new Request(url, { method: 'GET' })))
    if (!res.ok) throw new Error(`R2 list ${prefix} failed: ${res.status}`)
    const xml = await res.text()
    for (const m of xml.matchAll(/<Key>([^<]+)<\/Key>/g)) keys.push(m[1])
    token = /<IsTruncated>true<\/IsTruncated>/.test(xml)
      ? (xml.match(/<NextContinuationToken>([^<]+)<\/NextContinuationToken>/)?.[1] ?? null)
      : null
  } while (token)
  return keys
}

/** 개별 키 삭제. 404 는 성공 취급 (이미 없음). */
export async function deleteKeys(cfg: R2Cfg, keys: string[]): Promise<number> {
  if (keys.length === 0) return 0
  const { r2, base } = client(cfg)
  let deleted = 0
  for (const key of keys) {
    try {
      const res = await fetch(
        await r2.sign(new Request(`${base}/${key}`, { method: 'DELETE' })),
      )
      if (res.ok || res.status === 404) deleted++
    } catch {
      // 실패한 키는 남는다. 탈퇴 흐름을 막지 않는다 — 다음 정리 도구가 본다.
    }
  }
  return deleted
}

/** 소유자 폴더 통째로 삭제. 탈퇴·익명 90일 정리가 쓰는 단 하나의 경로. */
export async function deleteOwnerThumbnails(
  cfg: R2Cfg,
  owner: string,
): Promise<number> {
  return deleteKeys(cfg, await listKeys(cfg, `thumbnails/${owner}/`))
}
