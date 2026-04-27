import type { RenderedShare } from "../lib/types";

export function ShareCard({ data }: { data: RenderedShare }) {
  return (
    <article className="card">
      <header className="card-header">
        <img className="card-logo" src="/logo.png" alt="AI 관상가" />
        <p className="card-label">{data.label}</p>
        <h1 className="card-score">
          <strong>{data.score}점</strong>
        </h1>
        <p className="card-tagline">{data.summary}</p>
      </header>
      {data.highlights.length > 0 && (
        <ul className="card-highlights">
          {data.highlights.map((h) => (
            <li key={h.title}>
              <span className="hl-title">{h.title}</span>
              <span className="hl-detail">{h.detail}</span>
            </li>
          ))}
        </ul>
      )}
    </article>
  );
}
