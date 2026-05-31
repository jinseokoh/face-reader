import { redirect } from 'react-router'
import type { Route } from './+types/app'

/**
 * `GET /app` — **store redirector**.
 *
 * UA 보고 iOS → App Store, Android → Play Store, 그 외 (desktop/bot) → 홈으로.
 * 카톡·인스타·문자·QR 등 모든 채널에서 "앱 받기" 단일 link 로 쓰기 위함.
 * 서버 loader 에서 즉시 `redirect()` 라 빈 페이지 깜빡임 없음.
 */

export function meta(_: Route.MetaArgs) {
  return [
    { title: '관상은 과학이다 앱 받기' },
    { name: 'robots', content: 'noindex,nofollow' },
  ]
}

export async function loader({ request, context }: Route.LoaderArgs) {
  const env = context.cloudflare.env
  const ua = request.headers.get('user-agent') ?? ''

  if (/iPhone|iPad|iPod/i.test(ua)) {
    return redirect(env.APP_STORE_URL)
  }
  if (/Android/i.test(ua)) {
    return redirect(env.PLAY_STORE_URL)
  }

  return {
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    webappBase: env.WEBAPP_BASE,
  }
}

export default function AppRedirect({ loaderData }: Route.ComponentProps) {
  const { appStoreUrl, playStoreUrl, webappBase } = loaderData

  return (
    <main className="bridge">
      <p className="bridge-text">
        관상은 과학이다 앱은 모바일에서 사용할 수 있어요.
      </p>
      <p>
        <a href={appStoreUrl}>App Store</a>
        {' · '}
        <a href={playStoreUrl}>Google Play</a>
      </p>
      <p>
        <a href={webappBase}>홈으로</a>
      </p>
    </main>
  )
}
