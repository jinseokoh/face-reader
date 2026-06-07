import { useState } from 'react'
import type { Route } from './+types/contact'

/**
 * `GET /contact` — **개인정보 삭제 요청 폼** (Google Play 요구사항).
 *
 * 브라우저가 직접 `api.web3forms.com` 으로 AJAX POST. Worker → web3forms 는
 * CF WAF (1106) 에 차단되므로 client-side fetch 로 우회.
 * web3forms 응답의 `success` / `message` 를 그대로 상태로 노출 → 메일 발송
 * 실패 시 실제 원인이 화면에 표시됨.
 */

/**
 * 공유하기 기능을 쓸 때만 1건 생성되어 R2 에 저장되는 데이터 예시.
 * 사용자 안심용으로 삭제 요청 폼에 그대로 노출한다 (90일 후 자동 삭제).
 * raw JSON 을 파싱→prettify 해 전사 오류를 막는다.
 */
const STORED_SAMPLE = JSON.stringify(
  JSON.parse(
    '{"schemaVersion":1,"ethnicity":"eastAsian","gender":"male","ageGroup":"30s","timestamp":"2026-06-03T17:57:31.531888","source":"camera","thumbnailKey":"thumbnails/20260603/a53ae00b-2f48-40a2-b10f-ade2a4a4fa3b.jpg","metrics":{"faceAspectRatio":1.583152590136565,"faceTaperRatio":0.8204693681326711,"lowerFaceFullness":0.535534927595265,"upperFaceRatio":0.29172969852464936,"midFaceRatio":0.34017333637851627,"lowerFaceRatio":0.3681654370774055,"gonialAngle":142.55312961424286,"intercanthalRatio":0.28193897976673615,"eyeFissureRatio":0.21493680556103845,"eyeCanthalTilt":2.8479735430510416,"eyebrowThickness":0.03513082295332055,"browEyeDistance":0.14376208106290506,"nasalWidthRatio":1.1181850197575713,"nasalHeightRatio":0.31752206607074285,"mouthWidthRatio":0.4300998389276194,"mouthCornerAngle":4.897191139672551,"lipFullnessRatio":0.09187336226013933,"philtrumLength":0.09339543948884228,"foreheadWidth":0.8953820676868245,"cheekboneWidth":0.9564294500131548,"chinAngle":169.59828375487686,"eyeAspect":0.24419016422300677,"eyebrowCurvature":0.03412017824028422,"eyebrowTiltDirection":-0.015212046354978437,"upperVsLowerLipRatio":0.5810754911321435,"browSpacing":0.2167637482098117},"lateralMetrics":{"nasofrontalAngle":166.65202705066324,"nasolabialAngle":142.63314602611004,"facialConvexity":20.32894088044,"upperLipEline":0.008653900169832586,"lowerLipEline":-0.0005032992178926671,"mentolabialAngle":164.31306595793328,"noseTipProjection":0.29352445712388997,"dorsalConvexity":0.011327573016091589},"faceShapeLabel":"Oblong","faceShapeConfidence":0.9999735438373354,"faceShape":"oblong"}',
  ),
  null,
  2,
)

export function meta(_: Route.MetaArgs) {
  return [
    { title: '관상은 과학이다 — 데이터삭제 요청폼' },
    {
      name: 'description',
      content: '관상은 과학이다 계정 및 분석 데이터 삭제 요청 폼',
    },
  ]
}

export async function loader({ context }: Route.LoaderArgs) {
  return { accessKey: context.cloudflare.env.WEB3FORMS_ACCESS_KEY }
}

type Status =
  | { kind: 'idle' }
  | { kind: 'sending' }
  | { kind: 'success' }
  | { kind: 'error'; message: string }

