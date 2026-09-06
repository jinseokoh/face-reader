# HOW IT WORKS — 관상 엔진 기술 구현

얼굴 입력부터 리포트 본문까지 엔진 계산의 SSOT.
화면·폴더 구조는 [ARCHITECTURE.md](ARCHITECTURE.md), 디자인 토큰은 [DESIGN.md](DESIGN.md).

## 1. 파이프라인

```
MediaPipe Face Mesh (468 landmarks · 정면 + 3/4 측면)
  → FaceMetrics.computeAll() 32 frontal(reference 30 + classifier 전용 2) + LateralFaceMetrics 8 (옵션)
  → z-score vs (ethnicity × gender) reference + 50+ age 보정
  → Track 1: TFLite 28-feat 얼굴형 분류 (oval/oblong/round/square/heart)
    Track 2: 14-node tree + 5-stage pipeline → 10 attribute raw
    Track 3: lateral 8 metric + 5 flag
  → rank+quantile normalize (5.0~10.0) → classifyArchetype → report_assembler
    + life_question_narrative → FaceReadingReport (Hive + Supabase mirror)
```

Entry point: `flutter/lib/domain/models/face_analysis.dart::analyzeFaceReading()`.

**코드 위치** — 엔진 계산은 순수 Dart 패키지 `shared/`(`package:face_engine`).
Flutter 는 path dep, web 은 `dart compile js -O1` 산출물로 같은 엔진 사용.

| 위치 | 파일 |
|---|---|
| `shared/lib/` | `physiognomy_tree` · `face_reading_report` · `metric_score` · `physiognomy_scoring` · `attribute_derivation` · `attribute_normalize` · `archetype` · `age_adjustment` · `yin_yang` · `compat/` · `face_reference_data` · enums |
| `flutter/lib/` | `face_analysis` · `face_metrics`(+lateral) · `life_question_narrative` · `report_assembler` · text_blocks · `face_shape_classifier` |

JS export: `runEngine`(solo) / `runCompat`(궁합) / `runMetrics`(웹 티저).
빌드 `cd web && pnpm build:shared` (`-O2` 금지 — RTI subtype check 깨짐).

## 2. 26 Frontal + 8 Lateral Metric

z = (측정값 − μ) / σ. 좌표 기준 `faceWidth = dist(234,454)`, `faceHeight = dist(10,152)`.
코드 SSOT: `face_metrics.dart::computeAll()` + `face_reference_data.dart::metricInfoList`.

**등방 보정 (필수)** — MediaPipe 는 x 를 이미지 **폭**, y 를 **높이**로 각각 나눈
0~1 좌표를 준다. 정사각형이 아닌 사진에서는 두 축의 축척이 달라 좌표계가
비등방이 되고, **각도와 세로÷가로 비율이 사진 규격에 따라 달라진다**
(`faceAspectRatio` · `gonialAngle` · `chinAngle` · `eyeCanthalTilt` ·
`mouthCornerAngle` · `eyeAspect` 6개). 가로÷가로 · 세로÷세로 비율 20개는 축척이
약분돼 영향이 없다.

`FaceMetrics(landmarks, aspect: imageHeight / imageWidth)` 가 y 를 되돌려 등방
공간에서 계산한다. **모든 호출부는 실제 이미지 종횡비를 넘겨야 한다** — 앱은
`face_analysis.dart::analyzeFace`, 웹은 `runMetrics(landmarksJson, aspect)`,
레퍼런스 추출은 `extract_landmarks.py::compute_ratios`. 세 경로의 수식은 1:1
동일해야 하며, `faceAspectRatio` 에만 추가로 `kLandmark10Correction = 1.05`
(랜드마크 10 이 실제 헤어라인보다 아래에 찍히는 것) 가 곱해진다.

이 성질은 `test/face_metrics_isotropy_test.dart` 가 지킨다 — 같은 픽셀 얼굴을
400×400 · 400×600 · 1080×1440 에 담아 26개 metric 이 모두 같게 나오는지 검사한다.

**Frontal 26** (μ/σ = AAF 재보정 여성 empirical, 남성 등은 `face_reference_data.dart`):

