import { sendToUser, type ServiceAccount } from '../lib/push'
import type { Route } from './+types/api.push.match'

/**
 * POST /api/push/match — 매칭 응답 푸시 발송 (DB trigger 전용).
 *
 * team_matches 의 consent 변경 trigger(pg_net)가 호출한다.
 * 인증: `x-push-secret` == FACE_API_SECRET.
 * body: { team_id, target, responder, accepted, opened }
 *
 * 알림 문구 3종 (측정·사실만):
 *   - 개설(둘 다 수락):  "채팅방이 열렸습니다"
 *   - 상대 선수락 대기:  "{닉}님이 채팅을 수락했습니다"
 *   - 거절:              "이번에는 채팅방이 열리지 않았습니다"
 * data.team_id 로 앱이 `/g/{id}` 딥링크 이동.
 */

type PushBody = {
  team_id?: string
  target?: string
  responder?: string
  accepted?: boolean
  opened?: boolean
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
  const [nicks, teams] = await Promise.all([
    get<{ nickname: string | null }>(`users?select=nickname&id=eq.${responder}`),
    get<{ title: string }>(`teams?select=title&id=eq.${team_id}`),
  ])
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
  const sent = await sendToUser(
    { SUPABASE_URL: env.SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY: env.SUPABASE_SERVICE_ROLE_KEY },
    sa,
    target,
    { title, body: messageBody, data: { team_id, kind }, channelId: 'match' },
  )
  return Response.json({ sent })
}
