// dart compile js artifact (face_engine.js) registers two functions on
// globalThis at module load time. Same engine as react/ — single SSOT in
// /shared/. Recompile with `pnpm build:shared`.

declare global {
  // eslint-disable-next-line no-var
  var runEngine: (metricsJson: string) => string;
  // eslint-disable-next-line no-var
  var runCompat: (metricsJsonA: string, metricsJsonB: string) => string;
}

export {};
