import "./shared/face_engine.js";

export type ChipTone = "warm" | "cool";

export interface ShareChip {
  label: string;
  tone: ChipTone;
}

export interface ShareTopRank {
  key: string;
  labelKo: string;
  score: number;
}

export interface EngineOutput {
  gender: string;
  primaryAttribute: string;
  primaryLabel: string;
  secondaryLabel: string;
  specialArchetype: string | null;
  catchphrase: string;
  strengthLine: string;
  shadowLine: string;
  chips: ShareChip[];
  top3: ShareTopRank[];
  portraitUrl: string;
}

export interface CompatPersonOutput {
  gender: string;
  primaryAttribute: string;
  primaryLabel: string;
  fiveElement: string;
  portraitUrl: string;
}

export interface CompatOutput {
  total: number;
  label: string;
  labelKo: string;
  labelHanja: string;
  summary: string;
  scoreReason: string;
  subScores: {
    element: number;
    palace: number;
    qi: number;
    intimacy: number;
  };
  elementRelationKind: string;
  a: CompatPersonOutput;
  b: CompatPersonOutput;
}

function ensureLoaded() {
  if (typeof globalThis.runEngine !== "function" || typeof globalThis.runCompat !== "function") {
    throw new Error(
      "face_engine.js not loaded. Run `pnpm build:shared` to compile /shared/lib/face_engine.dart.",
    );
  }
}

export function runEngine(metricsJson: string): EngineOutput {
  ensureLoaded();
  return JSON.parse(globalThis.runEngine(metricsJson)) as EngineOutput;
}

export function runCompat(metricsJsonA: string, metricsJsonB: string): CompatOutput {
  ensureLoaded();
  return JSON.parse(globalThis.runCompat(metricsJsonA, metricsJsonB)) as CompatOutput;
}
