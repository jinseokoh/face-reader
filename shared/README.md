# face_engine — shared physiognomy engine

Flutter (`refine`) 와 React (share host) 가 동시에 쓰는 **단일 SSOT**. 룰·reference·quantile 변경은 이 패키지 한 곳만.

## 빌드

```bash
# react/ 디렉토리에서
pnpm build:shared
```

내부적으로:

```bash
cd shared && dart compile js -O1 lib/face_engine.dart \
  -o ../react/app/lib/shared/face_engine.js
```

**`-O2` 금지** — `-O2` 의 type elimination + class minification 이 vite/rollup ESM
번들 + workerd 실행 단계에서 RTI subtype check 깨뜨린다 (`'minified:z2' is not a
subtype of 'minified:z'` 런타임 에러). `-O1` (default, WPO + inlining 포함) 만 안전.

## 의존

- **Flutter**: `flutter/pubspec.yaml` 의 `dependencies` 에 `face_engine: { path: ../shared }`
- **React**: `react/app/lib/traits.ts` 가 `./shared/face_engine.js` 의 `runEngine` 호출

## API

```dart
ShareOutput runEngine(String metricsJson);
// metricsJson = FaceReadingReport.toJsonString() (v3 capture-only)
// ShareOutput = { score, archetype, highlights[3] }
```

`ShareOutput` 외 어떤 데이터도 외부 노출 금지 — share host 가 보여줄 minimal subset 으로만 한정한다.

## P0 작업 — 엔진 추출

`flutter/lib/domain/services/` 에서 이 패키지로 이동:

- `physiognomy_scoring.dart`
- `attribute_derivation.dart`
- `attribute_normalize.dart`
- `score_calibration.dart`
- `archetype.dart`
- `face_metrics.dart` + `face_metrics_lateral.dart`

`flutter/lib/data/constants/face_reference_data.dart` 도 함께 이동.

이동 후 Flutter import 경로를 `package:face_engine/...` 로 일괄 변경.

## 산출물 commit 금지

`react/app/lib/shared/face_engine.js` 와 `react/app/lib/shared/face_engine.js.map` 은 빌드 산출물 — `.gitignore`.
