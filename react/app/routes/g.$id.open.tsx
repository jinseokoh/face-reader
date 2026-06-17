import type { Route } from './+types/g.$id.open'
import { OpenBridge } from '../components/OpenBridge'

/**
 * `GET /g/:id/open` — 교감도 그룹 초대 앱 진입 bridge. 로직은 OpenBridge 공용.
 * 카톡 '참여하기' 가 가리키는 곳 — 인앱 브라우저에서 앱으로 빠져나간다.
 */

export function meta(_: Route.MetaArgs) {
  return [
    { title: '관상은 과학이다 앱 여는 중…' },
    { name: 'robots', content: 'noindex,nofollow' },
  ]
}

export async function loader({ params, context }: Route.LoaderArgs) {
  const env = context.cloudflare.env
  return {
    id: params.id,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    webappBase: env.WEBAPP_BASE,
  }
}

export default function Open({ loaderData }: Route.ComponentProps) {
  return <OpenBridge seg="g" {...loaderData} />
}
