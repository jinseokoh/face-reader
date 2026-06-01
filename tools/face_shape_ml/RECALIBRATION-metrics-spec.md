# 재보정 측정 명세 — Kaggle pooled 인간 얼굴에서 구할 metric μ/σ

**작성**: 2026-06-01
**목표**: 전 인종 pooled ~5000장 정면 사진 → MediaPipe 468 landmark → `face_metrics.dart::computeAll()` parity 로 각 metric raw 측정 → metric별 **평균 μ / 표준편차 σ** 산출 → `face_reference_data.dart` 의 `referenceData` 교체.

> z = (이 사람 측정값 − μ) / σ. 모든 관상 룰은 이 z 임계로 발동한다. 따라서 μ/σ 가 곧 "평균 이상/이하" 판정의 기준선이고, 각 metric 의 z 해석이 곧 관상 해설이다.

좌표 기준: `faceWidth = dist(234,454)`(양 볼 외곽), `faceHeight = dist(10,152)`(이마끝~턱끝). 대부분 metric 은 이 둘로 정규화한 비율이라 셀카 거리·해상도와 무관(scale-invariant).

---

## A. 정면에서 측정 가능 — Kaggle 5000장 대상 (26개)

| # | 항목 (id) | 측정 정의 (landmark · 공식) | 타입 | 현 μ/σ (EA♀, 교체 대상) | z>0 (값 큼) 관상 해석 | z<0 (값 작음) 관상 해석 | 주 영향 속성·룰 |
|---|---|---|---|---|---|---|---|
| 1 | 얼굴 종횡비 `faceAspectRatio` | faceHeight / faceWidth | ratio | 1.30 / 0.07 | 세로로 긴 얼굴 → 부유·리더 인상 | 가로로 넓은 얼굴 | wealth, leadership · Z-FAR(≥1.2) |
| 2 | 얼굴 테이퍼 `faceTaperRatio` | dist(172,397) / faceWidth | ratio | 0.78 / 0.05 | 하악(턱)이 넓음 → 골격 강함 | 좁은 턱(V라인) | 얼굴형 분류 |
| 3 | 하단 풍만도 `lowerFaceFullness` | (jaw+jawLower+chinSide 폭) / (3·faceWidth) | ratio | 0.49 / 0.05 | 볼살·턱살 풍만(둥근 얼굴) | 갸름한 하단(V라인) | 얼굴형 분류 |
| 4 | 상안면 비율 `upperFaceRatio` | dist(10,168) / faceHeight | ratio | 0.31 / 0.04 | 이마 영역 큼 → 지성·신뢰 | 이마 좁음 | intelligence, trustworthiness · Z-FH |
| 5 | 중안면 비율 `midFaceRatio` | dist(168,94) / faceHeight | ratio | 0.32 / 0.03 | 중정 긺 → 재물·사회성 | 중정 짧음 | wealth, sociability · Z-11(≥1.0) |
| 6 | 하안면 비율 `lowerFaceRatio` | dist(94,152) / faceHeight | ratio | 0.37 / 0.05 | 턱 길음 → 안정·신뢰 | 턱 짧음 → 감정 풍부 | stability, trustworthiness · Z-12/Z-13 |
| 7 | 하악각 `gonialAngle` | ∠(귀132·고니온172·턱152) 양측 평균 | angle° | 143 / 6 | 각진 턱(둔각) | 둥근/좁은 턱 | leadership, stability (chin node) |
| 8 | 눈 사이 거리 `intercanthalRatio` | dist(133,362) / faceWidth | ratio | 0.26 / 0.02 | 눈 사이 넓음 → 카리스마·리더십 | 눈 사이 좁음 | leadership, wealth · Z-IC(≥0.5) |
| 9 | 눈 길이 `eyeFissureRatio` | 양안 (외안각33↔내안각133) 평균 / faceWidth | ratio | 0.21 / 0.025 | 눈이 긺 → 매력·감정·통찰 | 눈이 짧음 | eye node(emotionality·attractiveness·sensuality) |
| 10 | 눈꼬리 각도 `eyeCanthalTilt` | 외안각 기울기(°), 양측 평균 | angle° | 5.0 / 4.0 | 눈꼬리 올라감 → 매력(媚)·관능 | 눈꼬리 내려감 | attractiveness, sensuality · O-MM·P-06 |
| 11 | 눈썹 두께 `eyebrowThickness` | 눈썹 상·하연 3구간 평균 두께 / faceHeight | shape | 0.036 / 0.005 | 눈썹 두꺼움 → 정력·리더십 | 눈썹 얇음 | libido, leadership (eyebrow node) |
| 12 | 눈썹-눈 거리 `browEyeDistance` | dist(눈썹하연105,눈위159) / faceHeight | shape | 0.138 / 0.020 | 전택궁 넓음 | 눈썹-눈 가까움 | eyebrow node |
| 13 | 코 너비 `nasalWidthRatio` | dist(98,327) / 눈사이거리(icd) | ratio | 0.93 / 0.10 | 코 넓음(콧방울 큼) | 코 좁음 | nose node(wealth) |
| 14 | 코 길이 `nasalHeightRatio` | dist(nasion168, noseTip1) / faceHeight | ratio | 0.29 / 0.03 | 콧대 긺 → 중년 재물 발복 | 콧대 짧음 | wealth · A-M01 |
| 15 | 입 너비 `mouthWidthRatio` | dist(61,291) / faceWidth | ratio | 0.38 / 0.05 | 입 넓음 → 사회성 | 입 작음(櫻桃, 매력) | sociability · Z-LFR / O-RL gating |
| 16 | 입꼬리 각도 `mouthCornerAngle` | 입꼬리 vs 입중앙 기울기(°), 부호 보존 | angle° | 5.0 / 5.0 | 입꼬리 올라감(仰月口) | 입꼬리 내려감(俯月口) | mouth node |
| 17 | 입술 두께 `lipFullnessRatio` | dist(상순0, 하순17) / faceHeight | ratio | 0.12 / 0.025 | 입술 두꺼움 → 관능·사회성 | 입술 얇음 | sociability, attractiveness · Z-LFR·O-RL |
| 18 | 인중 길이 `philtrumLength` | dist(94, 상순0) / faceHeight | ratio | 0.094 / 0.020 | 인중 긺 → 안정·신뢰 | 인중 짧음 → 관능·정력 | O-PH2(긺) vs O-PH1(짧음→libido·sensuality) |
| 19 | 이마 폭 `foreheadWidth` | dist(관자54,284) / faceWidth | ratio | 0.88 / 0.04 | 이마 넓음(天庭) → 관록·사회운 | 이마 좁음 | forehead node |
| 20 | 광대 폭 `cheekboneWidth` | dist(116,345) / faceWidth | ratio | 0.93 / 0.04 | 광대 넓음 → 권력·자아 | 광대 좁음 | leadership · O-CK; 過하면 O-CKE 매력− |
| 21 | 턱 각도 `chinAngle` | ∠(턱측면148·턱끝152·377) | angle° | 170 / 5 | 둥글고 넓은 턱(方頤) | 뾰족한 턱(尖頤) | chin node |
| 22 | 눈 세로/가로 `eyeAspect` | 양안 (세로/가로) 평균 | ratio | 0.32 / 0.06 | 둥글고 큰 눈(圓眼) | 가늘고 긴 눈(鳳眼) | eye node |
| 23 | 눈썹 곡률 `eyebrowCurvature` | 중앙점이 양끝 현(chord)보다 위로 솟은 정도 / faceHeight | shape | 0.038 / 0.005 | 아치형 눈썹(彎眉) | 직선/처진 눈썹(八字) | eyebrow node |
| 24 | 눈썹 기울기 `eyebrowTiltDirection` | (눈썹머리y − 꼬리y) / faceHeight, 부호 보존 | shape | 0.000 / 0.012 | 꼬리 올라감(劍眉) | 꼬리 내려감(八字眉) → 관능·감성 | sensuality, emotionality · Z-EBT(≤−1) |
| 25 | 윗/아랫입술 비율 `upperVsLowerLipRatio` | 윗입술두께 / 아랫입술두께 | ratio | 0.62 / 0.10 | 윗입술 두꺼움(情多) | 아랫입술 두꺼움 | mouth node |
| 26 | 미간 너비 `browSpacing` | dist(눈썹머리55,285) / faceWidth | ratio | 0.20 / 0.03 | 미간(印堂) 넓음 → 관대·재물·매력 | 미간 좁음 → 속좁음·예민 | wealth, leadership, attractiveness · P-09·P-MJ vs P-09B |