| # | 항목 (id) | 측정 정의 | 타입 | μ/σ (AAF♀) | z>0 해석 | z<0 해석 | 주 영향 |
|---|---|---|---|---|---|---|---|
| 1 | `faceAspectRatio` 얼굴 종횡비 | faceHeight / faceWidth | ratio | 1.223/0.066 | 세로로 긴 얼굴 → 부유·리더 | 가로로 넓음 | wealth·leadership (Z-FAR) |
| 2 | `faceTaperRatio` 테이퍼 | dist(172,397)/faceWidth | ratio | 0.793/0.025 | 넓은 턱·강한 골격 | 좁은 턱(V) | 얼굴형 |
| 3 | `lowerFaceFullness` 하단 풍만 | (jaw+jawLower+chinSide)/(3·faceWidth) | ratio | 0.507/0.020 | 볼살·턱살 풍만 | 갸름한 하단 | 얼굴형 |
| 4 | `upperFaceRatio` 상안면 | dist(10,168)/faceHeight | ratio | 0.306/0.019 | 이마 큼 → 지성·신뢰 | 이마 좁음 | intelligence·trust (Z-FH) |
| 5 | `midFaceRatio` 중안면 | dist(168,94)/faceHeight | ratio | 0.301/0.020 | 중정 긺 → 재물·사회성 | 중정 짧음 | wealth·sociability (Z-11) |
| 6 | `lowerFaceRatio` 하안면 | dist(94,152)/faceHeight | ratio | 0.394/0.035 | 턱 긺 → 안정·신뢰 | 턱 짧음 → 감정 풍부 | stability·trust (Z-12/13) |
| 7 | `gonialAngle` 하악각 | ∠(132·172·152) 평균 | 각° | 141.7/4.4 | 각진 턱 | 둥근 턱 | leadership·stability |
| 8 | `intercanthalRatio` 눈 사이 | dist(133,362)/faceWidth | ratio | 0.257/0.015 | 눈 사이 넓음 → 카리스마 | 좁음 | leadership·wealth (Z-IC) |
| 9 | `eyeFissureRatio` 눈 길이 | 양안 길이 평균/faceWidth | ratio | 0.189/0.011 | 눈 긺 → 매력·감정·통찰 | 눈 짧음 | eye node |
| 10 | `eyeCanthalTilt` 눈꼬리 각 | 외안각 기울기° 평균 | 각° | 5.9/2.6 | 올라감 → 매력·관능 | 내려감 | attractiveness·sensuality (O-MM·P-06) |
| 11 | `eyebrowThickness` 눈썹 두께 | 눈썹 3구간 두께/faceHeight | shape | 0.034/0.0026 | 두꺼움 → 정력·리더십 | 얇음 | libido·leadership |
| 12 | `browEyeDistance` 눈썹-눈 | dist(105,159)/faceHeight | shape | 0.141/0.016 | 전택궁 넓음 | 가까움 | eyebrow node |
| 13 | `nasalWidthRatio` 코 너비 | dist(98,327)/icd | ratio | 0.947/0.079 | 코 넓음 | 코 좁음 | nose (wealth) |
| 14 | `nasalHeightRatio` 코 길이 | dist(168,1)/faceHeight | ratio | 0.274/0.024 | 콧대 긺 → 중년 재물 | 짧음 | wealth (A-M01) |
| 15 | `mouthWidthRatio` 입 너비 | dist(61,291)/faceWidth | ratio | 0.386/0.047 | 입 넓음 → 사회성 | 작은 입 | sociability (Z-LFR/O-RL) |
| 16 | `mouthCornerAngle` 입꼬리 각 | 입꼬리 vs 중앙 기울기° (부호) | 각° | 6.7/6.0 | 올라감 | 내려감 | mouth node |
| 17 | `lipFullnessRatio` 입술 두께 | dist(0,17)/faceHeight | ratio | 0.129/0.032 | 두꺼움 → 관능·사회성 | 얇음 | sociability·attractiveness |
| 18 | `philtrumLength` 인중 길이 | dist(94,0)/faceHeight | ratio | 0.086/0.017 | 긺 → 안정·신뢰 | 짧음 → 관능·정력 | O-PH2 vs O-PH1 |
| 19 | `foreheadWidth` 이마 폭 | dist(54,284)/faceWidth | ratio | 0.848/0.032 | 넓음 → 관록 | 좁음 | forehead node |
| 20 | `cheekboneWidth` 광대 폭 | dist(116,345)/faceWidth | ratio | 0.911/0.014 | 넓음 → 권력·자아 | 좁음 | leadership (O-CK); 過 시 O-CKE 매력− |
| 21 | `chinAngle` 턱 각도 | ∠(148·152·377) | 각° | 169.5/2.5 | 둥근 턱 | 뾰족한 턱 | chin node |
| 22 | `eyeAspect` 눈 세로/가로 | 양안 세로/가로 평균 | ratio | 0.296/0.072 | 둥근 눈 | 가는 눈 | eye node |
| 23 | `eyebrowCurvature` 눈썹 곡률 | 중앙 솟음/faceHeight | shape | 0.039/0.0038 | 아치형 | 직선/처짐 | eyebrow node |
| 24 | `eyebrowTiltDirection` 눈썹 기울기 | (머리y−꼬리y)/faceHeight (부호) | shape | 0.002/0.014 | 올라감 | 내려감 → 관능·감성 | sensuality·emotionality (Z-EBT) |
| 25 | `upperVsLowerLipRatio` 윗/아랫입술 | 윗입술두께/아랫입술두께 | ratio | 0.597/0.110 | 윗입술 두꺼움 | 아랫입술 두꺼움 | mouth node |
| 26 | `browSpacing` 미간 너비 | dist(55,285)/faceWidth | ratio | 0.193/0.012 | 미간 넓음 → 관대·재물·매력 | 좁음 → 예민 | wealth·leadership·attractiveness (P-09·P-MJ vs P-09B) |
| 27 | `faceArea` 얼굴 면적 | 윤곽 다각형(36점) 면적 / faceWidth² | ratio | 0.966/0.053 | 폭 대비 면적 큼 | 작음 | §6 추가(2026-09-06) — 첫인상·프로필·비교만, 관상 트리 미사용 |
| 28 | `outlineCurvature` 윤곽 곡률 | 4πA/P² (등주비, 원=1) | ratio | 0.958/0.014 | 둥근 윤곽 | 길거나 각짐 | 〃 |
| 29 | `eyeSizeBalance` 양 눈 크기 균형 | 왼눈 면적/(왼+오른) | ratio | 0.499/0.037 | 왼눈 큼 | 오른눈 큼 | 〃 |
| 30 | `noseAxisTilt` 코 중심축 기울기 | ∠(nasion→코끝, nasion→턱) 부호 있는 각 | 각° | −0.23/5.05 | 코끝 왼쪽 | 코끝 오른쪽 | 〃 |

