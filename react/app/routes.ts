import { type RouteConfig, index, route } from "@react-router/dev/routes";

export default [
  index("./routes/_index.tsx"),
  route("/app", "./routes/app.tsx"),
  route("/terms", "./routes/terms.tsx"),
  route("/privacy", "./routes/privacy.tsx"),
  route("/contact", "./routes/contact.tsx"),
  route("/r/:id", "./routes/share.tsx"),
  route("/r/:id/open", "./routes/r.$id.open.tsx"),
  route("/g/:id", "./routes/g.$id.tsx"),
  route("/g/:id/open", "./routes/g.$id.open.tsx"),
  route("/api/r2/presign", "./routes/api.r2.presign.ts"),
  route("/api/r2/delete", "./routes/api.r2.delete.ts"),
  route("/api/analyze", "./routes/api.analyze.ts"),
  route("/api/account/delete", "./routes/api.account.delete.ts"),
  route("/api/push/match", "./routes/api.push.match.ts"),
] satisfies RouteConfig;
