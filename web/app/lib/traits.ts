import "./shared/face_engine.js";

import type {
  CompatOutput,
  EngineOutput,
  MetricsRow,
  RawMetrics,
  RenderedShare,
  ShareKind,
  ShareTopRank,
} from "./types";

export interface RenderInput {
  shortId: string;
  origin: string;
  /// `${WEBAPP_BASE}/r/` — canonical URL prefix (페이지 본인의 URL).
  appLinkBase: string;
  /// `${WEBAPP_BASE}/r/{id}/open` — CTA 버튼이 가리키는 nested bridge URL.
  /// 동일 페이지 URL 로 navigate 하면 Safari same-URL guard 가 noop 시키므로
  /// 다른 sub-path 로 보내 universal link intercept 를 trigger.
  appOpenUrl: string;
  appStoreUrl: string;
  playStoreUrl: string;
  /// R2 CDN base — body 안의 `thumbnailKey` 와 결합해서 og:image 조립.
  /// 없으면 fallback assets/og.png (FACELY 브랜딩 카드).
  cdnBase?: string;
}

function ensureLoaded() {
  if (typeof globalThis.runEngine !== "function" || typeof globalThis.runCompat !== "function") {
    throw new Error(
      "face_engine.js not loaded. Run `pnpm build:shared` to compile /shared/lib/face_engine.dart.",
    );
  }
}

function runEngineFor(row: MetricsRow): EngineOutput {
  ensureLoaded();
  return JSON.parse(globalThis.runEngine(JSON.stringify(row.raw))) as EngineOutput;
}

function runCompatFor(a: MetricsRow, b: MetricsRow): CompatOutput {
  ensureLoaded();
  return JSON.parse(
    globalThis.runCompat(JSON.stringify(a.raw), JSON.stringify(b.raw)),
  ) as CompatOutput;
}

function ogImageFor(row: MetricsRow, ctx: RenderInput): string {
  // body 안에 thumbnailKey (R2 path) 가 있으면 cdn.facely.kr/{key} 사용.
  // 없으면 fallback — 랜딩·케미 초대와 동일한 FACELY 브랜딩 카드 (assets/og.png).
  // PII (얼굴 thumbnail) 노출이므로 meta 에 robots noindex 동시에 박혀 있음
  // (share.tsx).
  const key = (row.raw as unknown as Record<string, unknown>).thumbnailKey;
  const base = (ctx.cdnBase ?? "https://cdn.facely.kr").replace(/\/$/, "");
  if (typeof key === "string" && key.length > 0 && ctx.cdnBase) {
    return `${base}/${key}`;
  }
  return `${base}/assets/og.png`;
}

/// compat 카드의 두 인물 thumbnail 용 — R2 thumbnailKey 가 있으면 직통,
/// 없으면 gender stock png (`/female.png` / `/male.png`) fallback.
function compatThumbUrlFor(row: MetricsRow, ctx: RenderInput): string {
  const key = (row.raw as unknown as Record<string, unknown>).thumbnailKey;
  if (typeof key === "string" && key.length > 0 && ctx.cdnBase) {
    return `${ctx.cdnBase.replace(/\/$/, "")}/${key}`;
  }
  const gender = row.raw.gender;
  return `${ctx.origin}${gender === "female" ? "/female.png" : "/male.png"}`;
}

/// solo 카드의 사용자 thumbnail — 있으면 R2 직통, 없으면 undefined.
/// React 측에서 undefined 이면 engine 의 archetype portraitUrl 로 fallback.
function soloThumbUrlFor(row: MetricsRow, ctx: RenderInput): string | undefined {
  const key = (row.raw as unknown as Record<string, unknown>).thumbnailKey;
  if (typeof key === "string" && key.length > 0 && ctx.cdnBase) {
    return `${ctx.cdnBase.replace(/\/$/, "")}/${key}`;
  }
  return undefined;
}

export function renderSolo(row: MetricsRow, ctx: RenderInput): RenderedShare {
  const eng = runEngineFor(row);
  const ogTitle = eng.specialArchetype
    ? `${eng.primaryLabel} · ${eng.specialArchetype} — AI 관상가`
    : `${eng.primaryLabel} — AI 관상가`;
  const ogDescription = eng.catchphrase || eng.strengthLine;
  return {
    type: "solo",
    shortId: ctx.shortId,
    ogTitle,
    ogDescription,
    ogImage: ogImageFor(row, ctx),
    canonicalUrl: `${ctx.appLinkBase}${ctx.shortId}`,
    appLinkBase: ctx.appLinkBase,
    appOpenUrl: ctx.appOpenUrl,
    appStoreUrl: ctx.appStoreUrl,
    playStoreUrl: ctx.playStoreUrl,
    solo: eng,
    soloThumbUrl: soloThumbUrlFor(row, ctx),
  };
}

export function renderCompat(a: MetricsRow, b: MetricsRow, ctx: RenderInput): RenderedShare {
  const compat = runCompatFor(a, b);
  const score = Math.round(compat.total);
  const ogTitle = `${compat.labelKo} ${score}점 — AI 관상가`;
  const ogDescription = compat.summary;
  return {
    type: "compat",
    shortId: ctx.shortId,
    ogTitle,
    ogDescription,
    // 궁합은 my (=a) 의 thumbnail 만 og:image 로 노출 — 합성은 향후 확장.
    ogImage: ogImageFor(a, ctx),
    canonicalUrl: `${ctx.appLinkBase}${ctx.shortId}`,
    appLinkBase: ctx.appLinkBase,
    appOpenUrl: ctx.appOpenUrl,
    appStoreUrl: ctx.appStoreUrl,
    playStoreUrl: ctx.playStoreUrl,
    compat,
    compatAThumbUrl: compatThumbUrlFor(a, ctx),
    compatBThumbUrl: compatThumbUrlFor(b, ctx),
  };
}

export function isShareKind(s: string): s is ShareKind {
  return s === "solo" || s === "compat";
}

// ── 오늘의 관상 — 홈 그리드 카드 (routes/_index.tsx) ─────────────────────────

export interface DailyFaceCard {
  thumbUrl: string;
  /** "30대 남성" */
  demoLabel: string;
  /** 1순위 유형 — "학자형" 등 */
  typeLabel: string;
  /** hover 툴팁용 3순위 (score 는 0~10, toFixed(1) 표기) */
  top3: ShareTopRank[];
}

/// metrics.body 원문 1건 → 그리드 카드 1장. 썸네일 없는 row 는 카드로서
/// 의미가 없고, body 파싱·엔진 실패 row 는 조용히 건너뛴다 (null 반환 —
/// 호출부에서 filter).
export function renderDailyFace(body: string, cdnBase?: string): DailyFaceCard | null {
  try {
    const raw = JSON.parse(body) as RawMetrics;
    const key = (raw as unknown as Record<string, unknown>).thumbnailKey;
    if (typeof key !== "string" || key.length === 0 || !cdnBase) return null;
    const eng = runEngineFor({ id: "", raw });
    return {
      thumbUrl: `${cdnBase.replace(/\/$/, "")}/${key}`,
      demoLabel: `${eng.ageGroupKo} ${eng.genderKo}`,
      typeLabel: eng.primaryLabel,
      top3: eng.top3,
    };
  } catch (e) {
    console.warn("[renderDailyFace] drop row:", e);
    return null;
  }
}
