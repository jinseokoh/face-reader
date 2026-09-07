import type {
  CompatOutput,
  CompatPersonOutput,
  EngineOutput,
  MeasureOutput,
  MeasurePairOutput,
  RenderedShare,
} from '../lib/types'

export function ShareCard({ data }: { data: RenderedShare }) {
  if (data.measurePair) {
    return (
      <MeasurePairCard
        pair={data.measurePair}
        aThumbUrl={data.compatAThumbUrl ?? ''}
        bThumbUrl={data.compatBThumbUrl ?? ''}
      />
    )
  }
  if (data.measure) {
    return <MeasureCard m={data.measure} thumbUrl={data.soloThumbUrl} />
  }
  if (data.compat) {
    return (
      <CompatHeroCard
        compat={data.compat}
        aThumbUrl={data.compatAThumbUrl ?? ''}
        bThumbUrl={data.compatBThumbUrl ?? ''}
      />
    )
  }
  if (data.solo) {
    return (
      <SoloHeroCard
        eng={data.solo}
        thumbUrl={data.soloThumbUrl ?? data.solo.portraitUrl}
      />
    )
  }
  return null
}

function SoloHeroCard({
  eng,
  thumbUrl,
}: {
  eng: EngineOutput
  thumbUrl: string
}) {
  return (
    <article className="hero">
      <div className="hero-head-row">
        <header className="hero-head">
          <p className="hero-eyebrow">관상은 과학이다</p>
          <h1 className="hero-title">{eng.primaryLabel}</h1>
          <p className="hero-subtitle">{eng.secondaryLabel} 기질</p>
          {eng.specialArchetype && (
            <span className="hero-special">{eng.specialArchetype}</span>
          )}
        </header>
        <div className="hero-side">
          <img className="hero-avatar" src={thumbUrl} alt="" />
          <p className="hero-side-demo">
            {eng.ageGroupKo} {eng.genderKo} {eng.ethnicityKo}
          </p>
          <p className="hero-side-demo">{eng.faceShapeKo}</p>
        </div>
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
            <span className="hero-chip-icon">
              {c.tone === 'warm' ? '👍' : '👎'}
            </span>
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
                style={{
                  width: `${Math.max(0, Math.min(100, t.score * 10))}%`,
                }}
              />
            </div>
            <p className="hero-rank-score">{t.score.toFixed(1)}</p>
          </div>
        ))}
      </div>
    </article>
  )
}

function CompatHeroCard({
  compat,
  aThumbUrl,
  bThumbUrl,
}: {
  compat: CompatOutput
  aThumbUrl: string
  bThumbUrl: string
}) {
  return (
    <article className="hero hero--compat">
      <p className="hero-eyebrow">궁합도 과학이다</p>

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
            <span className="hero-chip-icon">
              {c.tone === 'warm' ? '👍' : '👎'}
            </span>
            <span className="hero-chip-label">{c.label}</span>
          </li>
        ))}
      </ul>

      <p className="compat-relation">{compat.relation}</p>
    </article>
  )
}

function CompatSide({
  person,
  thumbUrl,
}: {
  person: CompatPersonOutput
  thumbUrl: string
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
  )
}

function HeroLine({ label, line }: { label: string; line: string }) {
  if (!line) return null
  return (
    <p className="hero-line">
      <span className="hero-line-label">{label}</span>
      <span className="hero-line-text">{line}</span>
    </p>
  )
}

const MEASURE_DISCLAIMER =
  '첫인상 지표는 공개 학술연구를 기반으로 계산한 추정치이며, 한국인만을 대상으로 학습·검증된 모델이 아닙니다. 실제 성격·능력이 아니라 얼굴 형태가 기준 집단 안에서 갖는 상대 위치입니다.'

