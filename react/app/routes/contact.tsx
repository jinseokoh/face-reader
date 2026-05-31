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

export function meta(_: Route.MetaArgs) {
  return [
    { title: '관상은 과학이다 — 개인정보 삭제 요청' },
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
    formData.append('subject', '[Facely] 개인정보 삭제 요청')
    formData.append('from_name', 'Facely 삭제 요청 폼')

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
          영업일 기준 7일 이내에 처리 후 입력하신 이메일로 결과를 안내드립니다.
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
      <h1>개인정보 삭제 요청</h1>
      <p className="doc-lead">
        관상은 과학이다 계정 및 분석 데이터의 삭제를 요청합니다. 처리 후
        입력하신 이메일로 결과를 회신드립니다.
      </p>

      <form onSubmit={onSubmit} className="form">
        <ul className="form-note">
          <li>
            삭제되는 내용은 관상 기록 추적용 저해상도 200×200 썸네일과 안면 계측
            데이터 파일 전부입니다.
          </li>
          <li>삭제이후 복원은 불가하므로 신중히 선택해 주세요.</li>
        </ul>

        <label className="form-label">
          회신 받을 이메일 <span className="form-required">*</span>
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
          가입 시 사용한 이메일 또는 ID <span className="form-required">*</span>
          <input
            type="text"
            name="name"
            required
            autoComplete="username"
            className="form-input"
            placeholder="Facely 계정 식별을 위해 필요합니다"
          />
        </label>

        <label className="form-label">
          삭제 사유 <span className="form-required">*</span>
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