27~30 은 좌표에서 계산하며 저장 전 카드는 로드 때 `landmarks` 로 다시 만든다(`fromJsonString`). AAF reference 는
`test/new_metrics_calibration_test.dart` 로 생성. 랜드마크 10 보정(×1.05)은 2026-09-06 부터 `computeAll` 안에서 한다 —
웹 `runMetrics` 가 이 보정을 빠뜨려 웹 참여 카드의 얼굴 비율이 −0.77σ 치우쳐 있던 것을 같이 고쳤다.

`computeAll()` 의 `eyebrowLength`·`noseBridgeRatio` 는 분류기 전용 (referenceData 미사용).

**Lateral 8** — yaw ∈ [0.70, 0.88] (3/4 view) 만 수락:

| ID | 의미 | reference mean (F) |
|---|---|---|
| `nasofrontalAngle` | 비전두각 | ~141° |
| `nasolabialAngle` | 비순각 (tip rotation) | 130~140° |
| `facialConvexity` | 안면 돌출각 | ~7.7° |
| `upperLipEline` | 상순 E-line 거리 | ~-1mm |
| `lowerLipEline` | 하순 E-line 거리 | 동일 규약 |
| `mentolabialAngle` | 순이각 | ~134° |
| `noseTipProjection` | 코끝 돌출 | — |
| `dorsalConvexity` | 코 등선 곡률 | — |

5 lateral flag (`face_analysis.dart`): `aquilineNose`(dorsalConvexity z≥3) ·
`snubNose`(nasolabialAngle z≥2 AND raw≥115°) · `droopingTip`(z≤-2 AND raw≤112°) ·
`saddleNose`(dorsalConvexity z≤-3) · `flatNose`(noseTipProjection z≤-3).

**Reference 출처** — AAF-only 로 최종 (한·중·일 개인 구분 불가 → 층화·재보정 폐기):

| | frontal 26 | lateral 8 |
|---|---|---|
| eastAsian | AAF 실측 11,800장 empirical | proxy-frame empirical |
| 비-EA 5인종 | niten19 pooled in-frame 5,000장 | 임상 추정 (의도적 유지 — 측면 데이터셋 부재) |

## 3. 14-Node Tree

root 1 + 삼정 3 (upper/middle/lower) + leaf 10 (이마·미간·눈썹 / 눈·코·광대·귀 / 인중·입·턱).
코드 SSOT: `physiognomy_tree.dart`. `귀` 는 정면 mesh 커버리지 부족으로 `unsupported=true`.

- 노드 보유: `metricIds` + 메타데이터 태그(오관·오악·사독·십이궁) + `zone`
- `scoreTree(z)`: **own stats**(ownMeanZ signed + ownMeanAbsZ 강도) 와
  **roll-up stats**(자신+descendant) 분리 — 방향과 distinctiveness 독립 규칙 가능

| 메타 체계 | 매핑 |
|---|---|
| 오관 | 눈썹·눈·코·입·귀 |
| 오악 | 이마·광대좌·광대우·코·턱 |
| 사독 | 귀·눈·코·입 |
| 십이궁 | 명궁=미간, 재백궁=코, 형제궁=눈썹, 전택궁=눈상안검, 남녀궁=와잠, 노복궁=턱, 처첩궁=눈꼬리, 질액궁=산근, 천이궁=이마양옆, 관록궁=이마중앙, 복덕궁·상모궁=root |

## 4. 10 Attribute + 5-Stage Pipeline

