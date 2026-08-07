/**
 * FCM v1 발송 공용부 — /api/push/* 라우트가 공유한다.
 * service account JWT(RS256, WebCrypto) → OAuth token(인스턴스 캐시) →
 * 기기별 발송. UNREGISTERED/INVALID token 은 그 자리에서 삭제.
 */

export type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

export type PushEnv = {
  SUPABASE_URL: string
  SUPABASE_SERVICE_ROLE_KEY: string
}

// OAuth 토큰 캐시 — worker 인스턴스 생존 동안 재사용 (만료 5분 전 갱신).
let cachedToken: { token: string; exp: number } | null = null

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

export async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000)
  if (cachedToken && cachedToken.exp - 300 > now) return cachedToken.token
  const enc = new TextEncoder()
  const header = b64url(enc.encode(JSON.stringify({ alg: 'RS256', typ: 'JWT' })))
  const claims = b64url(
    enc.encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: 'https://www.googleapis.com/auth/firebase.messaging',
        aud: 'https://oauth2.googleapis.com/token',
        iat: now,
        exp: now + 3600,
      }),
    ),
  )
  const input = `${header}.${claims}`
  const pem = sa.private_key.replace(/-----[^-]+-----/g, '').replace(/\s+/g, '')
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0))
  const key = await crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const sig = new Uint8Array(
    await crypto.subtle.sign('RSASSA-PKCS1-v1_5', key, enc.encode(input)),
  )
  const jwt = `${input}.${b64url(sig)}`
  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: `grant_type=${encodeURIComponent('urn:ietf:params:oauth:grant-type:jwt-bearer')}&assertion=${jwt}`,
  })
  if (!res.ok) throw new Error(`oauth ${res.status}`)
  const data = (await res.json()) as { access_token: string; expires_in: number }
  cachedToken = { token: data.access_token, exp: now + data.expires_in }
  return data.access_token
}

/** target 유저의 전 기기로 발송. 반환 = 성공 발송 수. */
export async function sendToUser(
  env: PushEnv,
  sa: ServiceAccount,
  targetUid: string,
  message: {
    title: string
    body: string
    data: Record<string, string>
    channelId: string
  },
): Promise<number> {
  const svc = {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
  }
  const r = await fetch(
    `${env.SUPABASE_URL}/rest/v1/push_tokens?select=token&user_id=eq.${targetUid}`,
    { headers: svc },
  )
  const tokens = r.ok ? ((await r.json()) as Array<{ token: string }>) : []
  if (tokens.length === 0) return 0

  const accessToken = await fcmAccessToken(sa)
  let sent = 0
  await Promise.all(
    tokens.map(async ({ token }) => {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: 'POST',
          headers: {
            Authorization: `Bearer ${accessToken}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            message: {
              token,
              notification: { title: message.title, body: message.body },
              data: message.data,
              android: {
                priority: 'HIGH',
                // 채널 미지정이면 기본 채널(중요도 보통)로 빠져 무음 —
                // 앱이 생성해 둔 중요도 높음 채널로 지정.
                notification: {
                  channel_id: message.channelId,
                  notification_priority: 'PRIORITY_HIGH',
                  default_sound: true,
                },
              },
            },
          }),
        },
      )
      if (res.ok) {
        sent++
        return
      }
      // 만료·삭제된 token 정리 — 다음 발송부터 시도 자체를 없앤다.
      if (res.status === 404 || res.status === 400) {
        await fetch(
          `${env.SUPABASE_URL}/rest/v1/push_tokens?token=eq.${encodeURIComponent(token)}`,
          { method: 'DELETE', headers: { ...svc, Prefer: 'return=minimal' } },
        )
      }
    }),
  )
  return sent
}
