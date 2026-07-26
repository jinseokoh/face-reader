import { useEffect, useState } from "react";
import { useLoaderData } from "react-router";
import type { Route } from "./+types/g.$id";
import { CTA } from "../components/CTA";
import { JoinWizard } from "../components/JoinWizard";
import { getSupabase } from "../lib/auth";
import {
  bestPair,
  computeTeamPayload,
  photoConsentText,
  remainingGenderSlots,
  submitTeamResult,
  type TeamPayload,
} from "../lib/join";
import { fetchTeamSSR } from "../lib/supabase";

/**
 * `GET /g/:id` — 케미 매칭 (Plan 3). 한 라우트, status 4분기:
 *   - recruiting = 초대장(공약·연령대·n/N 노출) + JoinWizard
 *   - revealing/completed + payload = 결과 쇼케이스 (🏆 Best 카드 + 밴드 매트릭스)
 *   - revealing/completed + payload 없음 + snapshot 있음 = 클라이언트 즉석 계산
 *     (runTeam) 후 (로그인 참가자면) 정본 backfill
 *   - expired 또는 completed + payload/snapshot 둘 다 없음 = 종료 안내
 *
 * 밴드는 색 대신 이모지(🟢🔵🟠🔴)로만 표기해 웹 4색 팔레트를 지킨다.
 */
export async function loader({ context, params }: Route.LoaderArgs) {
  const env = context.cloudflare.env;
  const data = await fetchTeamSSR(env, params.id!);
  if (!data) throw new Response("Not Found", { status: 404 });
  return {
    team: data.team,
    roster: data.roster,
    appOpenUrl: `${env.WEBAPP_BASE}/g/${params.id}/open`,
    appStoreUrl: env.APP_STORE_URL,
    playStoreUrl: env.PLAY_STORE_URL,
    canonicalUrl: `${env.WEBAPP_BASE}/g/${params.id}`,
    // 링크 스크랩(카톡·문자 등) 미리보기 이미지 — /r/:id 와 동일하게 R2 CDN 서빙.
    ogImage: `${env.R2_CDN_BASE}/assets/og.png`,
    // 웹 카카오 로그인·참여용 공개 config (anon key 는 공개키).
    supabaseUrl: env.SUPABASE_URL,
    supabaseAnonKey: env.SUPABASE_ANON_KEY,
    cdnBase: env.R2_CDN_BASE,
  };
}

export const meta: Route.MetaFunction = ({ data }) => {
  if (!data) return [];
  const { team, roster, canonicalUrl, ogImage } = data;
  const title =
    team.status === "recruiting"
      ? `${team.title} — 케미 그룹 참가`
      : `${team.title} — 케미 그룹 결과`;
  const description =
    team.status === "recruiting"
      ? `${roster.length} / ${team.maxPlayers} 명 모집 중`
      : team.status === "expired"
        ? "인원이 모이지 않아 종료된 그룹입니다"
        : "케미 그룹 결과가 공개되었습니다";
  return [
    { title },
    { name: "description", content: description },
    // 멤버 이름이 노출되므로 검색엔진 indexing 차단.
    { name: "robots", content: "noindex,nofollow" },
    { property: "og:type", content: "website" },
    { property: "og:title", content: title },
    { property: "og:description", content: description },
    { property: "og:url", content: canonicalUrl },
    { property: "og:image", content: ogImage },
    { name: "twitter:card", content: "summary_large_image" },
  ];
};

export default function Group() {
  const data = useLoaderData<typeof loader>();
  const { team } = data;
  const [wizardActive, setWizardActive] = useState(false);

  let body: React.ReactNode;
  if (team.status === "recruiting") {
    body = (
      <>
        {!wizardActive && <TeamInvite data={data} />}
        {/* 미설치자 웹 참여 위저드 (미리보기 겸용) — 카카오 로그인 →
            (비밀방) PIN → (공약) 동의 → 정면 캡처 → join_team 까지
            브라우저에서 완결. */}
        <JoinWizard
          team={team}
          roster={data.roster}
          supabaseUrl={data.supabaseUrl}
          supabaseAnonKey={data.supabaseAnonKey}
          cdnBase={data.cdnBase}
          onActive={setWizardActive}
        />
      </>
    );
  } else if (team.resultPayload) {
    body = (
      <TeamShowcase
        title={team.title}
        payload={team.resultPayload as TeamPayload}
        roomKind={team.roomKind}
      />
    );
  } else if (team.status !== "expired" && team.chemistrySnapshot) {
    body = <RevealFallback data={data} />;
  } else {
    body = <TeamClosedNotice expired={team.status === "expired"} />;
  }
  return (
    <main className="join">
      {body}
      <CTA
        appOpenUrl={data.appOpenUrl}
        appStoreUrl={data.appStoreUrl}
        playStoreUrl={data.playStoreUrl}
      />
    </main>
  );
}