| Attribute | Korean | 핵심 노드 | Archetype |
|---|---|---|---|
| `wealth` | 재물운 | 코 · 광대 · 턱 | 사업가형 |
| `leadership` | 리더십 | 턱 · 광대 · 이마 | 리더형 |
| `intelligence` | 통찰력 | 이마 · 눈 · 눈썹 | 학자형 |
| `sociability` | 사회성 | 입 · 광대 · 턱 | 외교형 |
| `emotionality` | 감정성 | 눈 · 미간 · 입 | 예술가형 |
| `stability` | 안정성 | 턱 · 미간 · 코 | 현자형 |
| `sensuality` | 바람기 | 눈 · 입 · 인중 | 연예인형 |
| `trustworthiness` | 신뢰성 | 이마 · 눈 · 턱 | 신의형 |
| `attractiveness` | 매력도 | 눈 · 입 · 광대 | 미인형 |
| `libido` | 관능도 | 눈썹 · 인중(-) · 눈 | 정열형 |

`attribute_derivation.dart::deriveAttributeScores()` — 5 stage 누적 합산:

| Stage | 이름 | 동작 |
|---|---|---|
| 1 | base linear | 9-node × 10-attr weight matrix (행 합 = 1.00), signed-z × weight × polarity |
| 1b | distinctiveness | intelligence(upper absZ) + emotionality(lower absZ) 가산 |
| 2 | zone rules (20) `Z-##` | 삼정 조화/대립 + root 비율 + 美 rule |
| 3 | organ rules (24) `O-##` | 오관 쌍 조합 |
| 4 | palace rules (11) `P-##` | 십이궁 cross-node overlay |
| 5 | gender/age/lateral (10+4+3) | 성별 delta + 50+ 보정 + 측면 flag (`L-AQ`/`L-SN`/`L-EL`) |

총 62 rule, magnitude cap `|Δ| ≤ 0.5` (invariant — step-function dominance 차단).

**Weight Matrix (9-node)** — 각 행 합 = 1.00, attribute 별 top node 상호 분리:

| Attribute \\ Node | 이마 | 미간 | 눈썹 | 눈 | 코 | 광대 | 인중 | 입 | 턱 |
|---|---|---|---|---|---|---|---|---|---|
| wealth | 0.12 | 0.10 | 0.08 | 0.08 | **0.20** | 0.10 | 0.07 | 0.10 | 0.15 |
| leadership | 0.13 | 0.08 | 0.15 | 0.10 | 0.15 | 0.10 | 0.03 | 0.08 | **0.18** |
| intelligence | **0.18** | 0.10 | 0.10 | 0.15 | 0.10 | 0.08 | 0.09 | 0.10 | 0.10 |
| sociability | 0.08 | 0.10 | 0.10 | 0.12 | 0.08 | 0.12 | 0.07 | **0.20** | 0.13 |
| emotionality | 0.06 | 0.13 | 0.12 | **0.20** | 0.08 | 0.08 | 0.10 | 0.13 | 0.10 |
| stability | 0.12 | 0.15 | 0.08 | 0.08 | 0.13 | 0.10 | 0.08 | 0.08 | **0.18** |
| sensuality | 0.05 | 0.08 | 0.13 | **0.17** | 0.10 | 0.08 | 0.15 | **0.17** | 0.07 |
| trustworthiness | **0.15** | 0.12 | 0.06 | **0.15** | 0.13 | 0.07 | 0.07 | 0.10 | **0.15** |
| attractiveness | 0.07 | 0.07 | 0.13 | **0.17** | 0.10 | 0.13 | 0.07 | **0.17** | 0.09 |
| libido | 0.05 | 0.08 | **0.17** | 0.13 | 0.10 | 0.10 | 0.15(−) | 0.12 | 0.10 |

**Archetype**: 상위 2 속성 → primary/secondary. 복합 조건 시 special (`archetype.dart`,
shape-gated overlay 포함):

special 판정은 **원 normalized score** 기준 (gender prior 는 ranking 전용).
임계값은 5.0~10.0 스케일에서 9.0=상위 ~15%, 9.5=상위 ~7%, ≤6.0=하위 ~20%
(2026-07-25 재설계 — 과거 7.5/7.0 은 중앙값 근처라 98% 가 special 을 받고
제왕형이 58% 를 독식했다. 재발 가드: archetype_fairness_test 의 rate cap.)

| ID | 조건 | Label |
|---|---|---|
| SP-1 | wealth≥9.5 AND leadership≥9.5 | 제왕상 |
| SP-2 | sensuality≥9.5 AND attractiveness≥9.5 | 도화상 |
| SP-3 | intelligence≥9.5 AND stability≥9.5 | 군사상 |
| SP-4 | sociability≥9.5 AND attractiveness≥9.0 | 연예인상 |
| SP-5 | wealth≥9.5 AND trustworthiness≥9.0 | 복덕상 |
| SP-6 | leadership≥9.0 AND stability≥9.0 AND trust≥8.5 | 대인상 |
| SP-7 | libido≥9.5 AND sensuality≥9.0 | 풍류상 |
| SP-8 | intelligence≥9.5 AND emotionality≥9.0 | 천재상 |
| SP-9 | stability≤5.5 AND emotionality≥9.0 | 광인상 |
| SP-10 | trust≤6.0 AND sociability≥8.5 | 사기상 |

