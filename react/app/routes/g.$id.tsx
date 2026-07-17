import { useEffect, useState } from "react";
import { useLoaderData } from "react-router";
import type { Route } from "./+types/g.$id";
import { CTA } from "../components/CTA";
import { JoinWizard } from "../components/JoinWizard";
import { getSupabase } from "../lib/auth";
import {
  computeBattlePayload,
  submitBattleResult,
  type BattlePayload,
} from "../lib/join";
import { fetchBattleSSR } from "../lib/supabase";

/**
 * `GET /g/:id` — 케미 배틀 (Plan 3). 한 라우트, status 4분기:
 *   - recruiting = 초대장(공약·연령대·n/N 노출) + JoinWizard
 *   - revealing/completed + payload = 결과 쇼케이스 (🏆 Best 카드 + 밴드 매트릭스)
 *   - revealing/completed + payload 없음 + snapshot 있음 = 클라이언트 즉석 계산
 *     (runBattle) 후 (로그인 참가자면) 정본 backfill
 *   - expired 또는 completed + payload/snapshot 둘 다 없음 = 종료 안내
 *
 * 밴드는 색 대신 이모지(🟢🔵🟠🔴)로만 표기해 웹 4색 팔레트를 지킨다.
 */
export async function loader({ context, params }: Route.LoaderArgs) {
  const env = context.cloudflare.env;
  const data = await fetchBattleSSR(env, params.id!);
  if (!data) throw new Response("Not Found", { status: 404 });
  return {
    battle: data.battle,
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
  const { battle, roster, canonicalUrl, ogImage } = data;
  const title =
    battle.status === "recruiting"
      ? `${battle.title} — 케미 배틀 참가`
      : `${battle.title} — 케미 배틀 결과`;
  const description =
    battle.status === "recruiting"
      ? `${roster.length} / ${battle.maxPlayers} 명 모집 중`
      : battle.status === "expired"
        ? "인원이 모이지 않아 종료된 배틀입니다"
        : "케미 배틀 결과가 공개되었습니다";
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
  const { battle } = data;
  const [wizardActive, setWizardActive] = useState(false);

  let body: React.ReactNode;
  if (battle.status === "recruiting") {
    body = (
      <>
        {!wizardActive && <BattleInvite data={data} />}
        {/* 미설치자 웹 참여 위저드 (미리보기 겸용) — 카카오 로그인 →
            (비밀방) PIN → (공약) 동의 → 정면 캡처 → join_battle 까지
            브라우저에서 완결. */}
        <JoinWizard
          battle={battle}
          roster={data.roster}
          supabaseUrl={data.supabaseUrl}
          supabaseAnonKey={data.supabaseAnonKey}
          cdnBase={data.cdnBase}
          onActive={setWizardActive}
        />
      </>
    );
  } else if (battle.resultPayload) {
    body = (
      <BattleShowcase
        title={battle.title}
        payload={battle.resultPayload as BattlePayload}
        pledge={battle.pledge}
      />
    );
  } else if (battle.status !== "expired" && battle.chemistrySnapshot) {
    body = <RevealFallback data={data} />;
  } else {
    body = <BattleClosedNotice expired={battle.status === "expired"} />;
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

/** ageMin/ageMax → 라벨. 전연령(둘 다 null) · 정확히 한 decade(N대) · 그 외 범위(N~M세). */
function ageLabel(min: number | null, max: number | null): string {
  if (min == null || max == null) return "전연령";
  if (min === max) return `${min}대`;
  return `${min}~${max + 9}세`;
}

function BattleInvite({
  data,
}: {
  data: ReturnType<typeof useLoaderData<typeof loader>>;
}) {
  const { battle, roster } = data;
  const waitCount = Math.max(battle.maxPlayers - roster.length, 0);
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <h1 style={{ fontSize: 24, color: "#1a1a1a", margin: 0 }}>
        {battle.title}
      </h1>
      <p style={{ color: "#666", fontSize: 14, marginTop: 8 }}>
        {roster.length} / {battle.maxPlayers}명 ·{" "}
        {ageLabel(battle.ageMin, battle.ageMax)}
      </p>
      {battle.pledge && (
        <div className="join-pledge">
          <p className="join-pledge-text">이 방의 공약 — {battle.pledge}</p>
        </div>
      )}
      <div className="invite-chips">
        {roster.map((r) => (
          <span key={r.userId} className="invite-chip">
            {r.nickname}
          </span>
        ))}
        {Array.from({ length: waitCount }).map((_, i) => (
          <span key={`wait-${i}`} className="invite-chip invite-chip--wait">
            대기 중
          </span>
        ))}
      </div>
    </section>
  );
}

function BattleClosedNotice({ expired }: { expired: boolean }) {
  return (
    <section style={{ textAlign: "center", padding: "24px 16px" }}>
      <p style={{ color: "#666", fontSize: 14, margin: 0 }}>
        {expired
          ? "인원이 모이지 않아 종료된 배틀입니다"
          : "결과가 생성되지 않은 배틀입니다"}
      </p>
    </section>
  );
}

const BAND_EMOJI_BY_CODE = ["🟢", "🔵", "🟠", "🔴"] as const;
const BAND_LABEL_BY_CODE = ["천작지합", "금슬상화", "마합가성", "형극난조"] as const;

function BattleShowcase({
  title,
  payload,
  pledge,
}: {
  title: string;
  payload: BattlePayload;
  pledge: string | null;
}) {
  const nameOf = (slot: number) =>
    payload.players.find((p) => p.slot === slot)?.name ?? "참가자";
  const bandOf = (a: number, b: number) => {
    const lo = Math.min(a, b);
    const hi = Math.max(a, b);
    return payload.pairs.find((p) => p.a === lo && p.b === hi)?.band;
  };
  const slots = payload.players.map((p) => p.slot);
  return (
    <section className="showcase">
      <h1 className="showcase-title">{title}</h1>
      <div className="showcase-best">
        <p className="showcase-best-eyebrow">🏆 베스트 케미</p>
        <p className="showcase-best-pair">
          {nameOf(payload.best.a)} × {nameOf(payload.best.b)}
        </p>
        <p className="showcase-best-score">{payload.best.score}점</p>
      </div>
      {pledge && (
        <p className="showcase-pledge">
          이 방의 공약 — {pledge}
          <br />
          {nameOf(payload.best.a)}, {nameOf(payload.best.b)} 두 분의 몫입니다
        </p>
      )}
      <div style={{ overflowX: "auto", marginTop: 16 }}>
        <table style={tableStyle}>
          <thead>
            <tr>
              <th style={head} />
              {slots.map((s) => (
                <th key={s} style={head}>
                  {nameOf(s)}
                </th>
              ))}
            </tr>
          </thead>
          <tbody>
            {slots.map((row) => (
              <tr key={row}>
                <th style={head}>{nameOf(row)}</th>
                {slots.map((col) => (
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
    </section>
  );
}

function RevealFallback({
  data,
}: {
  data: ReturnType<typeof useLoaderData<typeof loader>>;
}) {
  const [payload, setPayload] = useState<BattlePayload | null>(null);
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
        }));
        const computed = computeBattlePayload(
          roster,
          data.battle.chemistrySnapshot as Record<string, unknown>,
        );
        if (!computed) {
          if (!cancelled) setFailed(true);
          return;
        }
        // 로그인 참가자면 정본 backfill (first-writer-wins, 실패 무해).
        const sb = getSupabase(data.supabaseUrl, data.supabaseAnonKey);
        const { data: session } = await sb.auth.getSession();
        if (session.session) {
          await submitBattleResult(sb, data.battle.id, computed).catch(
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
  if (failed) return <BattleClosedNotice expired={false} />;
  if (!payload) return <p className="join-sub">결과를 계산하는 중…</p>;
  return (
    <BattleShowcase
      title={data.battle.title}
      payload={payload}
      pledge={data.battle.pledge}
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
