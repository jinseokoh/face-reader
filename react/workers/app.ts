import { createRequestHandler } from "react-router";

import {
  cleanupStaleMetrics,
  closeStaleTeams,
  purgeExpiredTeams,
} from "./cron";

declare module "react-router" {
  export interface AppLoadContext {
    cloudflare: { env: Env; ctx: ExecutionContext };
  }
}

const requestHandler = createRequestHandler(
  () => import("virtual:react-router/server-build"),
  import.meta.env.MODE,
);

export default {
  fetch(request, env, ctx) {
    return requestHandler(request, { cloudflare: { env, ctx } });
  },
  // Cron Triggers (wrangler.jsonc `triggers.crons`) — Cloudflare 플랫폼이
  // 스케줄마다 직접 호출. 어느 표현식에 불렸는지는 controller.cron 으로 분기.
  async scheduled(controller, env, _ctx) {
    if (controller.cron === "0 18 * * *") {
      // 매일 UTC 18:00 = KST 새벽 3시 — 정리 2종.
      await cleanupStaleMetrics(env);
      await purgeExpiredTeams(env);
    } else {
      // 매시 정각 — 48h 자동 발표 (하루 1회면 최대 24h 오차라 시간 단위로).
      await closeStaleTeams(env);
    }
  },
} satisfies ExportedHandler<Env>;
