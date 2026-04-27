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
  appLinkBase: string;
  appStoreUrl: string;
  playStoreUrl: string;
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
    ogImage: `${ctx.origin}/logo.png`,
    canonicalUrl: `${ctx.appLinkBase}${ctx.shortId}`,
    appLinkBase: ctx.appLinkBase,
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
    ogImage: `${ctx.origin}/logo.png`,
    canonicalUrl: `${ctx.appLinkBase}${ctx.shortId}`,
    appLinkBase: ctx.appLinkBase,
    appStoreUrl: ctx.appStoreUrl,
    playStoreUrl: ctx.playStoreUrl,
    compat,
  };
}

export function isShareKind(s: string): s is ShareKind {
  return s === "solo" || s === "compat";
}
