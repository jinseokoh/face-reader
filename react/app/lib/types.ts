export type FiveElement = "wood" | "fire" | "earth" | "metal" | "water";

export interface Highlight {
  title: string;
  detail: string;
}

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

export type ShareKind = "solo" | "compat";

export interface RenderedShare {
  type: ShareKind;
  title: string;
  label: string;
  score: number;
  summary: string;
  highlights: Highlight[];
  ogTitle: string;
  ogDescription: string;
  ogImage: string;
  canonicalUrl: string;
  appLinkBase: string;
  appStoreUrl: string;
  playStoreUrl: string;
  shortId: string;
}
