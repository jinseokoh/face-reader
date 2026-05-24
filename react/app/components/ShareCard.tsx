import type {
  CompatOutput,
  CompatPersonOutput,
  EngineOutput,
  RenderedShare,
} from "../lib/types";

export function ShareCard({ data }: { data: RenderedShare }) {
  if (data.compat) {
    return (
      <CompatHeroCard
        compat={data.compat}
        aThumbUrl={data.compatAThumbUrl ?? ""}
        bThumbUrl={data.compatBThumbUrl ?? ""}
      />
    );
  }
  if (data.solo) return <SoloHeroCard eng={data.solo} />;
  return null;
}

function SoloHeroCard({ eng }: { eng: EngineOutput }) {
  return (
    <article className="hero">
      <div className="hero-head-row">
        <header className="hero-head">
          <p className="hero-eyebrow">Facely 관상 평가</p>
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

function CompatHeroCard({
  compat,
  aThumbUrl,
  bThumbUrl,
}: {
  compat: CompatOutput;
  aThumbUrl: string;
  bThumbUrl: string;
}) {
  return (
    <article className="hero hero--compat">
      <p className="hero-eyebrow">Facely 궁합 평가</p>

      <h1 className="compat-title">
        {compat.labelKo}
        <span className="compat-title-hanja">({compat.labelHanja})</span>
      </h1>
      <p className="compat-tagline">{compat.labelTagline}</p>

      <div className="compat-pair">
        <CompatSide person={compat.a} thumbUrl={aThumbUrl} />
        <span className="compat-x">×</span>
        <CompatSide person={compat.b} thumbUrl={bThumbUrl} />
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

function CompatSide({
  person,
  thumbUrl,
}: {
  person: CompatPersonOutput;
  thumbUrl: string;
}) {
  // 메인 라벨 = archetype primary (e.g. "기업가형", "학자형") — 사용자에게
  // 의미 있는 personality. demographic sub-line 은 "{ageGroup} {gender}
  // {secondary}기질" 포맷 (얼굴형 type 보다 풍성한 context).
  // R2 thumbnail 우선, 없으면 gender stock png (traits.ts::compatThumbUrlFor).
  return (
    <div className="compat-side">
      <img className="compat-side-thumb" src={thumbUrl} alt="" />
      <p className="compat-side-alias">{person.primaryLabel}</p>
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