> 참고: `computeAll()` 은 `eyebrowLength`·`noseBridgeRatio` 도 내지만 이 둘은 referenceData·weight matrix 에 없는 분류기 전용 feature 라 재보정 대상 아님.

---

## B. 정면 Kaggle 로는 측정 불가 — 측면(3/4뷰) 필요 (8개)

이 8개는 ~30–45° yaw 측면 캡처에서만 나온다. 정면 사진엔 z 좌표 의존 + E-line 등 측면 기하가 없으므로 **이번 Kaggle 재보정 대상에서 제외**. 현재 임상 anthropometry 추정값 유지하거나, 별도 측면 데이터셋이 생기면 보정.

| 항목 (id) | 뜻 | z>0 해석 | 주 영향 |
|---|---|---|---|
| `dorsalConvexity` | 코 등선 돌출(매부리/직선도) | 매부리(볼록) | leadership · O-DC1 / 오목 O-DC2 관능 |
| `nasofrontalAngle` | 비전두각(이마-코 경사) | 경사 완만 | intelligence, trustworthiness · O-NF1 |
| `nasolabialAngle` | 비순각(코끝 들림) | 코끝 들림 | nose node |
| `facialConvexity` | 안면 돌출각 | 볼록한 옆모습 | profile |
| `noseTipProjection` | 코끝 돌출 | 코끝 길게 나옴 | nose node |
| `upperLipEline` / `lowerLipEline` | 입술 E-line 거리 | 입술 앞으로 나옴 | sensuality, libido · L-EL |
| `mentolabialAngle` | 순이각(입술-턱 경계) | 경계 평평 | chin profile |

