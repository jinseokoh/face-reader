/**
 * 미니 markdown → HTML 렌더러.
 *
 * `/terms` · `/privacy` 처럼 우리가 직접 작성한 안전한 md 만 렌더하므로
 * sanitize / 외부 라이브러리 없이 정규식 기반으로 처리.
 * 지원: heading(1~3), paragraph, ul list, table(`| a | b |`),
 * inline `**bold**` · `[text](url)`.
 */

const ESC: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;',
}

function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => ESC[c]!)
}

function renderInline(text: string): string {
  let out = escapeHtml(text)
  out = out.replace(
    /\[([^\]]+)\]\(([^)]+)\)/g,
    (_m, label, href) =>
      `<a href="${escapeHtml(href)}" rel="noopener">${label}</a>`,
  )
  out = out.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>')
  return out
}

function renderTable(rows: string[]): string {
  const cells = (row: string) =>
    row
      .replace(/^\||\|$/g, '')
      .split('|')
      .map((c) => c.trim())
  const header = cells(rows[0]!)
  const body = rows.slice(2).map(cells)
  const thead = header
    .map((c) => `<th>${renderInline(c)}</th>`)
    .join('')
  const tbody = body
    .map(
      (r) =>
        `<tr>${r.map((c) => `<td>${renderInline(c)}</td>`).join('')}</tr>`,
    )
    .join('')
  return `<table><thead><tr>${thead}</tr></thead><tbody>${tbody}</tbody></table>`
}

export function renderMarkdown(md: string): string {
  const lines = md.replace(/\r\n/g, '\n').split('\n')
  const html: string[] = []
  let i = 0
  while (i < lines.length) {
    const line = lines[i]!

    if (!line.trim()) {
      i++
      continue
    }

    const h = /^(#{1,3})\s+(.+)$/.exec(line)
    if (h) {
      const level = h[1]!.length
      html.push(`<h${level}>${renderInline(h[2]!)}</h${level}>`)
      i++
      continue
    }

    // 표: 헤더 라인 + separator (`| --- |`) + 본문
    if (
      line.startsWith('|') &&
      lines[i + 1]?.startsWith('|') &&
      /^\|[\s\-:|]+\|$/.test(lines[i + 1]!.trim())
    ) {
      const tableRows: string[] = []
      while (i < lines.length && lines[i]?.startsWith('|')) {
        tableRows.push(lines[i]!)
        i++
      }
      html.push(renderTable(tableRows))
      continue
    }

    // 리스트
    if (/^[-*]\s+/.test(line)) {
      const items: string[] = []
      while (i < lines.length && /^[-*]\s+/.test(lines[i] ?? '')) {
        items.push(lines[i]!.replace(/^[-*]\s+/, ''))
        i++
      }
      html.push(
        `<ul>${items.map((it) => `<li>${renderInline(it)}</li>`).join('')}</ul>`,
      )
      continue
    }

    // paragraph — 빈 줄까지 모음
    const para: string[] = []
    while (
      i < lines.length &&
      lines[i]!.trim() &&
      !/^#{1,3}\s/.test(lines[i]!) &&
      !/^[-*]\s/.test(lines[i]!) &&
      !lines[i]!.startsWith('|')
    ) {
      para.push(lines[i]!)
      i++
    }
    html.push(`<p>${renderInline(para.join(' '))}</p>`)
  }
  return html.join('\n')
}
