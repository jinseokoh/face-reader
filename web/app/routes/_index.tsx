import type { Variants } from 'motion/react'
import { useEffect, useRef, useState } from 'react'
import { FlipCard } from '../components/FlipCard'
import { TextAnimate } from '../components/TextAnimate'
import { fetchDailyFaces } from '../lib/supabase'
import { renderDailyFace, type DailyFaceCard } from '../lib/traits'
import type { Route } from './+types/_index'

/** Science Integration hover 설명부 — 문자별 blurInUp (blur 10px→0 ·
 *  y 20→0), 0.03s stagger. 시작 지연 없음 — hover 즉시 재생. */
const DELAY_BLUR_VARIANTS: Variants = {
  hidden: { opacity: 0, y: 20, filter: 'blur(10px)' },
  show: (i: number) => ({
    opacity: 1,
    y: 0,
    filter: 'blur(0px)',
    transition: { delay: i * 0.03, duration: 0.3 },
  }),
}

/**
 * 오늘 등록된 관상 그리드 필터 — 출시 전 테스트 스위치 (baseline §14 daily_faces).
 *   todayOnly  — KST 오늘 분석(updated_at)만
 *   optedOnly  — 설정 > 오늘 등록된 관상 공개 를 켠 사용자만
 *   myFaceOnly — 내 관상(my-face) 행만
 * 오픈 시 나머지 두 값도 true 로.
 */
const DAILY_FACES = {
  todayOnly: true,
  optedOnly: false,
  myFaceOnly: false,
  limit: 60,
}

export async function loader({ context }: Route.LoaderArgs) {
  const env = context.cloudflare.env
  const rows = await fetchDailyFaces(env, DAILY_FACES)
  const cards = rows
    .map((r) => {
      const card = renderDailyFace(r.body, env.R2_CDN_BASE)
      return card && { ...card, opted: r.opted }
    })
    .filter((c): c is DailyFaceCard & { opted: boolean } => c !== null)
  return { cards }
}

export function meta(_: Route.MetaArgs) {
  const title = '관상은 과학이다'
  const description = '안면 계측 데이터 기반 인공지능 관상앱'
  const ogImage = 'https://cdn.facely.kr/assets/og.png'
  const url = 'https://facely.kr'
  return [
    { title },
    { name: 'description', content: description },
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
    // canonical — http/https 두 주소가 같은 내용을 서빙해 Google 이 서로 다른
    // URL 로 세는 것을 막는다 (GSC 에 http://facely.kr/ 와 https://facely.kr/ 가
    // 둘 다 잡혀 있다). sitemap.xml 의 <loc> 과 정확히 같은 형태로 적는다.
    { tagName: 'link', rel: 'canonical', href: 'https://facely.kr/' },
  ]
}

/**
 * 노출 미허용 사용자 썸네일 — <img> 대신 캔버스에 축소(36×36)→스무딩 없는
 * 확대로 모자이크 타일만 그린다. 페이지에 원본 <img> 가 없어 길게 눌러/
 * 우클릭 저장이 안 되고, cross-origin 이미지라 캔버스도 taint 되어
 * toDataURL 추출이 막힌다 (ctx.filter blur 는 Safari 미지원이라 축소-확대
 * 방식 사용). 36 은 인상착의는 남고 인물 특정은 어려운 절충값 — 조정은
 * MOSAIC_RES 하나로.
 */
const MOSAIC_RES = 36
function BlurredThumb({ src, alt }: { src: string; alt: string }) {
  const ref = useRef<HTMLCanvasElement>(null)
  useEffect(() => {
    const canvas = ref.current
    if (!canvas) return
    const img = new Image()
    img.onload = () => {
      const ctx = canvas.getContext('2d')
      if (!ctx) return
      const off = document.createElement('canvas')
      off.width = MOSAIC_RES
      off.height = MOSAIC_RES
      const octx = off.getContext('2d')
      if (!octx) return
      octx.drawImage(img, 0, 0, MOSAIC_RES, MOSAIC_RES)
      ctx.imageSmoothingEnabled = false
      ctx.drawImage(off, 0, 0, canvas.width, canvas.height)
    }
    img.src = src
  }, [src])
  return (
    <canvas
      ref={ref}
      width={200}
      height={200}
      className="daily-face-thumb"
      role="img"
      aria-label={alt}
    />
  )
}

