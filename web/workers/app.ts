import { createRequestHandler } from "react-router";

import {
  cleanupStaleMetrics,
  completeOrphanReveals,
  expireStaleTeams,
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
      // 매시 정각 — 48h 만료 + revealing 고아 안전망.
      await expireStaleTeams(env);
      await completeOrphanReveals(env);
    }
  },
} satisfies ExportedHandler<Env>;
