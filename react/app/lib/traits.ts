import "./shared/face_engine.js";

import type { Highlight, MetricsRow, RenderedShare, ShareKind } from "./types";

export interface RenderInput {
  shortId: string;
  origin: string;
  appLinkBase: string;
  appStoreUrl: string;
  playStoreUrl: string;
}

interface EngineOutput {
  score: number;
  archetype: string;
  highlights: Highlight[];
}

function runEngineFor(row: MetricsRow): EngineOutput {
  if (typeof globalThis.runEngine !== "function") {
    throw new Error(
      "face_engine.js not loaded. Run `pnpm build:shared` to compile /shared/lib/face_engine.dart.",
    );
  }
  const json = JSON.stringify(row.raw);
  const out = globalThis.runEngine(json);
  return JSON.parse(out) as EngineOutput;
}

export function renderSolo(row: MetricsRow, ctx: RenderInput): RenderedShare {
  const r = runEngineFor(row);
  const title = `${r.archetype} ${r.score}점`;
  const summary = (r.highlights[0]?.detail) ?? "균형 잡힌 흐름이 보이는 얼굴.";
  const ogTitle = `${title} — AI 관상가`;
  return {
    type: "solo",
    title,
    label: "관상 점수",
    score: r.score,
    summary,
    highlights: r.highlights.slice(0, 3),
    ogTitle,
    ogDescription: summary,
    ogImage: `${ctx.origin}/logo.png`,
    canonicalUrl: `${ctx.appLinkBase}${ctx.shortId}`,
    appLinkBase: ctx.appLinkBase,
    appStoreUrl: ctx.appStoreUrl,
    playStoreUrl: ctx.playStoreUrl,
    shortId: ctx.shortId,
  };
}

export function renderCompat(a: MetricsRow, b: MetricsRow, ctx: RenderInput): RenderedShare {
  const ra = runEngineFor(a);
  const rb = runEngineFor(b);
  const score = Math.round((ra.score + rb.score) / 2);
  const label = compatLabel(score);
  const title = `${label} ${score}점`;
  const summary = score >= 80
    ? "결이 자연스럽게 이어지는 사이입니다."
    : score >= 65
      ? "서로의 빈틈을 채울 가능성이 높습니다."
      : "결이 다르지만, 알고 보면 서로를 보완할 수 있습니다.";
  const ogTitle = `둘의 궁합 ${score}점 — AI 관상가`;
  return {
    type: "compat",
    title,
    label: "둘의 궁합",
    score,
    summary,
    highlights: [
      { title: "A 면", detail: ra.archetype },
      { title: "B 면", detail: rb.archetype },
      { title: "총평", detail: summary },
    ],
    ogTitle,
    ogDescription: summary,
    ogImage: `${ctx.origin}/logo.png`,
    canonicalUrl: `${ctx.appLinkBase}${ctx.shortId}`,
    appLinkBase: ctx.appLinkBase,
    appStoreUrl: ctx.appStoreUrl,
    playStoreUrl: ctx.playStoreUrl,
    shortId: ctx.shortId,
  };
}

function compatLabel(score: number): string {
  if (score >= 88) return "끌림이 통하는 조합";
  if (score >= 78) return "잘 맞는 흐름";
  if (score >= 68) return "은근히 맞는 사이";
  if (score >= 55) return "서로를 채우는 짝";
  return "다른 결을 가진 사이";
}

export function isShareKind(s: string): s is ShareKind {
  return s === "solo" || s === "compat";
}