export default function Index({ loaderData }: Route.ComponentProps) {
  const { cards } = loaderData
  // ⓒ 라인 전체가 hover 대상 — 올리면 즉시 재생, 머무는 동안 유지, 벗어나면
  // 즉시 제거. 타이머 없음. key 카운터라 재진입 때마다 처음부터 재생.
  // (라인 전체라 예전 "링크 글자 가장자리 enter/leave 연사" 문제도 없음.)
  const [siShown, setSiShown] = useState(0)
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

      <div className="landing-qr">
        <img
          src="/qr-code.svg"
          alt="앱 다운로드 QR 코드"
          width={168}
          height={168}
          className="landing-qr-img"
        />
        <p className="landing-qr-caption">카메라로 스캔해 앱 받기</p>
      </div>

      {cards.length > 0 && (
        <section className="daily-faces">
          <h2 className="daily-faces-title">오늘 등록된 관상</h2>
          <p className="daily-faces-caption">
            <span className="daily-faces-bonus-pill">
              관상 노출을 허용하시면 보너스 3코인 지급합니다.
            </span>
          </p>
          <ul className="daily-faces-grid">
            {cards.map((c, i) => (
              // 썸네일 hover/focus 시 카드가 뒤집히며 관상 3순위 노출 (FlipCard).
              <li key={i} className="daily-face-card">
                <FlipCard
                  front={
                    c.opted ? (
                      <img
                        src={c.thumbUrl}
                        alt={`${c.demoLabel} ${c.typeLabel}`}
                        className="daily-face-thumb"
                        loading="lazy"
                      />
                    ) : (
                      <BlurredThumb
                        src={c.thumbUrl}
                        alt={`${c.demoLabel} ${c.typeLabel}`}
                      />
                    )
                  }
                  back={
                    <div className="daily-face-back">
                      {c.top3.map((t, rank) => (
                        <p key={t.key}>
                          {rank + 1}. {t.labelKo}{' '}
                          <span className="score">{t.score.toFixed(1)}</span>
                        </p>
                      ))}
                    </div>
                  }
                />
                <p className="daily-face-demo">{c.demoLabel}</p>
                <p className="daily-face-type">{c.typeLabel}</p>
              </li>
            ))}
          </ul>
        </section>
      )}

      <footer className="landing-footer">
        <a href="/terms">이용약관</a>
        <span aria-hidden="true">·</span>
        <a href="/privacy">개인정보처리방침</a>
        <span aria-hidden="true">·</span>
        <a href="/contact">요청폼</a>
      </footer>

      <div className="landing-legal">
        <p>
          상호명 에스아이 (S.I.) | 사업장소재지 서울특별시 강남구 선릉로 222 |
          대표자 오진석 a.k.a. 공대삼촌 | 사업자 등록번호 889-15-02079 |
          통신판매업신고 제 2024-서울강남-02200호 | 이메일 uncle@facely.kr
        </p>
        <p
          onMouseEnter={() => setSiShown((k) => k + 1)}
          onMouseLeave={() => setSiShown(0)}
        >
          ⓒ 2026{' '}
          <a
            href="https://scienceintegration.com"
            target="_blank"
            rel="noreferrer"
            className="landing-si"
          >
            Science Integration
          </a>
        </p>
        {/* 높이 예약 — hover 시 레이아웃이 밀리지 않게 빈 줄을 상시 유지 */}
        <p className="landing-legal-desc">
          {siShown > 0 && (
            <TextAnimate key={siShown} variants={DELAY_BLUR_VARIANTS}>
              {'Connecting people with science'}
            </TextAnimate>
          )}
        </p>
      </div>
    </main>
  )
}
