import type { Route } from "./+types/g.$id";
import { CTA } from "../components/CTA";
import { CameraTeaser } from "../components/CameraTeaser";
import { fetchTeam, type TeamPayload } from "../lib/supabase";

/**
 * `GET /g/:id` — 교감도 그룹 (P3). 한 라우트, 두 얼굴:
 *   - 마감 전 = 초대장 (참여자 칩 + "당신 자리가 비어 있어요" + 앱 유도)
 *   - 마감 후 = 결과 쇼케이스 (이름 + 밴드 이모지 매트릭스, 사진/점수 없음)
 *   - 마감 후 payload 없음 = 48h cron 이 닫은 방 — 3명 이상이면 owner 앱이
 *     payload 를 backfill 할 때까지 대기 안내, 미만이면 인원 미달 종료 안내.
 *     닫힌 방은 합류 불가라 초대장·티저를 렌더하면 안 된다.
 *
 * teams.matrix_payload 가 있으면 결과, 없으면 초대장. 밴드는 색 대신 이모지
 * (🟢🔵🟠🔴) 로만 표기해 웹 4색 팔레트를 지킨다.
 */
export async function loader({ params, request, context }: Route.LoaderArgs) {
  const env = context.cloudflare.env;
  const team = await fetchTeam(env, params.id);
  if (!team) throw new Response("Not Found", { status: 404 });
  const origin = env.WEBAPP_BASE ?? new URL(request.url).origin;
  return {
    team,
    appOpenUrl: `${origin}/g/${params.id}/open`,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    canonicalUrl: `${origin}/g/${params.id}`,
    // 링크 스크랩(카톡·문자 등) 미리보기 이미지 — 공용 배너(800x420, OG 표준
    // 1.91:1). /r/:id 와 동일하게 R2 CDN 서빙 (번들 아님 — 교체 시 재배포 불필요).
    ogImage: `${env.R2_CDN_BASE}/assets/og.png`,
  };
}

export function meta({ data }: Route.MetaArgs) {
  if (!data) return [{ title: "그룹을 찾을 수 없습니다" }];
  const t = data.team;
  const title = t.closed
    ? `${t.title} — 케미 결과`
    : `${t.title} — 케미 그룹 초대`;
  const desc = t.closed
    ? "관상으로 풀어본 우리 그룹의 케미 결과"
    : `${t.memberNames.length}명이 참여 중 · 당신 자리가 비어 있어요`;
  return [
    { title },
    { name: "description", content: desc },
    // 멤버 이름이 노출되므로 검색엔진 indexing 차단.
    { name: "robots", content: "noindex,nofollow" },
    { property: "og:type", content: "website" },
    { property: "og:title", content: title },
    { property: "og:description", content: desc },
    { property: "og:url", content: data.canonicalUrl },
    // og:image 부재 시 카톡 링크 스크랩이 텍스트-only 로 떨어진다 — 크기
    // 힌트까지 명시해 2:1 배너가 크게 보이게 (share.tsx 와 동일 패턴).
    { property: "og:image", content: data.ogImage },
    { property: "og:image:width", content: "800" },
    { property: "og:image:height", content: "420" },
    { name: "twitter:card", content: "summary_large_image" },
  ];
}

export default function Group({ loaderData }: Route.ComponentProps) {
  const { team } = loaderData;
  return (
    <main className="share">
      {team.closed && team.payload ? (
        <Showcase payload={team.payload} />
      ) : team.closed ? (
        <ClosedNotice title={team.title} memberCount={team.memberNames.length} />
      ) : (
        <>
          <Invite title={team.title} names={team.memberNames} />
          {/* 비연락처 설치 전 티저 — 정면 1장으로 미리보기 → 설치 유도. */}
          <CameraTeaser
            team={team}
            appOpenUrl={loaderData.appOpenUrl}
            appStoreUrl={loaderData.appStoreUrl}
            playStoreUrl={loaderData.playStoreUrl}
          />
        </>
      )}
      <CTA
        appOpenUrl={loaderData.appOpenUrl}
        appStoreUrl={loaderData.appStoreUrl}
        playStoreUrl={loaderData.playStoreUrl}
      />
    </main>
  );
}

function Invite({ title, names }: { title: string; names: string[] }) {
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <h1 style={{ fontSize: 24, color: "#1a1a1a", margin: 0 }}>{title}</h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        {names.length}명이 참여 중 · 당신 자리가 비어 있어요
      </p>
      {names.length > 0 && (
        <div
          style={{
            display: "flex",
            flexWrap: "wrap",
            gap: 8,
            justifyContent: "center",
            marginTop: 16,
          }}
        >
          {names.map((n, i) => (
            <Chip key={i} label={n} />
          ))}
        </div>
      )}
    </section>
  );
}

function ClosedNotice({
  title,
  memberCount,
}: {
  title: string;
  memberCount: number;
}) {
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <h1 style={{ fontSize: 24, color: "#1a1a1a", margin: 0 }}>{title}</h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        {memberCount >= 3
          ? "모집이 끝났습니다. 결과 발표를 기다리는 중입니다."
          : "인원이 모이지 않아 종료된 그룹입니다."}
      </p>
    </section>
  );
}

function Showcase({ payload }: { payload: TeamPayload }) {
  const { members, pairs, best } = payload;
  const bandOf = (i: number, j: number) => {
    const a = Math.min(i, j);
    const b = Math.max(i, j);
    return pairs.find((p) => p.a === a && p.b === b) ?? null;
  };

  return (
    <section style={{ padding: "24px 16px" }}>
      <h1
        style={{
          fontSize: 24,
          color: "#1a1a1a",
          textAlign: "center",
          margin: 0,
        }}
      >
        {payload.title}
      </h1>
      <p
        style={{
          color: "#666",
          fontSize: 13,
          textAlign: "center",
          marginTop: 4,
        }}
      >
        케미 결과 발표
      </p>

      {best.length > 0 && (
        <div
          style={{
            background: "#f7f7f8",
            borderRadius: 12,
            padding: 16,
            marginTop: 16,
          }}
        >
          {best.map((h, k) => {
            const band = bandOf(h.a, h.b);
            return (
              <div key={k} style={{ fontSize: 16, color: "#1a1a1a" }}>
                🏆 {members[h.a]} × {members[h.b]}
                {band ? ` ${band.e} ${band.l}` : ""}
              </div>
            );
          })}
        </div>
      )}

      <div style={{ overflowX: "auto", marginTop: 16 }}>
        <table style={{ borderCollapse: "collapse", margin: "0 auto" }}>
          <thead>
            <tr>
              <th />
              {members.map((n, j) => (
                <th key={j} style={head}>
                  {n}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {members.map((n, i) => (
              <tr key={i}>
                <th style={{ ...head, textAlign: "right", paddingRight: 8 }}>
                  {n}
                </th>
                {members.map((_, j) => (
                  <td key={j} style={cell}>
                    {i === j ? "·" : (bandOf(i, j)?.e ?? "")}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function Chip({ label }: { label: string }) {
  return (
    <span
      style={{
        background: "#f7f7f8",
        borderRadius: 10,
        padding: "4px 12px",
        fontSize: 14,
        color: "#1a1a1a",
      }}
    >
      {label}
    </span>
  );
}

const head: React.CSSProperties = {
  fontSize: 12,
  color: "#666",
  fontWeight: 400,
  padding: 4,
  whiteSpace: "nowrap",
};

const cell: React.CSSProperties = {
  width: 36,
  height: 36,
  textAlign: "center",
  fontSize: 16,
  border: "1px solid #f7f7f8",
};
