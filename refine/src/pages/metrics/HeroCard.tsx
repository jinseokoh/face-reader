import type { CompatOutput, EngineOutput } from "../../lib/share-engine";
import "./hero-card.css";

export function SoloHeroCard({ eng }: { eng: EngineOutput }) {
  return (
    <article className="hero">
      <div className="hero-head-row">
        <header className="hero-head">
          <p className="hero-eyebrow">AI 관상가 평가</p>
          <h1 className="hero-title">{eng.primaryLabel}</h1>
          <p className="hero-subtitle">{eng.secondaryLabel} 기질</p>
          {eng.specialArchetype && (
            <span className="hero-special">{eng.specialArchetype}</span>
          )}
        </header>
        <img className="hero-portrait" src={eng.portraitUrl} alt="" />
      </div>

      {eng.catchphrase && (
        <blockquote className="hero-catchphrase">{eng.catchphrase}</blockquote>
      )}

      <div className="hero-lines">
        <HeroLine label="강점" line={eng.strengthLine} />
        <HeroLine label="약점" line={eng.shadowLine} />
      </div>

      <ul className="hero-chips">
        {eng.chips.map((c, i) => (
          <li key={i} className={`hero-chip hero-chip--${c.tone}`}>
            <span className="hero-chip-icon">{c.tone === "warm" ? "👍" : "👎"}</span>
            <span className="hero-chip-label">{c.label}</span>
          </li>
        ))}
      </ul>

      <div className="hero-top3">
        {eng.top3.map((t, i) => (
          <div key={t.key} className="hero-rank">
            <p className="hero-rank-no">{i + 1}순위</p>
            <p className="hero-rank-label">{t.labelKo}</p>
            <div className="hero-rank-bar">
              <span
                className="hero-rank-fill"
                style={{ width: `${Math.max(0, Math.min(100, t.score * 10))}%` }}
              />
            </div>
            <p className="hero-rank-score">{t.score.toFixed(1)}</p>
          </div>
        ))}
      </div>
    </article>
  );
}

export function CompatHeroCard({ compat }: { compat: CompatOutput }) {
  const score = Math.round(compat.total);
  return (
    <article className="hero">
      <header className="hero-head">
        <p className="hero-eyebrow">AI 관상가 — 궁합 분석</p>
        <h1 className="hero-title">
          {compat.labelKo} <span className="hero-title-score">{score}</span>
        </h1>
        <p className="hero-subtitle">{compat.labelHanja}</p>
      </header>

      <div className="compat-portraits">
        <CompatFace person={compat.a} />
        <span className="compat-x">×</span>
        <CompatFace person={compat.b} />
      </div>

      {compat.summary && (
        <blockquote className="hero-catchphrase">{compat.summary}</blockquote>
      )}

      <div className="compat-subscores">
        <SubScore label="五行 (요소)" value={compat.subScores.element} />
        <SubScore label="十二宮 (궁)" value={compat.subScores.palace} />
        <SubScore label="氣 (기)" value={compat.subScores.qi} />
        <SubScore label="性情 (정)" value={compat.subScores.intimacy} />
      </div>

      {compat.scoreReason && (
        <p className="hero-score-reason">{compat.scoreReason}</p>
      )}
    </article>
  );
}

function CompatFace({ person }: { person: CompatOutput["a"] }) {
  return (
    <div className="compat-face">
      <img className="compat-face-img" src={person.portraitUrl} alt="" />
      <p className="compat-face-label">{person.primaryLabel}</p>
      <p className="compat-face-element">{elementKo(person.fiveElement)}</p>
    </div>
  );
}

function SubScore({ label, value }: { label: string; value: number }) {
  return (
    <div className="compat-sub">
      <p className="compat-sub-label">{label}</p>
      <p className="compat-sub-value">{value.toFixed(1)}</p>
    </div>
  );
}

function elementKo(e: string): string {
  return (
    {
      wood: "木 (목)",
      fire: "火 (화)",
      earth: "土 (토)",
      metal: "金 (금)",
      water: "水 (수)",
    }[e] ?? e
  );
}

function HeroLine({ label, line }: { label: string; line: string }) {
  if (!line) return null;
  return (
    <p className="hero-line">
      <span className="hero-line-label">{label}</span>
      <span className="hero-line-text">{line}</span>
    </p>
  );
}