## 5. Normalize (raw → 5.0~10.0)

`attribute_normalize.dart::normalizeAllScores()`:

```
raw → globalPct = _rawToPercentile(raw, attr, gender)   ← 21-point quantile 보간
       rankPct = (9 - rank) / 9                          ← 얼굴 내 10 속성 desc
       blend   = 0.35 × rankPct + 0.65 × globalPct
       score   = 5.0 + blend × 5.0                       ← [5.0, 10.0]
```

- quantile table 은 **per-shape × gender** (`_attrQuantilesMale`/`_attrQuantilesFemale`) —
  **AAF 11,800장 실측**(male 5361 / female 6439)을 프로덕션 파이프라인에 통과시켜
  오프라인 생성해 코드에 박음. 앱 런타임은 표를 읽기만 한다. 합성 분포가 아니므로
  부위 간 상관·왜도·얼굴형 구성비가 전부 데이터에서 나온다.
- 표본 400장 미만 (얼굴형×성별) 셀은 싣지 않는다 (oblong♀ 244 · square♀ 362 ·
  heart♂ 60). `_quantileFor` 가 성별 전체 테이블로 폴백한다.
- weight matrix·rule·reference 변경 시 재생성 필수:
  `flutter test test/calibration_empirical_test.dart` → 출력 map 을
  `attribute_normalize.dart` 에 paste.
- **분포 검증 테스트는 반드시 같은 실측 얼굴을 입력으로 쓴다**
  (`test/support/aaf_faces.dart`). 합성 입력으로 재놓고 실측 테이블로 정규화하면
  서로 다른 두 세계를 섞는 것이라 발동률·포화도 수치가 의미를 잃는다.
- Invariant (`score_distribution_test.dart`, AAF 실측): median 7.3~7.8 ·
  saturation(>9.5) 3.1~9.5%. 공정성(`archetype_fairness_test.dart`):
  primary 최저 7.20% ~ 최고 14.67%.
- 궁합도 동일 방식 별도 도구: `compat_calibration_test.dart` → `compat_label.dart` 경계 +
  `compat_aggregator.dart` anchor(p30/p60/p90 → 56/78/90).

## 6. Hive 저장 (capture-only)

> **저장**: raw metric + 촬영 맥락 + UI 메타. **저장 안 함**: z·nodeScores·attributes·rules·archetype.
> 엔진이 오르면 모든 리포트가 load 시 자동으로 새 결과를 받는다.
> `kReportSchemaVersion` bump 는 capture 필드 변경 시에만.

**Hive ↔ Supabase metrics**: 컬럼 = 관계·소유 메타(snake_case) / body = 분석 payload(camelCase).

| prop | Hive `toJsonString` | Supabase 위치 | 역할 |
|---|---|---|---|
| id / supabaseId | body `supabaseId` | **column `id`** | 공유 UUID·PK |
| userId | ✗ | **column `user_id`** | 업로더(anon=null), 소유·RLS |
| alias | body | **column** | 소유자 지정 이름 (내 관상은 nickname 파이프라인) |
| isMyFace | body | **column `is_my_face`** | 본인 얼굴 플래그 |
| views / createdAt / updatedAt | ✗ | **column** | 조회수·publish·활동 (updatedAt = 90일 정리 기준) |
| schemaVersion(=2) · demographics · timestamp · source · thumbnailKey · metrics · lateralMetrics · symmetry · modelVersion · landmarks · lateralLandmarks · faceShape* | body | body | 분석 payload (z/score 는 load 시 재계산). symmetry = 대칭 6 raw, modelVersion = {geometry, impression, pair} (§58). landmarks = 정면 468×[x,y] 등방 원본 좌표 소수 4자리(스키마 2 필수, 없으면 폐기), lateralLandmarks = 측면(선택). 계측이 늘거나 바뀌면 여기서 다시 계산한다. thumbnailKey = `thumbnails/{owner}/{sha256}.jpg` — 첫 칸이 소유자(탈퇴 시 폴더째 삭제), 로컬 캐시 파일명은 뒤 칸에서 파생 |

재계산 흐름 (`fromJsonString()`): raw→z(현재 reference)→age 보정 → lateralFlags →
scoreTree → deriveAttributeScoresDetailed → normalizeAllScores → classifyArchetype.

Hive Box 3종: `history`(리포트 JSON list) · `prefs` · `auth`(Supabase 세션).

**신규 Metric 추가 체크리스트**:
1. `face_metrics.dart::computeAll()` 계산 추가
2. `face_reference_data.dart::metricInfoList` entry
3. 같은 파일 `referenceData` 12 (ethnicity×gender) entry mean/sd
4. `physiognomy_tree.dart` 노드 `metricIds`
5. `attribute_derivation.dart` weight/rule (필요 시)
6. `extract_aaf.py` 재추출 → `calibration_empirical_test` → 새 quantile → `attribute_normalize.dart`
7. `kReportSchemaVersion` bump (신규 rule 만이면 bump 불필요)

