import type { Route } from './+types/_index'

export function meta(_: Route.MetaArgs) {
  const title = '관상은 과학이다'
  const description = '안면 계측 데이터 기반 인공지능 관상앱'
  const ogImage = 'https://cdn.facely.kr/assets/800x420.png'
  const url = 'https://facely.kr'
  return [
    { title },
    { name: 'description', content: description },
    { name: 'robots', content: 'noindex,nofollow' },
    // Open Graph — KakaoTalk · Slack · iMessage · Facebook 등 link preview.
    { property: 'og:type', content: 'website' },
    { property: 'og:url', content: url },
    { property: 'og:title', content: title },
    { property: 'og:description', content: description },
    { property: 'og:image', content: ogImage },
    { property: 'og:image:width', content: '800' },
    { property: 'og:image:height', content: '420' },
    { property: 'og:site_name', content: '관상은 과학이다' },
    { property: 'og:locale', content: 'ko_KR' },
    // Twitter / X
    { name: 'twitter:card', content: 'summary_large_image' },
    { name: 'twitter:title', content: title },
    { name: 'twitter:description', content: description },
    { name: 'twitter:image', content: ogImage },
  ]
}

export default function Index() {
  return (
    <main className="landing">
      <img
        src="https://cdn.facely.kr/assets/hero-bg.png"
        alt="facely.kr"
        className="landing-hero-img"
        fetchPriority="high"
      />
      <h1 className="landing-hero">관상은 과학이다</h1>
      <p className="landing-sub">안면 계측 데이터 기반 인공지능 관상앱</p>

      <div className="landing-cta">
        <a href="/app" className="landing-cta-primary">
          앱 다운로드
        </a>
      </div>

      <footer className="landing-footer">
        <a href="/terms">이용약관</a>
        <span aria-hidden="true">·</span>
        <a href="/privacy">개인정보처리방침</a>
        <span aria-hidden="true">·</span>
        <a href="/contact">컨택</a>
      </footer>
    </main>
  )
}
