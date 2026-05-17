# face share host — Claude 컨벤션

아키텍처·계약·할 일은 [docs/HOW-IT-WORKS.md](./docs/HOW-IT-WORKS.md), [docs/TO-DO.md](./docs/TO-DO.md).
이 파일은 코드 컨벤션 only.

---

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
