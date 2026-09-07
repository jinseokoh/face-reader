// dart compile js artifact (face_engine.js) registers these functions on
// globalThis at module load time. Same engine as web/ — single SSOT in
// /shared/. Recompile with `pnpm build:shared`.

declare global {
  // eslint-disable-next-line no-var
  var runEngine: (metricsJson: string) => string;
  // eslint-disable-next-line no-var
  var runCompat: (metricsJsonA: string, metricsJsonB: string) => string;
  // 현재 모델 버전 {geometry, impression, pair} JSON (APPLE.md §58).
  // eslint-disable-next-line no-var
  var modelVersions: () => string;
  // measure 카드 — 첫인상 4축·프로필·특이 계측·대칭·확신도 JSON (관상 없음).
  // eslint-disable-next-line no-var
  var runMeasure: (metricsJson: string) => string;
  // measure 두 카드 비교 — 케미 합·세 성분·닮은 정도·영역·두 사람 축.
  // eslint-disable-next-line no-var
  var runMeasurePair: (metricsJsonA: string, metricsJsonB: string) => string;
}

export {};
