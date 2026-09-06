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
  /** 좌우 대칭 6개 (symmetry_metrics.dart). */
  symmetry?: Record<string, number>;
  /** 계산에 쓴 모델 버전 {geometry, impression, pair} (§58). */
  modelVersion?: Record<string, string>;
  /** 정면 468 랜드마크 [x, y] — 등방 원본 좌표, 소수 4자리. 스키마 2 필수. */
  landmarks: number[][];
  lateralLandmarks?: number[][];
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
  genderKo: string;
  ageGroupKo: string;
  ethnicityKo: string;
  faceShapeKo: string;
  primaryAttribute: string;
  primaryLabel: string;
  secondaryLabel: string;
  specialArchetype: string | null;
  catchphrase: string;
  strengthLine: string;
  shadowLine: string;
  chips: ShareChip[];
  top3: ShareTopRank[];
  /// archetype 별 fallback portrait. 새 디자인은 사용자 thumbnail (RenderedShare
  /// .soloThumbUrl) 우선, 없을 때만 fallback.
  portraitUrl: string;
}

export interface CompatPersonOutput {
  gender: string;
  genderKo: string;
  ageGroupKo: string;
  faceShapeKo: string;
  fiveElement: string;
  fiveElementKo: string;
  demographic: string;
  primaryLabel: string;
  secondaryLabel: string;
}

export interface CompatOutput {
  total: number;
  label: string;
  labelKo: string;
  labelHanja: string;
  labelTagline: string;
  summary: string;
  scoreReason: string;
  subScores: {
    element: number;
    palace: number;
    qi: number;
    intimacy: number;
  };
  elementRelationKind: string;
  relation: string;
  chips: ShareChip[];
  a: CompatPersonOutput;
  b: CompatPersonOutput;
}

export type ShareKind = "solo" | "compat" | "measure" | "measurePair";

/** runMeasure 출력 — measure 카드의 첫인상 리포트 (관상 없음). */
export interface MeasureOutput {
  genderKo: string;
  ageGroupKo: string;
  faceShapeKo: string;
  axes: { key: string; labelKo: string; top: number }[];
  cardAxes: { labelKo: string; level: number }[];
  profile: { labelKo: string; score: number }[];
  distinct: { labelKo: string; top: number }[];
  symmetry: { labelKo: string; value: number }[];
  confidenceKo: string;
}

/** runMeasurePair 출력 — measure 두 카드의 비교. */
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

export interface RenderedShare {
  type: ShareKind;
  shortId: string;
  ogTitle: string;
  ogDescription: string;
  ogImage: string;
  canonicalUrl: string;
  appLinkBase: string;
  /// CTA 버튼이 navigate 할 nested bridge URL — `${WEBAPP_BASE}/r/{id}/open`.
  /// Safari same-URL guard 회피용으로 `/r/{id}` 와 다른 path 이어야 한다.
  appOpenUrl: string;
  appStoreUrl: string;
  playStoreUrl: string;
  solo?: EngineOutput;
  compat?: CompatOutput;
  /// solo 전용 — 사용자 face thumbnail R2 URL. thumbnailKey 가 비어있으면
  /// engine 의 archetype `portraitUrl` 로 fallback.
  soloThumbUrl?: string;
  /// compat 전용 — a/b 양쪽의 R2 thumbnail 절대 URL.
  /// thumbnailKey 가 비어있으면 CDN gender stock png
  /// (`/assets/female.png` / `/assets/male.png`) 로 fallback.
  compatAThumbUrl?: string;
  compatBThumbUrl?: string;
  /// measure 카드 — 첫인상 리포트. solo/compat 과 동시에 있지 않다.
  measure?: MeasureOutput;
  measurePair?: MeasurePairOutput;
}
