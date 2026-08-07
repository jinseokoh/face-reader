import { renderMarkdown } from '../lib/markdown'
import type { Route } from './+types/privacy'

export function meta(_: Route.MetaArgs) {
  return [
    { title: '관상은 과학이다 — 개인정보처리방침' },
    { name: 'description', content: '관상은 과학이다 개인정보처리방침' },
  ]
}

export async function loader({ request, context }: Route.LoaderArgs) {
  const url = new URL('/privacy.md', request.url)
  const res = await context.cloudflare.env.ASSETS.fetch(url.toString())
  const md = await res.text()
  return { html: renderMarkdown(md) }
}

export default function Privacy({ loaderData }: Route.ComponentProps) {
  return (
    <main className="doc">
      <article
        className="doc-body"
        dangerouslySetInnerHTML={{ __html: loaderData.html }}
      />
      <p className="doc-back">
        <a href="/">← 홈으로</a>
      </p>
    </main>
  )
}
