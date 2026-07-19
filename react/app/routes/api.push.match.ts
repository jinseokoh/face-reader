import type { Route } from './+types/api.push.match'

/**
 * POST /api/push/match — 매칭 응답 푸시 발송 (DB trigger 전용).
 *
 * team_matches 의 consent 변경 trigger(pg_net)가 호출한다.
 * 인증: `x-push-secret` == FACE_API_SECRET.
 * body: { team_id, target, responder, accepted, opened }
 *
 * 흐름: service role 로 응답자 닉네임·방 제목·target 의 push_tokens 조회 →
 * FCM v1 로 기기별 발송. UNREGISTERED/INVALID token 은 그 자리에서 삭제.
 * 알림 문구 3종 (측정·사실만):
 *   - 개설(둘 다 수락):  "채팅방이 열렸습니다"
 *   - 상대 선수락 대기:  "{닉}님이 채팅을 수락했습니다"
 *   - 거절:              "이번에는 채팅방이 열리지 않았습니다"
 * data.team_id 로 앱이 `/g/{id}` 딥링크 이동.
 */

type ServiceAccount = {
  project_id: string
  client_email: string
  private_key: string
}

type PushBody = {
  team_id?: string
  target?: string
  responder?: string
  accepted?: boolean
  opened?: boolean
}

// FCM OAuth 토큰 캐시 — worker 인스턴스 생존 동안 재사용 (만료 5분 전 갱신).
let cachedToken: { token: string; exp: number } | null = null

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
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

export async function action({ request, context }: Route.ActionArgs) {
  if (request.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405 })
  }
  const env = context.cloudflare.env as Env & {
    FACE_API_SECRET?: string
    FCM_SERVICE_ACCOUNT?: string
    SUPABASE_SERVICE_ROLE_KEY?: string
  }
  if (
    !env.FACE_API_SECRET ||
    request.headers.get('x-push-secret') !== env.FACE_API_SECRET
  ) {
    return new Response('Forbidden', { status: 403 })
  }
  if (!env.FCM_SERVICE_ACCOUNT || !env.SUPABASE_SERVICE_ROLE_KEY) {
    return new Response('Server misconfigured', { status: 500 })
  }

  const body = (await request.json()) as PushBody
  const { team_id, target, responder } = body
  if (!team_id || !target || !responder) {
    return new Response('Bad Request', { status: 400 })
  }

  const svc = {
    apikey: env.SUPABASE_SERVICE_ROLE_KEY,
    Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
  }
  const get = async <T>(path: string): Promise<T[]> => {
    const r = await fetch(`${env.SUPABASE_URL}/rest/v1/${path}`, { headers: svc })
    return r.ok ? ((await r.json()) as T[]) : []
  }
  const [tokens, nicks, teams] = await Promise.all([
    get<{ token: string }>(`push_tokens?select=token&user_id=eq.${target}`),
    get<{ nickname: string | null }>(`users?select=nickname&id=eq.${responder}`),
    get<{ title: string }>(`teams?select=title&id=eq.${team_id}`),
  ])
  if (tokens.length === 0) return Response.json({ sent: 0 })

  const nick = nicks[0]?.nickname ?? '상대'
  const roomTitle = teams[0]?.title ?? '케미 매칭'
  let title: string
  let kind: string
  if (body.accepted && body.opened) {
    title = '채팅방이 열렸습니다'
    kind = 'opened'
  } else if (body.accepted) {
    title = `${nick}님이 채팅을 수락했습니다`
    kind = 'accepted'
  } else {
    title = '이번에는 채팅방이 열리지 않았습니다'
    kind = 'closed'
  }
  const messageBody =
    kind === 'opened' ? `${nick}님과 대화를 시작할 수 있습니다 — ${roomTitle}`
    : kind === 'accepted' ? `수락하면 채팅방이 열립니다 — ${roomTitle}`
    : roomTitle

  const sa = JSON.parse(env.FCM_SERVICE_ACCOUNT) as ServiceAccount
  const accessToken = await fcmAccessToken(sa)
  let sent = 0
  await Promise.all(
    tokens.map(async ({ token }) => {
      const r = await fetch(
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
              notification: { title, body: messageBody },
              data: { team_id, kind },
              android: {
                priority: 'HIGH',
                // 앱이 생성해 둔 중요도 높음 채널 — 채널 미지정이면 기본
                // 채널(중요도 보통)로 빠져 소리·화면 팝업 없이 조용히 쌓인다.
                notification: {
                  channel_id: 'match',
                  notification_priority: 'PRIORITY_HIGH',
                  default_sound: true,
                },
              },
            },
          }),
        },
      )
      if (r.ok) {
        sent++
        return
      }
      // 만료·삭제된 token 정리 — 다음 발송부터 시도 자체를 없앤다.
      if (r.status === 404 || r.status === 400) {
        await fetch(
          `${env.SUPABASE_URL}/rest/v1/push_tokens?token=eq.${encodeURIComponent(token)}`,
          { method: 'DELETE', headers: { ...svc, Prefer: 'return=minimal' } },
        )
      }
    }),
  )
  return Response.json({ sent })
}
