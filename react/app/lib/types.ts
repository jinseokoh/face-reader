export type FiveElement = "wood" | "fire" | "earth" | "metal" | "water";

export interface RawMetrics {
  schemaVersion: number;
  ethnicity: string;
  gender: string;
  ageGroup: string;
  source: string;
  metrics: Record<string, number>;
  lateralMetrics?: Record<string, number>;
  faceShapeLabel?: string;
  faceShape: string;
}

export interface MetricsRow {
  id: string;
  raw: RawMetrics;
}

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

export type ShareKind = "solo" | "compat";

export interface RenderedShare {
  type: ShareKind;
  shortId: string;
  ogTitle: string;
  ogDescription: string;
  ogImage: string;
  canonicalUrl: string;
  appLinkBase: string;
  appStoreUrl: string;
  playStoreUrl: string;
  solo?: EngineOutput;
  compat?: CompatOutput;
}
