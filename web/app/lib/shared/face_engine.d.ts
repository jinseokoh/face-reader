// dart compile js artifact (face_engine.js) registers two functions on
// globalThis at module load time.

declare global {
  // eslint-disable-next-line no-var
  var runEngine: (metricsJson: string) => string;
  // eslint-disable-next-line no-var
  var runCompat: (metricsJsonA: string, metricsJsonB: string) => string;
  // 웹 티저 — [[x,y],...] (MediaPipe 468 landmarks) JSON → 26 정면 raw 메트릭 JSON.
  // eslint-disable-next-line no-var
  /** @param aspect imageHeight / imageWidth — 비정사각 프레임의 각도 왜곡 보정 */
  var runMetrics: (landmarksJson: string, aspect: number) => string;
  // 좌우 대칭 6개 — runMetrics 와 같은 입력, {symEyes,…,symOverall} JSON.
  // eslint-disable-next-line no-var
  var runSymmetry: (landmarksJson: string, aspect: number) => string;
  // 현재 모델 버전 {geometry, impression, pair} JSON (§58).
  // eslint-disable-next-line no-var
  var modelVersions: () => string;
  // measure 카드 공유 — 첫인상·프로필·특이점·대칭·확신도 JSON (관상 없음).
  // eslint-disable-next-line no-var
  var runMeasure: (metricsJson: string) => string;
  // measure 두 카드 비교 — 케미 합·세 성분·닮은 정도·영역·두 사람 축.
  // eslint-disable-next-line no-var
  var runMeasurePair: (metricsJsonA: string, metricsJsonB: string) => string;
  // Chemistry Team — 입력 {"roomKind":"match"|"all","players":[{"slot","name","gender","body"}]},
  // 출력 result_payload. roomKind=="match" 면 이성 쌍만 계산(matchOnly).
  // eslint-disable-next-line no-var
  var runTeam: (teamJson: string) => string;
}

export {};