export default function Contact({ loaderData }: Route.ComponentProps) {
  const { accessKey } = loaderData
  const [status, setStatus] = useState<Status>({ kind: 'idle' })

  const onSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    // React synthetic event 의 currentTarget 은 await 이후 null 됨 — 미리 캡쳐.
    const form = event.currentTarget
    setStatus({ kind: 'sending' })

    const formData = new FormData(form)
    formData.append('access_key', accessKey)
    formData.append('subject', '[관상은 과학이다] 개인정보 삭제 요청')
    formData.append('from_name', '관상은 과학이다 삭제 요청 폼')

    try {
      const response = await fetch('https://api.web3forms.com/submit', {
        method: 'POST',
        body: formData,
      })
      const data = (await response.json()) as {
        success?: boolean
        message?: string
      }
      if (data.success) {
        setStatus({ kind: 'success' })
        form.reset()
      } else {
        setStatus({
          kind: 'error',
          message: data.message ?? `HTTP ${response.status}`,
        })
      }
    } catch (err) {
      setStatus({
        kind: 'error',
        message: err instanceof Error ? err.message : '네트워크 오류',
      })
    }
  }

  if (status.kind === 'success') {
    return (
      <main className="doc">
        <h1>요청이 접수되었습니다</h1>
        <p>
          영업일 기준 7일 이내에 처리한 다음, 입력하신 이메일로 결과를 안내드립니다.
        </p>
        <p className="doc-back">
          <a href="/">← 홈으로</a>
        </p>
      </main>
    )
  }

  const sending = status.kind === 'sending'

  return (
    <main className="doc">
      <h1>데이터삭제 요청폼</h1>
      <p className="doc-lead">
        관상은 과학이다 계정 및 분석 데이터의 삭제를 요청합니다. 처리한 다음,
        입력하신 이메일로 결과를 회신드립니다.
      </p>

      <form onSubmit={onSubmit} className="form">
        <section className="privacy-panel">
          <h2 className="privacy-panel-title">
            보관하는 정보는 이것이 전부입니다
          </h2>
          <dl className="privacy-facts">
            <div className="privacy-fact">
              <dt>생성 시점</dt>
              <dd>공유하기 기능을 사용할 때만 1건 생성됩니다.</dd>
            </div>
            <div className="privacy-fact">
              <dt>보관 항목</dt>
              <dd>
                저해상도 200×200 썸네일 한 장과 아래 계측 수치값뿐입니다. 원본
                고해상도 사진은 저장하지 않습니다.
              </dd>
            </div>
            <div className="privacy-fact">
              <dt>자동 삭제</dt>
              <dd>생성 후 90일이 지나면 자동으로 삭제됩니다.</dd>
            </div>
          </dl>
          <p className="privacy-sample-label">실제 저장 데이터 예시</p>
          <pre className="privacy-sample">{STORED_SAMPLE}</pre>
        </section>

        <label className="form-label">
          <span className="form-label-text">
            회신 받을 이메일 <span className="form-required">*</span>
          </span>
          <input
            type="email"
            name="email"
            required
            autoComplete="email"
            className="form-input"
            placeholder="you@example.com"
          />
        </label>

        <label className="form-label">
          <span className="form-label-text">
            가입 시 사용한 이메일 또는 ID <span className="form-required">*</span>
          </span>
          <input
            type="text"
            name="name"
            required
            autoComplete="username"
            className="form-input"
            placeholder="관상은 과학이다 계정 식별을 위해 필요합니다"
          />
        </label>

        <label className="form-label">
          <span className="form-label-text">
            삭제 사유 <span className="form-required">*</span>
          </span>
          <textarea
            name="message"
            rows={4}
            required
            className="form-input"
            placeholder="자유롭게 작성해 주세요"
          />
        </label>

        <label className="form-check">
          <input type="checkbox" name="consent" required />
          <span>
            본인의 데이터에 대한 삭제 요청이며, 삭제 후 복구가 불가능함에
            동의합니다.
          </span>
        </label>

        {status.kind === 'error' && (
          <p className="form-error">전송 실패: {status.message}</p>
        )}

        <button type="submit" className="form-submit" disabled={sending}>
          {sending ? '전송 중…' : '삭제 요청 보내기'}
        </button>
      </form>

      <p className="doc-back">
        <a href="/">← 홈으로</a>
      </p>
    </main>
  )
}
