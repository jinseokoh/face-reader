import { type RouteConfig, index, route } from "@react-router/dev/routes";

export default [
  index("./routes/_index.tsx"),
  route("/r/:shortId", "./routes/share.tsx"),
  route("/api/share", "./routes/api.share.ts"),
  route("/api/r2/presign", "./routes/api.r2.presign.ts"),
] satisfies RouteConfig;
