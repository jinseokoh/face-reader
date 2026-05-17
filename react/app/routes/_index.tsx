import type { Route } from "./+types/_index";

export function meta(_: Route.MetaArgs) {
  return [
    { title: "Facely — 관상은 과학이다" },
    {
      name: "description",
      content: "Facely, 안면 계측 데이터 기반 인공지능 관상앱.",
    },
    { name: "robots", content: "noindex,nofollow" },
  ];
}

export default function Index() {
  return (
    <main className="landing">
      <h1 className="landing-hero">관상은 과학이다.</h1>
      <p className="landing-sub">
        Facely, 안면 계측 데이터 기반 인공지능 관상앱.
      </p>
    </main>
  );
}
