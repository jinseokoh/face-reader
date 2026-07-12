# face_engine — shared physiognomy engine

Flutter 앱과 react share host 가 동시에 쓰는 **단일 엔진 SSOT**.
룰·reference·quantile 변경은 이 패키지 한 곳만.

## 빌드 (react 용 JS 산출물)

```bash
cd react && pnpm build:shared
# = cd shared && dart compile js -O1 lib/face_engine.dart -o ../react/app/lib/shared/face_engine.js
```

**`-O2` 금지** — type elimination + class minification 이 vite/rollup ESM +
workerd 단계에서 RTI subtype check 를 깨뜨린다. `-O1` 만 안전.
산출물 `face_engine.js(.map)` 은 빌드 결과 — commit 금지 (`.gitignore`).

## 의존·API

- Flutter: `face_engine: { path: ../shared }` path dependency.
- React: `react/app/lib/traits.ts` 가 `./shared/face_engine.js` 로드.
- JS export 3개: `runEngine(metricsJson)`(solo 카드) · `runCompat(jsonA, jsonB)`(궁합) ·
  `runMetrics(...)`(웹 티저). 출력은 share 표면이 렌더할 minimal subset 만 —
  그 외 데이터 외부 노출 금지.

불변식: 이 패키지는 platform-free 순수 Dart (`dart compile js` 통과 필수).
