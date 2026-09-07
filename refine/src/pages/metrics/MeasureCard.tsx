import type { MeasureOutput, MeasurePairOutput } from "../../lib/share-engine";
import { firstImpressionBand } from "../../lib/share-engine";
import "./hero-card.css";

/** 첫인상 사분위 등급 문구 — 앱 team_band.dart firstImpressionBandLabel 과 동일. */
export const FI_BAND_LABEL = ["상위 25%", "상위 50%", "상위 75%", "하위 25%"] as const;

/** iOS(measure) 카드 — 첫인상 4축·카드 3축 5칸·프로필·특이 계측·대칭·확신도.
 *  앱 MeasureReportBody 와 같은 숫자 (shared measure_share.dart). 관상 없음. */
export function SoloMeasureCard({
  m,
  thumbUrl,
}: {
  m: MeasureOutput;
  thumbUrl?: string | null;
}) {
  const best = [...m.axes].filter((a) => a.key !== "attractive").sort((x, y) => x.top - y.top)[0];
  return (
    <article className="hero hero--measure">
      <div className="hero-head-row">
        <header className="hero-head">
          <p className="hero-eyebrow">첫인상 측정 (iOS)</p>
          <h1 className="hero-title">
            {best ? `${best.labelKo} 상위 ${best.top}%` : "첫인상"}
          </h1>
          <p className="hero-subtitle">
            {m.ageGroupKo} {m.genderKo} · {m.faceShapeKo} · 확신도 {m.confidenceKo}
          </p>
        </header>
        <img className="hero-portrait" src={thumbUrl ?? portraitFor(m.genderKo)} alt="" />
      </div>

      <div className="hero-grid-4">
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

      <p className="hero-section-label">공유 카드 3축 (5칸)</p>
      <div className="hero-top3">
        {m.cardAxes.map((a) => (
          <div key={a.labelKo} className="hero-rank">
            <p className="hero-rank-label">{a.labelKo}</p>
            <Levels level={a.level} />
            <p className="hero-rank-score">{a.level}/5</p>
          </div>
        ))}
      </div>

      {m.profile.length > 0 && (
        <>
          <p className="hero-section-label">얼굴 기하학 프로필</p>
          <table className="measure-table">
            <tbody>
              {m.profile.map((p) => (
                <tr key={p.labelKo}>
                  <td>{p.labelKo}</td>
                  <td>{p.score}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}

      {m.distinct.length > 0 && (
        <>
          <p className="hero-section-label">특이 계측 (|z| 큰 순)</p>
          <table className="measure-table">
            <tbody>
              {m.distinct.map((d) => (
                <tr key={d.labelKo}>
                  <td>{d.labelKo}</td>
                  <td>상위 {d.top}%</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}

      {m.symmetry.length > 0 && (
        <>
          <p className="hero-section-label">좌우 비대칭도 (0 = 완전 대칭)</p>
          <table className="measure-table">
            <tbody>
              {m.symmetry.map((s) => (
                <tr key={s.labelKo}>
                  <td>{s.labelKo}</td>
                  <td>{s.value.toFixed(3)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </>
      )}
    </article>
  );
}

/** iOS 얼굴 비교 — 케미 합(0~300)·조화도·보완도·닮은 정도·영역별·두 사람 축. */
export function MeasurePairCard({
  p,
  thumbA,
  thumbB,
  aName,
  bName,
}: {
  p: MeasurePairOutput;
  thumbA?: string | null;
  thumbB?: string | null;
  aName?: string | null;
  bName?: string | null;
}) {
  const band = firstImpressionBand(p.chemistry);
  return (
    <article className="hero hero--measure">
      <header className="hero-head">
        <p className="hero-eyebrow">얼굴 비교 (iOS)</p>
        <h1 className="hero-title">
          케미 {p.chemistry}
          <span className="hero-title-score">/300 · {FI_BAND_LABEL[band]}</span>
        </h1>
        <p className="hero-subtitle">
          무작위 쌍 대비 상위 {p.chemistryTop}% · 닮은 정도 상위 {p.similarityTop}%
        </p>
      </header>

      <div className="compat-portraits">
        <PairFace thumbUrl={thumbA} person={p.a} name={aName} />
        <span className="compat-x">×</span>
        <PairFace thumbUrl={thumbB} person={p.b} name={bName} />
      </div>

      <div className="hero-top3">
        <Sub label="조화도" value={p.harmony} />
        <Sub label="보완도" value={p.complementarity} />
        <Sub label="닮은 정도" value={p.similarity} />
      </div>

      <p className="hero-section-label">영역별 닮은 정도</p>
      <table className="measure-table">
        <tbody>
          {p.regions.map((r) => (
            <tr key={r.key}>
              <td>{r.labelKo}</td>
              <td className="measure-dim">{r.bandKo}</td>
              <td>{r.value}</td>
            </tr>
          ))}
        </tbody>
      </table>

      <p className="hero-section-label">두 사람의 첫인상 (상위 N%) · 인상 유사도 {p.impressionSimilarity}</p>
      <table className="measure-table">
        <tbody>
          {p.axes.map((a) => (
            <tr key={a.labelKo}>
              <td>{a.labelKo}</td>
              <td className="measure-dim">{aName ?? "A"} {a.aTop}%</td>
              <td>{bName ?? "B"} {a.bTop}%</td>
            </tr>
          ))}
        </tbody>
      </table>
    </article>
  );
}

function PairFace({
  thumbUrl,
  person,
  name,
}: {
  thumbUrl?: string | null;
  person: MeasurePairOutput["a"];
  name?: string | null;
}) {
  return (
    <div className="compat-face">
      <img className="compat-face-img" src={thumbUrl ?? portraitFor(person.genderKo)} alt="" />
      <p className="compat-face-label">{name ?? `${person.ageGroupKo} ${person.genderKo}`}</p>
      <p className="compat-face-element">
        {name ? `${person.ageGroupKo} ${person.genderKo} · ` : ""}
        {person.faceShapeKo}
      </p>
    </div>
  );
}

function Sub({ label, value }: { label: string; value: number }) {
  return (
    <div className="hero-rank">
      <p className="hero-rank-no">{label}</p>
      <p className="hero-rank-label">{value}</p>
    </div>
  );
}

function Levels({ level }: { level: number }) {
  return (
    <div className="measure-levels">
      {[1, 2, 3, 4, 5].map((i) => (
        <span key={i} className={`measure-level${i <= level ? " measure-level--on" : ""}`} />
      ))}
    </div>
  );
}

/** genderKo("남성"/"여성") 기준 stock 초상 — HeroCard.portraitFor 와 같은 자산. */
function portraitFor(genderKo: string): string {
  return genderKo.startsWith("여")
    ? "https://cdn.facely.kr/assets/female.png"
    : "https://cdn.facely.kr/assets/male.png";
}
