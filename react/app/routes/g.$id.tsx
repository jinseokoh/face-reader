import { useState } from "react";
import type { Route } from "./+types/g.$id";
import { CTA } from "../components/CTA";
import { JoinWizard } from "../components/JoinWizard";
import {
  fetchTeam,
  type TeamPayload,
  type TeamShowcase,
} from "../lib/supabase";

/**
 * `GET /g/:id` — 교감도 그룹 (P3). 한 라우트, 두 얼굴:
 *   - 마감 전 = 초대장 (참여자 칩 + "당신 자리가 비어 있어요" + 앱 유도)
 *   - 마감 후 = 결과 쇼케이스 (이름 + 밴드 이모지 매트릭스, 사진/점수 없음)
 *   - 마감 후 payload 없음 = 48h cron 이 닫은 방. 결과표는 **전원 등록**
 *     시에만 생성되므로: 전원이 찼으면 owner 앱의 backfill 대기 안내,
 *     아니면 전원 미충족 종료 안내 (옛 ≥3 기준 폐기, 2026-07-12).
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
    // 웹 카카오 로그인·참여용 공개 config (anon key 는 공개키).
    supabaseUrl: env.SUPABASE_URL ?? "",
    supabaseAnonKey: env.SUPABASE_ANON_KEY ?? "",
    cdnBase: env.R2_CDN_BASE ?? "",
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
    : `${t.members.length}명이 참여 중 · 당신 자리가 비어 있어요`;
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
  // 위저드 진행 중엔 초대장 멤버 칩을 숨긴다 — 위저드의 "비어 있는 자리"
  // 목록과 같은 이름이 이중 노출되어 혼란을 만든다.
  const [wizardActive, setWizardActive] = useState(false);
  // 참여 성립 시 최신 현황 — 헤더 subtitle 3상태의 입력.
  const [joinedInfo, setJoinedInfo] = useState<{
    joined: number;
    total: number;
  } | null>(null);
  return (
    <main className="share">
      {team.closed && team.payload ? (
        <Showcase payload={team.payload} />
      ) : team.closed ? (
        <ClosedNotice title={team.title} allJoined={team.allJoined} />
      ) : (
        <>
          <Invite
            title={team.title}
            members={team.members}
            hideChips={wizardActive}
            wizardActive={wizardActive}
            joinedInfo={joinedInfo}
          />
          {/* 미설치자 웹 참여 위저드 (미리보기 겸용) — 카카오 로그인 →
              슬롯 claim → 정면 캡처 → 그룹 합류까지 브라우저에서 완결. */}
          <JoinWizard
            team={team}
            supabaseUrl={loaderData.supabaseUrl}
            supabaseAnonKey={loaderData.supabaseAnonKey}
            cdnBase={loaderData.cdnBase}
            onProgress={setWizardActive}
            onJoined={setJoinedInfo}
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

function Invite({
  title,
  members,
  hideChips,
  wizardActive,
  joinedInfo,
}: {
  title: string;
  members: TeamShowcase["members"];
  hideChips: boolean;
  /** 위저드 진행 중(로그인·미참여) — subtitle "당신의 자리가 비어 있어요". */
  wizardActive: boolean;
  /** 내 참여가 성립된 뒤의 최신 현황 — null 이면 아직 미참여. */
  joinedInfo: { joined: number; total: number } | null;
}) {
  const joined = joinedInfo?.joined ?? members.filter((m) => m.joined).length;
  const total = joinedInfo?.total ?? members.length;
  // subtitle 3상태: 참여 완료 / 진행 중(로그인·미참여) / 방문만.
  const status =
    joinedInfo != null
      ? "내 관상은 이미 등록했습니다."
      : wizardActive
        ? "당신의 자리가 비어 있어요"
        : `아직 ${Math.max(total - joined, 0)}명이 미등록 중입니다.`;
  // 등록 완료자 먼저 보여준다.
  const ordered = [
    ...members.filter((m) => m.joined),
    ...members.filter((m) => !m.joined),
  ];
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <h1 style={{ fontSize: 24, color: "#1a1a1a", margin: 0 }}>{title}</h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        {total}명 중 {joined}명 등록 · {status}
      </p>
      {!hideChips && ordered.length > 0 && (
        <div className="invite-chips">
          {ordered.map((m, i) => (
            <span
              key={i}
              className={
                m.joined ? "invite-chip" : "invite-chip invite-chip--wait"
              }
            >
              {m.name}
              {m.joined ? " ✓" : ""}
            </span>
          ))}
        </div>
      )}
    </section>
  );
}

function ClosedNotice({
  title,
  allJoined,
}: {
  title: string;
  allJoined: boolean;
}) {
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <h1 style={{ fontSize: 24, color: "#1a1a1a", margin: 0 }}>{title}</h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        {allJoined
          ? "모집이 끝났습니다. 케미 결과표가 만들어지기를 기다리는 중입니다."
          : "전원이 모이지 않아 종료된 그룹입니다."}
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
