import {
  Links,
  Meta,
  Outlet,
  Scripts,
  ScrollRestoration,
  isRouteErrorResponse,
} from 'react-router'
import type { Route } from './+types/root'
import './app.css'

export function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta
          name="naver-site-verification"
          content="030f9c075e4b47e60585eecd911d3d5d26d82122"
        />
        <link rel="icon" type="image/svg+xml" href="/favicon.svg?v=2" />
        <Meta />
        <Links />
      </head>
      <body>
        {children}
        <ScrollRestoration />
        <Scripts />
      </body>
    </html>
  )
}

export default function App() {
  return (
    <>
      {/* Overscroll reveal layer — 공대삼촌 react 앱 공통 시그니처 (fruit
          __root.tsx 와 동일 구조). 본문 뒤 fixed 레이어라 평소엔 안 보이고,
          rubber-band 오버스크롤 순간에만 위/아래로 드러난다. */}
      <div className="overscroll-reveal overscroll-top">
        <span>냥이 관상도 과학이다냥~</span>
        <img src="/cat.png" alt="" className="overscroll-img" />
      </div>

      <div className="overscroll-reveal overscroll-bottom">
        <span>공대삼촌이 극강T의 힘을 보여주려고 만들었대.</span>
        <img src="/uncle.png" alt="" className="overscroll-img" />
      </div>

      <div className="app-shell">
        <Outlet />
      </div>
    </>
  )
}

export function ErrorBoundary({ error }: Route.ErrorBoundaryProps) {
  let title = '오류가 발생했습니다'
  let detail = '잠시 후 다시 시도해 주세요.'
  if (isRouteErrorResponse(error)) {
    if (error.status === 404) {
      title = '공유 카드를 찾을 수 없습니다'
      detail = '만료되었거나 잘못된 link 입니다.'
    } else if (error.status === 410) {
      title = '만료된 카드입니다'
      detail = '공유 link 는 90일 동안 유효합니다.'
    } else {
      detail = error.statusText || detail
    }
  }
  return (
    <main className="error">
      <h1>{title}</h1>
      <p>{detail}</p>
    </main>
  )
}