## 7. 궁합 엔진 (5 frame)

`shared/lib/domain/services/compat/`. 입력 = 두 `FaceReadingReport` capture 만
(attributes/archetype 미의존 — double-interpretation 차단).

| sub | 이름 | weight | 입력 |
|---|---|---|---|
| `elementScore` (L1) | 五形和 | 0.20 | 얼굴형 metric 7개 + faceShape → 五行 + 5×5 상생상극 |
| `palaceScore` (L2) | 宮位調 | 0.40 | ~22 metric → 12 궁 state + ~40 PalacePair rule |
| `qiScore` (L3) | 氣質合 | 0.25 | 五官 1:1 (0.55) + 三停 (0.25) + 陰陽 (0.20) |
| `intimacyScore` (L4) | 性情諧 | 0.15 | 항상 계산, narrative tone 만 분기 |

```
rawTotal = 0.20·element + 0.40·palace + 0.25·qi + 0.15·intimacy
total = clamp(50 + (rawTotal - 50) × 1.4, 5, 99)
```

- intimacy tone: `pure`(동성 or 10대/70대+) / `flirty`(이성 + 한쪽 20대·60대) /
  `spicy`(이성 + 양쪽 30~50대) — narrative 만 분기.
- Label 4-tier (`compat_label.dart`, MC p30/p60/p90 = 61.56/81.42/90.50):
  天作之合(≥90.5) · 琴瑟相和(81.5~) · 磨合可成(61.5~) · 刑剋難調(<61.5).
- capture-only: Hive 저장은 `myReportId`·`albumReportId`·`evaluatedAt` 뿐 — 본문은 재계산.
- 상세 rule 카탈로그의 SSOT 는 코드: `compat_pipeline.dart` + `palace_rules.dart`.

## 7b. 첫인상 엔진 (문헌 기반 계산 모델) — APPLE.md §81

학습하지 않는다. 공개 학술연구의 "특징 → 인상" 방향만 쓰고 원 논문 계수는 옮기지 않는다.
세 층으로 나뉘며 코드 위치가 곧 층이다.

| 층 | 파일 (shared/) | 내용 |
|---|---|---|
| 1 학술 보고 관계 | `data/constants/impression_evidence.dart` | 축 4개 × 논문이 보고한 특징의 부호·비중(주 1.0/보조 0.5)·출처(OT08·TD13·SU13·SU18·VE14·RH06) |
| 2 재구성 feature | `domain/services/impression_features.dart` | 그 특징을 30 계측 z 로 재정의. `averageness` = −mean\|z\|(30개), `symmetry` = −z(symOverall) |
| 3 제품 지표 | `domain/services/first_impression.dart` | 축 원점수 = Σ(부호×비중×feature z) → AAF 11,800 실측 분위표(`impression_quantiles.dart`, 성별 21-point)로 백분위 0~100 |

축 4개: 신뢰감 있는 · 친근한 · 주도적인 · 매력적인 인상. **매력은 본인 화면 전용** — 두 얼굴·케미에 쓰지 않는다.

**좌우 대칭** (`domain/services/symmetry_metrics.dart`): nasion(168)→chin(152) 중심선에 좌우 짝 랜드마크를
거울 대칭시킨 거리/얼굴 폭 → 눈·눈썹·코·입·윤곽 5영역 + 전체(평균). 0 = 완전 대칭. 성별 reference(mean/sd/21-point,
`symmetry_reference.dart`, AAF 11,800 실측 — `tools/face_shape_ml/extract_aaf_symmetry.py` 와 1:1)로 z·백분위.
리포트 `symmetry` 필드에 raw 저장(카드마다 재계산 없음). 신뢰(보조)·매력(주) 축에 feature 로 들어간다.
재생성: `flutter test test/symmetry_calibration_test.dart`.

**기하학 프로필** (§7, `domain/services/geometry_profile.dart`): 영역(`geometryRegions` 6개) 원점수 = 그 영역 계측
mean|z| → 성별 21-point 분위표(`geometry_profile_quantiles.dart`, AAF 실측)로 백분위 → 점수 = 100 − 백분위
(평균에 가까울수록 높음) + `symmetry`(전체 대칭, 높을수록 대칭). 리포트 "얼굴 기하학 프로필" 섹션.
첫인상 축 근거는 §13 문장형 — "{계측}이(가) 높은/낮은 편(±0.5σ)/기준 범위" + 높이는/낮추는 방향.

