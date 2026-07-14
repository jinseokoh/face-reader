import { useEffect, useState } from 'react'
import { openInExternalBrowser } from '../lib/inapp'

/**
 * 앱 진입 bridge — `/r/:id/open`(공유 카드) · `/g/:id/open`(교감도 그룹) 공용.
 *
 * 앱은 `https://facely.kr/{r,g}/*` 를 App Link(Android, autoVerify) / Universal
 * Link(iOS, applinks:facely.kr) 로 받는다. 플랫폼별 전략:
 *   • Android (Chrome): `intent://` — 앱 있으면 launch, 없으면 store fallback.
 *   • iOS Safari: Universal Link 1회 시도 → 안 열리면 수동 UI.
 *   • 카카오톡 인앱 브라우저: App Link·intent:// 가 모두 막힌다. `openExternal`
 *     로 기본 브라우저에 이 bridge 를 다시 띄우면 거기서 앱이 열린다.
 *
 * ⚠️ self-loop 금지: readable(`/{seg}/{id}`) 과 bridge(`/{seg}/{id}/open`) 는
 * 서로 다른 path 라 location.href 무한 루프가 없다.
 *
 * 탈출 함수(openInExternalBrowser)는 lib/inapp 에서 공유 — CameraTeaser 도 사용.
 */

export function OpenBridge({
  seg,
  id,
  appStoreUrl,
  playStoreUrl,
  webappBase,
}: {
  seg: 'r' | 'g'
  id: string
  appStoreUrl: string
  playStoreUrl: string
  webappBase: string
}) {
  const [stuck, setStuck] = useState(false)
  const [storeUrl, setStoreUrl] = useState(playStoreUrl)
  const [inKakao, setInKakao] = useState(false)

  const readUrl = `${webappBase}/${seg}/${id}`
  const openUrl = `${webappBase}/${seg}/${id}/open`

  useEffect(() => {
    const ua = navigator.userAgent
    const isIOS = /iPhone|iPad|iPod/.test(ua)
    const isAndroid = /Android/.test(ua)
    const isKakao = /KAKAOTALK/i.test(ua)
    const store = isIOS ? appStoreUrl : playStoreUrl
    setStoreUrl(store)
    setInKakao(isKakao)

    // Desktop 등 미지원 — readable preview 로.
    if (!isIOS && !isAndroid) {
      window.location.replace(readUrl)
      return
    }

    // 카카오톡 인앱 브라우저: 기본 브라우저로 이 bridge 를 다시 띄운다 → 거기서
    // 앱이 열린다. 자동 전환이 무시되는 기기/버전 대비 수동 버튼(stuck)도 노출.
    if (isKakao) {
      openInExternalBrowser(openUrl)
      const t = window.setTimeout(() => setStuck(true), 1500)
      return () => window.clearTimeout(t)
    }

    if (isAndroid) {
      // intent:// — 앱 launch or 스토어 fallback 을 OS 가 처리.
      window.location.href =
        `intent://facely.kr/${seg}/${id}` +
        `#Intent;scheme=https;package=com.scienceintegration.facely;` +
        `S.browser_fallback_url=${encodeURIComponent(store)};end`
      const t = window.setTimeout(() => setStuck(true), 3000)
      return () => window.clearTimeout(t)
    }

    // iOS Safari: Universal Link 1회 시도 → 앱 있으면 OS 가 가로채 launch.
    const startedAt = Date.now()
    window.location.href = readUrl
    const t = window.setTimeout(() => {
      if (
        document.visibilityState === 'visible' &&
        Date.now() - startedAt < 3000
      ) {
        setStuck(true)
      }
    }, 1500)
    return () => window.clearTimeout(t)
  }, [seg, id, appStoreUrl, playStoreUrl, webappBase, readUrl, openUrl])

  const readLabel = seg === 'g' ? '웹에서 보기' : '웹에서 결과 보기'

  return (
    <main className="bridge">
      {stuck ? (
        <>
          <p className="bridge-text">앱이 자동으로 열리지 않았어요</p>
          {inKakao ? (
            <>
              <p className="bridge-sub">
                카카오톡 안에서는 앱 열기가 막혀 있어서, 기본 브라우저를
                사용해서 다시 열어야 해요.
              </p>
              <button
                type="button"
                className="bridge-link bridge-link--primary"
                onClick={() => openInExternalBrowser(openUrl)}
              >
                기본 브라우저로 다시 열기
              </button>
            </>
          ) : (
            <p className="bridge-sub">
              앱이 설치돼 있다면 잠시 후 열려요. 안 열리면 아래에서 진행해
              주세요.
            </p>
          )}
          <a className="bridge-link" href={readUrl}>
            {readLabel}
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
