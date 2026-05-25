import { Form, useNavigation } from 'react-router'
import type { Route } from './+types/removal'

/**
 * `GET/POST /removal` — **개인정보 삭제 요청 폼** (Google Play 요구사항).
 *
 * POST 시 web3forms 로 전송 → 운영자 이메일로 전달.
 * 실키는 `pnpm wrangler secret put WEB3FORMS_ACCESS_KEY`.
 */

export function meta(_: Route.MetaArgs) {
  return [
    { title: 'Facely — 개인정보 삭제 요청' },
    {
      name: 'description',
      content: 'Facely 계정 및 분석 데이터 삭제 요청 폼',
    },
  ]
}

type ActionData =
  | { ok: true }
  | { ok: false; error: string }

export async function action({
  request,
  context,
}: Route.ActionArgs): Promise<ActionData> {
  const form = await request.formData()
  const email = String(form.get('email') ?? '').trim()
  const accountId = String(form.get('accountId') ?? '').trim()
  const reason = String(form.get('reason') ?? '').trim()
  const consent = form.get('consent') === 'on'

  if (!email || !accountId || !consent) {
    return { ok: false, error: '필수 항목을 모두 입력해 주세요.' }
  }

  const accessKey = context.cloudflare.env.WEB3FORMS_ACCESS_KEY
  if (!accessKey || accessKey === 'REPLACE_ME') {
    return {
      ok: false,
      error: '서비스가 일시적으로 사용할 수 없습니다. 잠시 후 다시 시도해 주세요.',
    }
  }

  const res = await fetch('https://api.web3forms.com/submit', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({
      access_key: accessKey,
      subject: '[Facely] 개인정보 삭제 요청',
      from_name: 'Facely 삭제 요청 폼',
      email,
      message: [
        '【개인정보 삭제 요청】',
        '',
        `회신 이메일: ${email}`,
        `가입 ID / 이메일: ${accountId}`,
        '',
        '사유:',
        reason || '(미작성)',
        '',
        `User-Agent: ${request.headers.get('user-agent') ?? '-'}`,
        `IP: ${request.headers.get('cf-connecting-ip') ?? '-'}`,
      ].join('\n'),
    }),
  })

  if (!res.ok) {
    return { ok: false, error: '전송 중 오류가 발생했습니다. 다시 시도해 주세요.' }
  }
  return { ok: true }
}

export default function Removal({ actionData }: Route.ComponentProps) {
  const nav = useNavigation()
  const submitting = nav.state === 'submitting'

  if (actionData?.ok) {
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

  return (
    <main className="doc">
      <h1>개인정보 삭제 요청</h1>
      <p className="doc-lead">
        Facely 계정 및 분석 데이터의 삭제를 요청합니다. 처리 후 입력하신 이메일로
        결과를 회신드립니다.
      </p>

      <Form method="post" className="form">
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
            name="accountId"
            required
            autoComplete="username"
            className="form-input"
            placeholder="Facely 계정 식별을 위해 필요합니다"
          />
        </label>

        <label className="form-label">
          삭제 사유 (선택)
          <textarea
            name="reason"
            rows={4}
            className="form-input"
            placeholder="자유롭게 작성해 주세요"
          />
        </label>

        <label className="form-check">
          <input type="checkbox" name="consent" required />
          <span>
            본인의 데이터에 대한 삭제 요청이며, 삭제 후 복구가 불가능함에 동의합니다.
          </span>
        </label>

        {actionData && !actionData.ok && (
          <p className="form-error">{actionData.error}</p>
        )}

        <button type="submit" className="form-submit" disabled={submitting}>
          {submitting ? '전송 중…' : '삭제 요청 보내기'}
        </button>
      </Form>

      <p className="doc-back">
        <a href="/">← 홈으로</a>
      </p>
    </main>
  )
}
