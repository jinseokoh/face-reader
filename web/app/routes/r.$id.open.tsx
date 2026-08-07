import type { Route } from './+types/r.$id.open'
import { OpenBridge } from '../components/OpenBridge'

/**
 * `GET /r/:id/open` — 공유 카드(관상·궁합) 앱 진입 bridge. 로직은 OpenBridge 공용.
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
  return <OpenBridge seg="r" {...loaderData} />
}
