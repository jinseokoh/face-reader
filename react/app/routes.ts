import { type RouteConfig, index, route } from "@react-router/dev/routes";

export default [
  index("./routes/_index.tsx"),
  route("/r/:id", "./routes/share.tsx"),
  route("/api/r2/presign", "./routes/api.r2.presign.ts"),
] satisfies RouteConfig;