/** ageMin/ageMax → 라벨. 전연령(둘 다 null) · 정확히 한 decade(N대) · 그 외 범위(N대~M대). */
function ageLabel(min: number | null, max: number | null): string {
  if (min == null || max == null) return "전연령";
  if (min === max) return `${min}대`;
  return `${min}대~${max}대`;
}

// 앱 enum labelKo 와 동일 매핑 (shared age_group.dart / ethnicity.dart).
const AGE_GROUP_LABEL: Record<string, string> = {
  teens: "10대",
  twenties: "20대",
  thirties: "30대",
  forties: "40대",
  fifties: "50대",
  sixties: "60대",
  seventies: "70대",
  eighties: "80대",
  nineties: "90대",
};
const ETHNICITY_LABEL: Record<string, string> = {
  eastAsian: "아시아인",
  caucasian: "백인",
  african: "아프리카인",
  southeastAsian: "동남아인",
  hispanic: "히스패닉",
  middleEastern: "중동인",
};

/** 참가자 칩 라벨 — "30대 여성 아시아인" 인구통계 풀이. metrics 없으면 닉네임. */
function rosterChipLabel(r: {
  nickname: string;
  gender: string;
  ageGroup: string | null;
  ethnicity: string | null;
}): string {
  const age = r.ageGroup ? AGE_GROUP_LABEL[r.ageGroup] : null;
  if (!age) return r.nickname;
  const genderKo = r.gender === "male" ? "남성" : "여성";
  const eth = r.ethnicity ? ETHNICITY_LABEL[r.ethnicity] : null;
  return `${age} ${genderKo}${eth ? ` ${eth}` : ""}`;
}

function TeamInvite({
  data,
}: {
  data: ReturnType<typeof useLoaderData<typeof loader>>;
}) {
  const { team, roster, cdnBase } = data;
  const waitCount = Math.max(team.maxPlayers - roster.length, 0);
  const isMatch = team.roomKind === "match";
  const chip = (r: (typeof roster)[number]) => (
    <span key={r.userId} className="invite-chip">
      {r.thumbKey && (
        <img
          className={`invite-avatar${
            r.thumbSource === "camera" ? " invite-avatar--camera" : ""
          }`}
          src={`${cdnBase}/${r.thumbKey}`}
          alt=""
        />
      )}
      {rosterChipLabel(r)}
    </span>
  );
  // match 방 빈자리는 성별 아이콘(public/male.png·female.png), all 방은 텍스트.
  const waitChips = (count: number, keyPrefix: string, iconSrc?: string) =>
    Array.from({ length: count }).map((_, i) => (
      <span
        key={`${keyPrefix}-${i}`}
        className="invite-chip invite-chip--wait"
      >
        {iconSrc && (
          <img className="invite-wait-icon" src={iconSrc} alt="" />
        )}
        대기 중
      </span>
    ));
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <h1 style={{ fontSize: 24, color: "#1a1a1a", margin: 0 }}>
        {team.title}
      </h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        {roster.length} / {team.maxPlayers}명 ·{" "}
        {ageLabel(team.ageMin, team.ageMax)}
      </p>
      {isMatch && (
        <p style={{ color: "#666", fontSize: 14, marginTop: 4 }}>
          이성 케미, 남녀 반반 그룹
        </p>
      )}
      <div className="join-consent">
        <p className="join-consent-text">{photoConsentText(team.roomKind)}</p>
      </div>
      {isMatch ? (
        // 앱 team_detail 과 동일한 축 분리 — 왼쪽 남자, 오른쪽 여자.
        <div className="invite-cols">
          <div className="invite-col">
            <p className="invite-col-head">남자</p>
            {roster.filter((r) => r.gender === "male").map(chip)}
            {waitChips(
              remainingGenderSlots(roster, team.maxPlayers, "male"),
              "wait-m",
              "/male.png",
            )}
          </div>
          <div className="invite-col">
            <p className="invite-col-head">여자</p>
            {roster.filter((r) => r.gender === "female").map(chip)}
            {waitChips(
              remainingGenderSlots(roster, team.maxPlayers, "female"),
              "wait-f",
              "/female.png",
            )}
          </div>
        </div>
      ) : (
        <div className="invite-chips">
          {roster.map(chip)}
          {waitChips(waitCount, "wait")}
        </div>
      )}
    </section>
  );
}

