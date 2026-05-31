import { useEffect, useState } from 'react'
import type { Route } from './+types/r.$id.open'

/**
 * `GET /r/:id/open` — 앱 진입 bridge.
 *
 * 앱은 `https://facely.kr/r/*` 를 App Link(Android, autoVerify) / Universal Link
 * (iOS, applinks:facely.kr) 로만 받는다. 커스텀 스킴 `facely://` 는 auth-callback
 * 전용이라 /r/ 진입엔 못 쓴다.
 *
 * 플랫폼별 전략:
 *   • Android (Chrome·카카오 인앱 모두): `intent://` — 앱 있으면 launch,
 *     없으면 `browser_fallback_url`(스토어)을 OS 가 자동 처리. 인앱 webview 도 지원.
 *   • iOS Safari: Universal Link(`/r/:id`) 1회 시도(현재 `/open` 과 다른 path 라
 *     self-loop 없음) → 안 열리면 수동 UI.
 *   • iOS 카카오 등 인앱 webview: Universal Link 가로채기 불가 → 즉시 수동 UI
 *     ("다른 브라우저로 열기" 안내 + 스토어/웹 link).
 *
 * ⚠️ 옛 버그: universalLink 를 `${webappBase}/r/${id}/open`(= 현재 URL)로 두고
 * `location.href` 했더니 자기 자신 재로드 → 무한 루프. self-URL navigate 금지.
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
  const [stuck, setStuck] = useState(false)
  const [storeUrl, setStoreUrl] = useState(playStoreUrl)

  useEffect(() => {
    const ua = navigator.userAgent
    const isIOS = /iPhone|iPad|iPod/.test(ua)
    const isAndroid = /Android/.test(ua)
    const isKakao = /KAKAOTALK/i.test(ua)
    const store = isIOS ? appStoreUrl : playStoreUrl
    setStoreUrl(store)

    // Desktop 등 미지원 — readable preview 로.
    if (!isIOS && !isAndroid) {
      window.location.replace(`${webappBase}/r/${id}`)
      return
    }

    if (isAndroid) {
      // intent:// — 앱 launch or 스토어 fallback 을 OS 가 처리 (카카오 인앱 포함).
      window.location.href =
        `intent://facely.kr/r/${id}` +
        `#Intent;scheme=https;package=com.scienceintegration.facely;` +
        `S.browser_fallback_url=${encodeURIComponent(store)};end`
      // 극히 드물게 아무 일도 안 나면 수동 UI.
      const t = window.setTimeout(() => setStuck(true), 3000)
      return () => window.clearTimeout(t)
    }

    // iOS 카카오 등 인앱 webview: Universal Link 불가 → 즉시 수동 안내.
    if (isKakao) {
      setStuck(true)
      return
    }

    // iOS Safari: Universal Link 1회 시도 → 앱 있으면 OS 가 가로채 launch(페이지
    // hidden) → 타이머 미발동. 안 열리면 stuck UI.
    const startedAt = Date.now()
    window.location.href = `${webappBase}/r/${id}`
    const t = window.setTimeout(() => {
      if (
        document.visibilityState === 'visible' &&
        Date.now() - startedAt < 3000
      ) {
        setStuck(true)
      }
    }, 1500)
    return () => window.clearTimeout(t)
  }, [id, appStoreUrl, playStoreUrl, webappBase])

  return (
    <main className="bridge">
      {stuck ? (
        <>
          <p className="bridge-text">앱이 자동으로 열리지 않았어요</p>
          <p className="bridge-sub">
            카카오 등 앱 안의 브라우저에서는 앱 열기가 제한됩니다. 오른쪽 위 메뉴에서
            <b> 다른 브라우저로 열기</b> 후 다시 시도하거나, 아래에서 진행해 주세요.
          </p>
          <a className="bridge-link" href={`${webappBase}/r/${id}`}>
            웹에서 결과 보기
          </a>
          <a className="bridge-link" href={storeUrl}>
            앱 설치하기
          </a>
        </>
      ) : (
        <p className="bridge-text">관상은 과학이다 앱을 여는 중…</p>
      )}
      <noscript>
        <p>JavaScript 가 비활성 상태입니다. 아래 link 로 앱을 받아주세요.</p>
        <a href={appStoreUrl}>App Store</a>
        <br />
        <a href={playStoreUrl}>Google Play</a>
      </noscript>
    </main>
  )
}
