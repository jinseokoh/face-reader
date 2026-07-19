import { sendToUser, type ServiceAccount } from '../lib/push'
import type { Route } from './+types/api.push.chat'

/**
 * POST /api/push/chat — 채팅 메시지 푸시 발송 (DB trigger 전용).
 *
 * team_messages INSERT trigger(pg_net)가 호출한다.
 * 인증: `x-push-secret` == FACE_API_SECRET.
 * body: { team_id, target, sender, preview }
 *
 * 알림 = "{보낸이 닉네임}" / 메시지 미리보기. data.kind='chat' 으로 앱이
 * 채팅방(/chat/{teamId})으로 직행하고, 그 방을 보고 있는 중이면 표시를
 * 억제한다(Realtime 이 메시지를 즉시 그리므로 알림은 소음).
 */

type ChatBody = {
  team_id?: string
  target?: string
  sender?: string
  preview?: string
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

  const body = (await request.json()) as ChatBody
  const { team_id, target, sender } = body
  if (!team_id || !target || !sender) {
    return new Response('Bad Request', { status: 400 })
  }

  const nickRes = await fetch(
    `${env.SUPABASE_URL}/rest/v1/users?select=nickname&id=eq.${sender}`,
    {
      headers: {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
      },
    },
  )
  const nicks = nickRes.ok
    ? ((await nickRes.json()) as Array<{ nickname: string | null }>)
    : []
  const nick = nicks[0]?.nickname ?? '상대'

  const sa = JSON.parse(env.FCM_SERVICE_ACCOUNT) as ServiceAccount
  const sent = await sendToUser(
    { SUPABASE_URL: env.SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY: env.SUPABASE_SERVICE_ROLE_KEY },
    sa,
    target,
    {
      title: nick,
      body: body.preview ?? '새 메시지가 도착했습니다',
      data: { team_id, kind: 'chat' },
      channelId: 'chat',
    },
  )
  return Response.json({ sent })
}
