# R2 bucket `facely` 의 root-level 자산

R2 객체로 업로드된 정적 자산의 SSOT 사본. 재해 복구·재배포 시 본 디렉토리의 파일을 그대로 r2 bucket 의 동명 key 에 올린다.

## 업로드 명령

```bash
# robots.txt — cdn.facely.kr 의 검색엔진 indexing 차단 (PII 보호).
pnpm wrangler r2 object put facely/robots.txt \
  --file r2-assets/robots.txt \
  --content-type "text/plain; charset=utf-8" \
  --remote
```

**`--remote` flag 필수** — 빼면 wrangler local mock 에만 업로드됨 (운영 R2 미반영).

## Cloudflare auto-injected 컨텐트

cdn.facely.kr/robots.txt 응답을 보면 우리 본문 앞에 Cloudflare 의 "Managed Content" 블록이 자동 prepend — AI 봇 일괄 차단 (Applebot-Extended / Bytespider / CCBot / ClaudeBot / GPTBot / Google-Extended / meta-externalagent 등). 우리 `User-agent: *` 와 결합되어 모든 봇 차단.

이 prepend 는 Cloudflare 의 "AI Audit" / Bot management 기능에서 토글 가능 (대시보드 → Bots → Manage robots.txt). 현재 우리 의도와 일치하므로 그대로 둠.

## 미래 추가 항목

- **X-Robots-Tag header**: robots.txt 무시하는 일부 봇 차단용. Cloudflare Transform Rule (Rules → Transform Rules → Modify Response Header) 로 `cdn.facely.kr` 호스트 매치 시 `X-Robots-Tag: noindex, nofollow` 추가. 대시보드 1-click 작업이라 별도 commit 불필요, 단 본 README 에 적용 시점 기록.