**정규화·Procrustes** (§5, `domain/services/landmark_normalize.dart`): 저장 좌표 → 무게중심 0 · RMS 1 · 눈꼬리(33→263) 수평.
두 얼굴은 정규화 뒤 [b]를 [a]에 최소제곱 회전으로 맞춘다(`alignFaces`, 영역 RMS 거리 제공). 정규화 좌표는 저장하지
않는다. `landmarkRegions`/`landmarkContours` 는 MediaPipe 표준 윤곽 인덱스. 화면: 리포트 "얼굴 지도"(§55) = 성별 평균 얼굴(`average_face.dart`, AAF 정규화 좌표 평균, 회색) 위에 내 얼굴을
겹치고 특이점 3개 계측의 측정선(`widgets/metric_landmark_paths.dart`, 30 계측 → 인덱스 경로)을 양쪽에 그린다 ·
비교 "두 얼굴 겹쳐 보기"(§24, 닮은 영역 강조) — `widgets/landmark_mesh_painter.dart`.
**닮은 정도 = Procrustes 거리** (`computeGeometrySimilarity(landmarksA, landmarksB)`): 정렬 뒤 RMS 거리를
`100·exp(−ln2·d/median)` 로, median 은 AAF 무작위 쌍 20,000개의 영역별 중앙 거리(`procrustes_reference.dart`,
overall 0.1105 · 윤곽 0.197 · 눈 0.059 · 눈썹 0.090 · 코 0.106 · 입 0.100 · 턱선 0.213). §25 문구 사분위도 같은 파일.
AAF 좌표 원본: `tools/face_shape_ml/extract_aaf_landmarks.py` → `out/aaf_landmarks.f32` (11,800×936 float32).
재생성: `flutter test test/procrustes_calibration_test.dart` (케미 등급 경계도 함께).

**공유 링크 경로**: 카드(얼굴 기록)는 종류가 없다 — 스키마 2 는 관상·첫인상 둘 다 계산할 수 있는 한 데이터다.
어느 화면으로 그릴지는 보는 쪽이 정한다: 앱은 에디션(`kMeasureEdition`), 케미 방은 mode, 웹은 링크 경로.
iOS(measure)가 만드는 공유 링크는 `/s/{id}`·`/s/{a}~{b}` (첫인상·비교, `runMeasure`/`runMeasurePair`), Android 는 `/r/…`
(관상·궁합). 딥링크는 두 경로 다 받고 앱 안에서는 에디션이 화면을 정한다 (`share_publisher.dart::_seg`, AASA·매니페스트 `/s/*`).

**결과 공개 5단계** (§54, measure): 정보 확인의 [확인] 뒤 `AnalysisStageOverlay` 가 얼굴 측정 중 → 얼굴 기하학
분석 → 첫인상 분석(각 0.8초 최소)을 덮어 보여주고, 정보 확인을 닫으며 바로 `ReportPage` 를 연다(등록 대화상자
없음). 리포트 본문은 "당신의 첫인상 프로필"(4축 표) → "왜 이런 결과가 나왔을까요?"(축별 근거 카드) 순.
**사진별 첫인상** (§56, `compatibility/photo_compare_screen.dart`): 비교 탭 앱바에서 카드 2~4장을 골라 4축 +
얼굴 대칭을 사진 A/B/C/D 열로 나란히. 같은 사람인지는 사용자가 고른다.

**분석 확신도** (§14·§29, `domain/services/analysis_confidence.dart`): 사진 상태 3단(높음·보통·낮음) — 좌표에서 본
yaw(|(l−r)/(l+r)|, AAF p95 0.45 / 정면 한계 0.70) · 얼굴 폭/사진 폭(0.20) · 전체 대칭 z(2/3). 가장 나쁜 신호를 따른다.
리포트 면책 카드와 공유 카드에 "분석 확신도". **첫인상 카드** (§55, 공유 카드): 매력 제외 3축을 5칸 막대
(백분위 20% 단위, `segmentLevel`)로 — 매력은 본인 화면 전용(§81.2).

**모델 버전** (§58·§59, `data/constants/model_version.dart`): geometry · impression · pair 세 문자열. 리포트
`modelVersion` 과 첫인상 방 payload `modelVersion` 에 기록. 화면은 저장된 z 에 현재 분위표를 다시 적용하므로
카드 버전 ≠ 현재 버전이면 리포트 "모델 버전" 카드가 알린다. 엔진에 난수 없음 → 같은 입력 = 같은 결과
(`test/model_version_test.dart` 의 고정값 회귀가 지킨다. 계측 식·reference 를 바꾸면 geometry 버전을 올린다).

두 얼굴 (`analyzePair`): 닮은 정도 = 저장 좌표의 Procrustes 거리(위) — 영역별(outline·eyes·brows·nose·mouth·jaw) 동일 식 · 첫인상 유사도 = 100 − mean\|Δ\| · 조화도 = mean(max(A,B))
(가설 지표) · 보완도 = mean\|Δ\| (매력 제외 3축). **케미 점수 = 조화도 + 보완도 + 닮은 정도 (0~300).**
비교 상세(measure)는 그 위에 여섯 가지를 더 보인다: 무작위 쌍 대비 닮은 정도·케미 합 상위 N%
(`kPairSimilarityQuantiles`·`kChemistryQuantiles`, 21-point) · 겹친 그림의 점별 차이(`showPointDiff`) · 축별 차이 문장과
차이를 만든 feature 2개(`axisContributions`) · 조화도에서 축을 채우는 쪽 · 둘 다 |z|≥1 인 계측의 같은/반대 방향
(`sharedDeviations`) · 대칭 상위 N% 와 얼굴형 나란히.
영역 닮은 정도 문구(§25, `SimilarityBand`): 무작위 쌍 사분위 `kRegionSimilarityQuartiles` [p75,p50,p25] 기준
매우 유사 · 유사 · 차이가 있음 · 차이가 큼. 비교 화면은 닮은 부분/다른 부분으로 나눠 보여준다.

