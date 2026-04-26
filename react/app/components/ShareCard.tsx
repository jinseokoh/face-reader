import type { ShareCardData } from "../lib/types";

export function ShareCard({ data }: { data: ShareCardData }) {
  const scoreLabel = data.kind === "compat" ? "둘의 궁합" : "관상 점수";
  return (
    <article className="card">
      <img className="card-image" src={data.cardImageUrl} alt="공유 카드" />
      <div className="card-summary">
        <p className="card-label">{data.label}</p>
        <h1 className="card-score">
          {scoreLabel} <strong>{data.totalScore}점</strong>
        </h1>
        <p className="card-tagline">{data.tagline}</p>
      </div>
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
