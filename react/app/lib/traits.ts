import "./shared/face_engine.js";

import type {
  CompatOutput,
  EngineOutput,
  MetricsRow,
  RenderedShare,
  ShareKind,
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
  /// 없으면 fallback logo.png.
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
  // 없으면 fallback logo.png. PII (얼굴 thumbnail) 노출이므로 meta 에 robots
  // noindex 동시에 박혀 있음 (share.tsx).
  const key = (row.raw as unknown as Record<string, unknown>).thumbnailKey;
  if (typeof key === "string" && key.length > 0 && ctx.cdnBase) {
    return `${ctx.cdnBase.replace(/\/$/, "")}/${key}`;
  }
  return `${ctx.origin}/logo.png`;
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
