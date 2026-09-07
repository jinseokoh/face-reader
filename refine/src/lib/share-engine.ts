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
}

export interface CompatPersonOutput {
  gender: string;
  primaryAttribute: string;
  primaryLabel: string;
  fiveElement: string;
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

/** runMeasure 출력 — measure(iOS) 카드의 첫인상 리포트 (관상 없음). web/app/lib/types.ts 와 동일. */
export interface MeasureOutput {
  genderKo: string;
  ageGroupKo: string;
  faceShapeKo: string;
  /** 첫인상 4축 — top = 상위 N% (1~99). */
  axes: { key: string; labelKo: string; top: number }[];
  /** 공유 카드 3축 5칸 막대 (매력 제외). */
  cardAxes: { labelKo: string; level: number }[];
  profile: { labelKo: string; score: number }[];
  /** |z| 큰 순 특이 계측 3개. */
  distinct: { labelKo: string; top: number }[];
  /** 좌우 비대칭도 raw — 0 이 완전 대칭. */
  symmetry: { labelKo: string; value: number }[];
  confidenceKo: string;
}

/** runMeasurePair 출력 — measure 두 카드의 비교 (케미 합 0~300). */
export interface MeasurePairOutput {
  chemistry: number;
  chemistryTop: number;
  harmony: number;
  complementarity: number;
  similarity: number;
  similarityTop: number;
  impressionSimilarity: number;
  regions: { key: string; labelKo: string; value: number; bandKo: string; similar: boolean }[];
  axes: { labelKo: string; aTop: number; bTop: number }[];
  a: { genderKo: string; ageGroupKo: string; faceShapeKo: string };
  b: { genderKo: string; ageGroupKo: string; faceShapeKo: string };
}

/** 현재 엔진의 모델 버전 (APPLE.md §58) — 카드의 modelVersion 과 비교용. */
export type ModelVersions = { geometry: string; impression: string; pair: string };

function ensureLoaded() {
  if (
    typeof globalThis.runEngine !== "function" ||
    typeof globalThis.runCompat !== "function" ||
    typeof globalThis.runMeasure !== "function"
  ) {
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

export function runMeasure(metricsJson: string): MeasureOutput {
  ensureLoaded();
  return JSON.parse(globalThis.runMeasure(metricsJson)) as MeasureOutput;
}

export function runMeasurePair(metricsJsonA: string, metricsJsonB: string): MeasurePairOutput {
  ensureLoaded();
  return JSON.parse(globalThis.runMeasurePair(metricsJsonA, metricsJsonB)) as MeasurePairOutput;
}

/** 첫인상 최고 축 — 매력(attractive) 제외, 상위 N% 가 가장 작은 축. 앱 리스트 배지·웹 OG 제목과 같은 규칙. */
export function topAxis(m: MeasureOutput | undefined | null) {
  if (!m) return null;
  return (
    [...m.axes]
      .filter((a) => a.key !== "attractive")
      .sort((x, y) => x.top - y.top)[0] ?? null
  );
}

export function currentModelVersions(): ModelVersions {
  ensureLoaded();
  return JSON.parse(globalThis.modelVersions()) as ModelVersions;
}

/** 첫인상 케미 합(0~300)의 사분위 등급 0~3 — shared team.dart kFirstImpressionBandCuts 미러. */
export const FIRST_IMPRESSION_BAND_CUTS = [167.2, 148.7, 130.5] as const;
export function firstImpressionBand(total: number): number {
  for (let i = 0; i < FIRST_IMPRESSION_BAND_CUTS.length; i++) {
    if (total >= FIRST_IMPRESSION_BAND_CUTS[i]) return i;
  }
  return FIRST_IMPRESSION_BAND_CUTS.length;
}
