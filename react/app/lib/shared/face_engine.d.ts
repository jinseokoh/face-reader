// dart compile js artifact (face_engine.js) registers two functions on
// globalThis at module load time.

declare global {
  // eslint-disable-next-line no-var
  var runEngine: (metricsJson: string) => string;
  // eslint-disable-next-line no-var
  var runCompat: (metricsJsonA: string, metricsJsonB: string) => string;
  // 웹 티저 — [[x,y],...] (MediaPipe 468 landmarks) JSON → 26 정면 raw 메트릭 JSON.
  // eslint-disable-next-line no-var
  var runMetrics: (landmarksJson: string) => string;
  // Chemistry Battle — 입력 {"roomKind":"match"|"all","players":[{"slot","name","gender","body"}]},
  // 출력 result_payload. roomKind=="match" 면 이성 쌍만 계산(matchOnly).
  // eslint-disable-next-line no-var
  var runBattle: (battleJson: string) => string;
}

export {};
