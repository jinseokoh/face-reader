import {
  Links,
  Meta,
  Outlet,
  Scripts,
  ScrollRestoration,
  isRouteErrorResponse,
} from "react-router";
import type { Route } from "./+types/root";
import "./app.css";

export function Layout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="ko">
      <head>
        <meta charSet="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <Meta />
        <Links />
      </head>
      <body>
        {children}
        <ScrollRestoration />
        <Scripts />
      </body>
    </html>
  );
}

export default function App() {
  return <Outlet />;
}

export function ErrorBoundary({ error }: Route.ErrorBoundaryProps) {
  let title = "오류가 발생했습니다";
  let detail = "잠시 후 다시 시도해 주세요.";
  if (isRouteErrorResponse(error)) {
    if (error.status === 404) {
      title = "공유 카드를 찾을 수 없습니다";
      detail = "만료되었거나 잘못된 link 입니다.";
    } else if (error.status === 410) {
      title = "만료된 카드입니다";
      detail = "공유 link 는 90일 동안 유효합니다.";
    } else {
      detail = error.statusText || detail;
    }
  }
  return (
    <main className="error">
      <h1>{title}</h1>
      <p>{detail}</p>
    </main>
  );
}
