import type { Route } from "./+types/_index";

export function meta(_: Route.MetaArgs) {
  return [
    { title: "AI 관상가 — 공유 링크 host" },
    { name: "description", content: "얼굴로 읽는 나와 우리의 관계." },
  ];
}

export default function Index() {
  return (
    <main className="landing">
      <h1>AI 관상가</h1>
      <p>이 페이지는 공유 link 의 host 입니다.</p>
      <p>받으신 link 가 <code>/r/abc12345</code> 형식이라면 그쪽으로 직접 이동하세요.</p>
      <a className="cta-primary" href="/r/demo">데모 카드 보기 →</a>
    </main>
  );
}
