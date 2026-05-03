# face share host — Claude 컨벤션

아키텍처·계약·할 일은 [docs/HOW-IT-WORKS.md](./docs/HOW-IT-WORKS.md), [docs/TO-DO.md](./docs/TO-DO.md).
이 파일은 코드 컨벤션 only.

---

## ⛔ 금지

1. **OG meta 는 route `meta` export 만.** client-only `<head>` 조작 금지 (카톡 크롤러 JS 실행 안 함).
2. **Vercel 등 다른 deploy target 추가 금지.** Cloudflare Workers only.
3. **친밀·갈등 본문, PII (이름·생년월일·얼굴 이미지) 응답 0.**
4. **R2 / KV / Storage 도입 금지.** 카드 PNG 는 카톡 attachment 1회성.
5. **`metrics_json` 외 derived 데이터 (archetype·rule·score) DB 저장 금지** — 엔진이 load 시점 재계산.
6. **engine 재이식 금지.** 룰은 `/shared/` 한 곳. `pnpm build:shared` 로 양쪽 반영.
7. **flutter 의 SongMyung 폰트 룰 적용 X.** system default 만.
8. **`app/lib/shared/face_engine.js` commit 금지** (build artifact).

## 디자인

- system font only.
- 5단 size: 24 / 16 / 14 / 13 / 12 px.
- 4 컬러: `#1a1a1a` text, `#666` caption, `#c44` accent (점수만), `#f7f7f8` bg.

## 빌드

```bash
pnpm build:shared    # 첫 실행 전 필수
pnpm dev
pnpm typecheck
pnpm deploy
```