/** measure 카드 — 첫인상 프로필. 관상 문구·유형·기질은 쓰지 않는다. */
function MeasureCard({ m, thumbUrl }: { m: MeasureOutput; thumbUrl?: string }) {
  return (
    <article className="hero">
      <div className="hero-head-row">
        <header className="hero-head">
          <p className="hero-eyebrow">첫인상 측정</p>
          <h1 className="hero-title">당신은 이런 인상을 줍니다.</h1>
          <p className="hero-subtitle">분석 확신도 {m.confidenceKo} (사진 상태 기준)</p>
        </header>
        <div className="hero-side">
          {thumbUrl && <img className="hero-avatar" src={thumbUrl} alt="" />}
          <p className="hero-side-demo">
            {m.ageGroupKo} {m.genderKo}
          </p>
          <p className="hero-side-demo">{m.faceShapeKo}</p>
        </div>
      </div>
      <div className="hero-top3">
        {m.axes.map((a) => (
          <div key={a.key} className="hero-rank">
            <p className="hero-rank-label">{a.labelKo}</p>
            <div className="hero-rank-bar">
              <span className="hero-rank-fill" style={{ width: `${100 - a.top}%` }} />
            </div>
            <p className="hero-rank-score">상위 {a.top}%</p>
          </div>
        ))}
      </div>
      <div className="hero-lines">
        <HeroLine
          label="얼굴 기하학 프로필"
          line={m.profile.map((p) => `${p.labelKo} ${p.score}`).join(' · ')}
        />
        <HeroLine
          label="평균에서 가장 먼 3개"
          line={m.distinct.map((d) => `${d.labelKo} 상위 ${d.top}%`).join(' · ')}
        />
      </div>
      <p className="hero-line">
        <span className="hero-line-text">{MEASURE_DISCLAIMER}</span>
      </p>
    </article>
  )
}

/** measure 두 카드 비교 — 케미 합과 세 성분, 닮은 정도, 영역 문구, 두 사람 축. */
function MeasurePairCard({
  pair,
  aThumbUrl,
  bThumbUrl,
}: {
  pair: MeasurePairOutput
  aThumbUrl: string
  bThumbUrl: string
}) {
  const similar = pair.regions.filter((r) => r.similar)
  const different = pair.regions.filter((r) => !r.similar)
  return (
    <article className="hero hero--compat">
      <p className="hero-eyebrow">얼굴 비교</p>
      <h1 className="compat-title">케미 {pair.chemistry} / 300</h1>
      <p className="compat-tagline">
        조화도 {pair.harmony} · 보완도 {pair.complementarity} · 닮은 정도 {pair.similarity}
      </p>
      <div className="compat-pair">
        <div className="compat-side">
          <img className="compat-side-thumb" src={aThumbUrl} alt="" />
          <p className="compat-side-demo">
            {pair.a.ageGroupKo} {pair.a.genderKo}
          </p>
        </div>
        <span className="compat-x">×</span>
        <div className="compat-side">
          <img className="compat-side-thumb" src={bThumbUrl} alt="" />
          <p className="compat-side-demo">
            {pair.b.ageGroupKo} {pair.b.genderKo}
          </p>
        </div>
      </div>
      <div className="hero-lines">
        <HeroLine
          label="무작위 두 사람 대비"
          line={`닮은 정도 상위 ${pair.similarityTop}% · 케미 점수 상위 ${pair.chemistryTop}%`}
        />
        <HeroLine
          label="닮은 부분"
          line={similar.map((r) => `${r.labelKo} ${r.bandKo}`).join(' · ') || '없음'}
        />
        <HeroLine
          label="다른 부분"
          line={different.map((r) => `${r.labelKo} ${r.bandKo}`).join(' · ') || '없음'}
        />
        <HeroLine
          label="두 사람의 첫인상"
          line={pair.axes.map((a) => `${a.labelKo} 상위 ${a.aTop}% 대 ${a.bTop}%`).join(' · ')}
        />
      </div>
      <p className="hero-line">
        <span className="hero-line-text">{MEASURE_DISCLAIMER}</span>
      </p>
    </article>
  )
}
