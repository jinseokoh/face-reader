import { useEffect } from 'react'
import type { Route } from './+types/r.$id.open'

/**
 * `GET /r/:id/open` — **앱 진입 전용 nested bridge route**.
 *
 * `/r/:id` (readable preview) 와 같은 resource 의 sub-action. CTA 가 이쪽으로
 * navigate 하면 iOS Universal Link / Android App Link 가 가로채 Flutter 앱의
 * deep-link stream 으로 흘려준다. 앱은 받은 uuid 로 ReportPage(received) 를
 * 띄워 사용자가 북마크 가능.
 *
 * **왜 `/r/:id` 와 분리?** 카톡 카드 preview tap → Safari 가 `/r/:id` 로 진입.
 * 사용자가 같은 페이지의 CTA 를 다시 `/r/:id` 로 보내면 Safari 는 "same URL"
 * 로 간주해 navigate 자체를 안 함 → universal link intercept 발동 안 함.
 * `/r/:id/open` 은 다른 path 라 Safari 가 navigate 시도 → OS 가 가로챔.
 *
 * **앱 미설치 fallback**: useEffect 가 universal link 발사 후 1.5s 뒤 still
 * visible 이면 App Store / Play Store 로 redirect.
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

export default function OpenBridge({ loaderData }: Route.ComponentProps) {
  const { id, appStoreUrl, playStoreUrl, webappBase } = loaderData

  useEffect(() => {
    const ua = navigator.userAgent
    const isIOS = /iPhone|iPad|iPod/.test(ua)
    const isAndroid = /Android/.test(ua)

    // Desktop 등 unsupported 환경 — readable preview 로 redirect.
    if (!isIOS && !isAndroid) {
      window.location.replace(`${webappBase}/r/${id}`)
      return
    }

    // Universal/App Link target — `/r/{id}/open` 자체로 OS intercept.
    // AASA components 가 `/r/*` 와일드카드라 sub-path 도 매칭. 앱 설치돼 있으면
    // OS 가 가로채 Flutter 앱 launch, 미설치면 Safari 가 그대로 이 페이지에
    // 머물러 useEffect fallback timer 가 store 로 보낸다.
    const universalLink = `${webappBase}/r/${id}/open`
    const storeUrl = isIOS ? appStoreUrl : playStoreUrl
    const startedAt = Date.now()

    window.location.href = universalLink

    const fallback = window.setTimeout(() => {
      if (
        Date.now() - startedAt < 2500 &&
        document.visibilityState === 'visible'
      ) {
        window.location.href = storeUrl
      }
    }, 1500)

    return () => window.clearTimeout(fallback)
  }, [id, appStoreUrl, playStoreUrl, webappBase])

  return (
    <main className="bridge">
      <p className="bridge-text">관상은 과학이다 앱을 여는 중…</p>
      <noscript>
        <p>JavaScript 가 비활성 상태입니다. 아래 link 로 앱을 받아주세요.</p>
        <a href={appStoreUrl}>App Store</a>
        <br />
        <a href={playStoreUrl}>Google Play</a>
      </noscript>
    </main>
  )
}
