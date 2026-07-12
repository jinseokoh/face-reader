# 재보정 측정 명세 — metric μ/σ 산출 규약

정면 인구 표본 → MediaPipe 468 landmark → `face_metrics.dart::computeAll()` parity 측정
→ metric별 μ/σ → `face_reference_data.dart::referenceData` 교체. 실행 절차는
[README §②](README.md), 26 metric 의 정의·현행 μ/σ·z 해석 표는
[HOW-IT-WORKS §2](../../flutter/docs/HOW-IT-WORKS.md) 가 SSOT.

z = (측정값 − μ) / σ — 모든 관상 룰이 이 z 임계로 발동하므로 μ/σ 가 판정 기준선이다.
좌표 기준 `faceWidth = dist(234,454)`, `faceHeight = dist(10,152)` (scale-invariant).

## 측정 규약 (parity 보장)

1. `extract_landmarks.py` 의 MediaPipe Face Landmarker(468, `face_landmarker.task`)로 추출.
2. ratio 공식은 `face_metrics.dart::computeAll()` 그대로 포팅 (`compute_ratios` 공유).
   raw→저장값 보정(예: `aspect_corr = aspect_raw·(imgH/imgW)·1.05`)도 동일 적용.
3. 품질 필터: near-frontal |yaw|,|pitch| < 18° 만 통과.
4. metric별 μ = mean(raw), σ = std(raw).
5. **성별 분리 유지** (dimorphism 큼 — pooled 하면 양쪽 다 부정확. 라벨 없는 표본만 pooled).
6. 교체 후 `flutter test test/calibration_test.dart` 로 quantile 재생성 →
   `score_distribution_test` 등 green 확인.

## 측면(3/4뷰) 필요 8 metric — 정면 표본 측정 불가

정면 사진엔 z 깊이·E-line 기하가 없어 재보정 대상에서 제외 (임상 추정 유지):

| 항목 (id) | 뜻 | z>0 해석 | 주 영향 |
|---|---|---|---|
| `dorsalConvexity` | 코 등선 돌출(직선도) | 볼록(매부리) | leadership · O-DC1 / 오목 O-DC2 관능 |
| `nasofrontalAngle` | 비전두각 | 경사 완만 | intelligence, trustworthiness · O-NF1 |
| `nasolabialAngle` | 비순각(코끝 들림) | 코끝 들림 | nose node |
| `facialConvexity` | 안면 돌출각 | 볼록한 옆모습 | profile |
| `noseTipProjection` | 코끝 돌출 | 코끝 길게 나옴 | nose node |
| `upperLipEline` / `lowerLipEline` | 입술 E-line 거리 | 입술 앞으로 나옴 | sensuality, libido · L-EL |
| `mentolabialAngle` | 순이각 | 경계 평평 | chin profile |

`computeAll()` 의 `eyebrowLength`·`noseBridgeRatio` 는 분류기 전용 — 재보정 비대상.