**케미 방 mode** (`teams.mode`, 0008): `physiognomy` = §7 궁합 엔진 total(0~100)+4단 등급 ·
`first_impression` = 위 케미 점수, 등급은 AAF 무작위 쌍 사분위(p75/p50/p25 = 167.2/148.7/130.5, Procrustes 닮은 정도 · 30 계측 기준),
차단 상한 130.4. `computeTeam(scoring: TeamScoring.forMode(mode))`. measure 에디션(iOS)은
`TeamScoring.firstImpression` 만 쓴다 (에디션은 플랫폼 런타임 판정, `core/edition.dart`).
분위표 재생성: `flutter test test/impression_calibration_test.dart`.

## 8. 서술 엔진 (life_question_narrative)

8 인생 질문 섹션: 재능 · 재물운 · 대인관계 · 연애운(남/여 pool) · 바람기(20+, 남/여) ·
관능도(30+, 남/여) · 건강과 수명 · 종합 조언 (50+ 는 "덜어내는 기술" 분기).

- **Beat-Fragment Grammar**: `_BeatPool = List<_Frag>`, `_Frag = (soft predicate 0~1, variants)`.
  face hash seed(FNV, metrics+attributes+nodeScores) → 같은 얼굴 = 같은 본문 (결정론).
  섹션/빗/슬롯 salting 으로 독립 stream.
- **슬롯**: `@{slot}` + `{a|b|c}` alternation, 성별 분기 `_m`/`_f`. `@{heard}` = 2인칭 경험
  예언. `@__ONELINER__` = 종합 조언 말미 한 줄 평 (상위 2 attribute 대비 조합, Step 0 치환).
- **톤 6 레버**: 관찰→해석 · 행동 vignette(`_Xvignette` beat) · 이중성 훅 · `@{heard}` ·
  평범 단문(한자 jargon 금지) · 한 줄 평.
- **14-node expandable** (`node_text_blocks.dart`): 14 node × 3 band × shared|male|female.
  성별 분기 4 node (eye/nose/mouth/cheekbone).

## 9. Face Shape Classifier (Track 1)

28-feature MLP (TFLite 18 KB) — niten19 4000 + East Asian 사용자 57 mixed 학습.
EA 5-fold CV accuracy 47.6%. `_priorRatio` = uniform (보정은 학습 단에 내장).
입력 28 feature: `face_shape_classifier.dart::featureNames` (학습-추론 정렬 필수).
재학습·배포: `tools/face_shape_ml/README.md`.

## 10. 빌드·검증

```bash
cd flutter && flutter pub get
flutter test             # 전부 green
flutter analyze          # 기준선 7건 (경미)
# weight/rule/reference 변경 후:
flutter test test/calibration_test.dart   # → 출력 map 을 attribute_normalize.dart 에 paste
flutter test test/archetype_fairness_test.dart test/score_distribution_test.dart
```

| 회귀 차단 Test | 검증 |
|---|---|
| `physiognomy_tree_sanity_test` | row sum, zone 합, per-metric 영향력 ∈ [0.15, 1.20] |
| `shape_archetype_bias_test` | 5 shape × 2000 top-1 분포 < 35% |
| `archetype_template_sanity_test` | 6 template hit rate ≥ 55% |
| `score_distribution_test` | spread·saturation invariant |
| `evidence_snapshot_test` | 고정 z-map 완전 snapshot |
| `face_shape_posterior_test` | posterior 수학 + 합 = 1 |

주요 상수: `kLandmark10Correction = 1.05`(이마 끝점) · `kReportSchemaVersion = 1` ·
앨범은 square-padding 후 MediaPipe (non-square distortion 차단).

앨범 품질 검사(§60, `domain/services/photo_quality.dart`): 얼굴 없음 · 얼굴 짧은 변 < 사진 짧은 변의 12% ·
얼굴 상자 평균 밝기 < 40 이면 점수를 만들지 않고 문구만. 정면 사진의 yaw 가 정면이 아니면 [다른 사진 선택] 만.
흐림 판정은 보정 데이터가 없어 v1 에서 뺐다. 여러 얼굴(§61): ML Kit 상자를 번호로 그려 고르게 하고, 고른 얼굴만
MediaPipe 에 넘기며 성별·연령 추정에는 그 얼굴 주변 1.6배 crop 을 보낸다.