function TeamClosedNotice({ expired }: { expired: boolean }) {
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <p style={{ color: "#666", fontSize: 14, margin: 0 }}>
        {expired
          ? "인원이 모이지 않아 종료된 그룹입니다"
          : "결과가 생성되지 않은 그룹입니다"}
      </p>
    </section>
  );
}

const BAND_EMOJI_BY_CODE = ["🟢", "🔵", "🟠", "🔴"] as const;
const BAND_LABEL_BY_CODE = ["천생연분", "금슬화합", "상부상조", "형극난조"] as const;

function TeamShowcase({
  title,
  payload,
  roomKind,
}: {
  title: string;
  payload: TeamPayload;
  roomKind: "all" | "match";
}) {
  const nameOf = (slot: number) =>
    payload.players.find((p) => p.slot === slot)?.name ?? "참가자";
  const bandOf = (a: number, b: number) => {
    const lo = Math.min(a, b);
    const hi = Math.max(a, b);
    return payload.pairs.find((p) => p.a === lo && p.b === hi)?.band;
  };
  // match 방 = 남(행) × 여(열) 직사각 매트릭스 (동성 쌍 부재) — Flutter
  // team_reveal_screen.dart 의 _matrix() 와 동일 축 분리 규칙. all 방은 정방.
  const isMatch = roomKind === "match";
  const allSlots = payload.players.map((p) => p.slot);
  const rows = isMatch
    ? payload.players.filter((p) => p.gender === "male").map((p) => p.slot)
    : allSlots;
  const cols = isMatch
    ? payload.players.filter((p) => p.gender === "female").map((p) => p.slot)
    : allSlots;
  return (
    <section className="showcase">
      <h1 className="showcase-title">{title}</h1>
      <div className="showcase-best">
        <p className="showcase-best-eyebrow">🏆 베스트 케미</p>
        <p className="showcase-best-pair">
          {nameOf(bestPair(payload).a)} × {nameOf(bestPair(payload).b)}
        </p>
        <p className="showcase-best-score">{bestPair(payload).score}점</p>
      </div>
      <div style={{ overflowX: "auto", marginTop: 16 }}>
        <table style={tableStyle}>
          <thead>
            <tr>
              <th style={head} />
              {cols.map((s) => (
                <th key={s} style={head}>
                  {nameOf(s)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row}>
                <th style={head}>{nameOf(row)}</th>
                {cols.map((col) => (
                  <td key={col} style={cell}>
                    {row === col
                      ? "·"
                      : BAND_EMOJI_BY_CODE[bandOf(row, col) ?? 3]}
                  </td>
                ))}
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      <p className="showcase-legend">
        {BAND_EMOJI_BY_CODE.map((e, i) => `${e} ${BAND_LABEL_BY_CODE[i]}`).join(
          "  ",
        )}
      </p>
      <p className="showcase-chat-hint">
        베스트 케미의 채팅은 앱에서 확인하세요
      </p>
    </section>
  );
}

function RevealFallback({
  data,
}: {
  data: ReturnType<typeof useLoaderData<typeof loader>>;
}) {
  const [payload, setPayload] = useState<TeamPayload | null>(null);
  const [failed, setFailed] = useState(false);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        await import("../lib/shared/face_engine.js");
        const roster = data.roster.map((r) => ({
          userId: r.userId,
          slotNo: r.slotNo,
          isOwner: r.isOwner,
          nickname: r.nickname,
          gender: r.gender,
        }));
        const computed = computeTeamPayload(
          roster,
          data.team.chemistrySnapshot as Record<string, unknown>,
          data.team.roomKind,
        );
        if (!computed) {
          if (!cancelled) setFailed(true);
          return;
        }
        // 로그인 참가자면 정본 backfill (first-writer-wins, 실패 무해).
        const sb = getSupabase(data.supabaseUrl, data.supabaseAnonKey);
        const { data: session } = await sb.auth.getSession();
        if (session.session) {
          await submitTeamResult(sb, data.team.id, computed).catch(
            () => {},
          );
        }
        if (!cancelled) setPayload(computed);
      } catch {
        if (!cancelled) setFailed(true);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);
  if (failed) return <TeamClosedNotice expired={false} />;
  if (!payload) return <p className="join-sub">결과를 계산하는 중…</p>;
  return (
    <TeamShowcase
      title={data.team.title}
      payload={payload}
      roomKind={data.team.roomKind}
    />
  );
}

const tableStyle: React.CSSProperties = {
  borderCollapse: "collapse",
  margin: "0 auto",
};

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
