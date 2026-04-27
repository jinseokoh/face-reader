import type {
  CompatOutput,
  CompatPersonOutput,
  EngineOutput,
  RenderedShare,
} from "../lib/types";

export function ShareCard({ data }: { data: RenderedShare }) {
  if (data.compat) return <CompatHeroCard compat={data.compat} />;
  if (data.solo) return <SoloHeroCard eng={data.solo} />;
  return null;
}

function SoloHeroCard({ eng }: { eng: EngineOutput }) {
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

function CompatHeroCard({ compat }: { compat: CompatOutput }) {
  return (
    <article className="hero hero--compat">
      <p className="hero-eyebrow">AI 관상가 궁합평가</p>

      <h1 className="compat-title">
        {compat.labelKo}
        <span className="compat-title-hanja">({compat.labelHanja})</span>
      </h1>
      <p className="compat-tagline">{compat.labelTagline}</p>

      <div className="compat-pair">
        <CompatSide person={compat.a} alias="나" />
        <span className="compat-x">×</span>
        <CompatSide person={compat.b} alias="상대" />
      </div>

      <ul className="hero-chips compat-chips">
        {compat.chips.map((c, i) => (
          <li key={i} className={`hero-chip hero-chip--${c.tone}`}>
            <span className="hero-chip-icon">{c.tone === "warm" ? "👍" : "👎"}</span>
            <span className="hero-chip-label">{c.label}</span>
          </li>
        ))}
      </ul>

      <p className="compat-relation">{compat.relation}</p>
    </article>
  );
}

function CompatSide({ person, alias }: { person: CompatPersonOutput; alias: string }) {
  return (
    <div className="compat-side">
      <img
        className="compat-side-thumb"
        src={person.gender === "female" ? "/female.png" : "/male.png"}
        alt=""
      />
      <p className="compat-side-alias">{alias}</p>
      <p className="compat-side-demo">{person.demographic}</p>
    </div>
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
