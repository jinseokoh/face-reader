import type { Route } from "./+types/_index";
import { encode } from "../lib/share-id";

const DEMO_A = "00000000-0000-0000-0000-000000000061";
const DEMO_B = "00000000-0000-0000-0000-000000000062";

export async function loader({ context }: Route.LoaderArgs) {
  const env = context.cloudflare.env;
  if (!env.SHARE_TOKEN_SECRET) {
    return { demoSolo: null, demoCompat: null };
  }
  const [demoSolo, demoCompat] = await Promise.all([
    encode({ type: "solo", userA: DEMO_A }, env.SHARE_TOKEN_SECRET),
    encode({ type: "compat", userA: DEMO_A, userB: DEMO_B }, env.SHARE_TOKEN_SECRET),
  ]);
  return { demoSolo, demoCompat };
}

export function meta(_: Route.MetaArgs) {
  return [
    { title: "AI 관상가 — 공유 링크 host" },
    { name: "description", content: "얼굴로 읽는 나와 우리의 관계." },
  ];
}

export default function Index({ loaderData }: Route.ComponentProps) {
  return (
    <main className="landing">
      <h1>AI 관상가</h1>
      <p>이 페이지는 공유 link 의 host 입니다.</p>
      <p>
        받으신 link 가 <code>/r/...</code> 형식이라면 그쪽으로 직접 이동하세요.
      </p>
      {loaderData.demoSolo && loaderData.demoCompat && (
        <p>
          <a className="cta-primary" href={`/r/${loaderData.demoSolo}`}>
            데모 — 솔로 카드
          </a>
          <a className="cta-primary" href={`/r/${loaderData.demoCompat}`}>
            데모 — 궁합 카드
          </a>
        </p>
      )}
    </main>
  );
}
