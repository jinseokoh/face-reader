import type { Route } from './+types/terms'
import { renderMarkdown } from '../lib/markdown'

export function meta(_: Route.MetaArgs) {
  return [
    { title: 'Facely — 이용약관' },
    { name: 'description', content: 'Facely 서비스 이용약관' },
  ]
}

export async function loader({ request, context }: Route.LoaderArgs) {
  const url = new URL('/terms.md', request.url)
  const res = await context.cloudflare.env.ASSETS.fetch(url.toString())
  const md = await res.text()
  return { html: renderMarkdown(md) }
}

export default function Terms({ loaderData }: Route.ComponentProps) {
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