---

## C. 측정 절차 (parity 보장)

1. 입력: pooled ~5000 정면 얼굴 (전 인종, 가능하면 성별 라벨만 — μ/σ 를 성별로 나눌지 결정용).
2. `extract_landmarks.py` 의 MediaPipe Face Landmarker(468, `face_landmarker.task`) 로 landmark 추출.
   - 기존 18-metric 추출을 **§A의 26개 전체로 확장** (face_metrics.dart 공식 그대로 포팅, 일부는 이미 구현됨).
   - face_analysis.dart 의 `aspect_corr = aspect_raw·(imgH/imgW)·1.05` 등 raw→저장값 사이 보정이 있으면 동일 적용.
3. 품질 필터: landmark 신뢰도/정면도(yaw) 낮은 샘플 제외.
4. metric별 μ = mean(raw), σ = std(raw) 산출.
5. `referenceData` 교체 (pooled 단일 baseline 을 전 인종 cell 에 적용, 성별 분리 여부는 §A 성별 라벨 유무로 결정).
6. `flutter test test/calibration_test.dart` 재실행 → quantile table 재생성 (saturation 동반 해소).
7. 검증: 진단 harness 시나리오 A 패턴(점수 SD~1.2, 1위 속성 고른 분산) 회복.

> 성별: 현 referenceData 는 [ethnicity][gender] 2-cell. 인종은 pooled 로 단일화하더라도 **성별은 분리 유지 권장** (얼굴 dimorphism 이 커서 pooled 하면 양쪽 다 부정확). Kaggle 데이터에 gender 라벨이 있으면 male/female 따로 μ/σ.
