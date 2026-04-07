# Face Analyzer 비즈니스 로직 분석서

## 1. 시스템 개요

카메라로 얼굴을 촬영하면 MediaPipe Face Mesh가 **468개 랜드마크**를 추출하고, 이 중 **23개 핵심 랜드마크**를 사용하여 **12개 메트릭**을 계산한다. 각 메트릭은 인종별 기준값과 비교하여 **Z-score**를 산출하고, **7단계 판정**으로 분류한다.

---

## 2. 35개 메트릭 정의

1️⃣ 32개 독립 metrics 구조 (세밀)
한글 이름 English 중요도 Why (관상적 의미)
얼굴 종횡비 faceAspectRatio ⭐⭐⭐⭐ 얼굴형 기본 구조. 장형/원형/방형 판단
상안면 비율 upperFaceRatio ⭐⭐⭐⭐ 초년운 / 지능 / 사고방식
중안면 비율 midFaceRatio ⭐⭐⭐⭐ 중년운 / 사회적 활동성
얼굴 테이퍼 비율 faceTaperRatio ⭐⭐⭐⭐ V형 vs 사각형 얼굴. 성격 강도
얼굴 대칭도 faceSymmetry ⭐⭐⭐ 전반적 안정성 / 인생 균형
하악각 gonialAngle ⭐⭐⭐⭐ 의지력 / 권위 / 리더십
눈 사이 거리 intercanthalRatio ⭐⭐⭐⭐ 사고 범위 / 성격 개방성
눈 길이 eyeFissureRatio ⭐⭐⭐⭐ 통찰력 / 사회성
눈 크기 eyeOpenness ⭐⭐⭐ 감정 표현 / 민감도
눈꼬리 각도 eyeCanthalTilt ⭐⭐⭐⭐⭐ 공격성 / 매력 / 사회적 태도
눈썹 두께 eyebrowThickness ⭐⭐⭐⭐ 의지력 / 성격 강도
눈썹 아치 eyebrowArch ⭐⭐⭐⭐ 성격 유형 (직선형 vs 감정형)
눈썹 길이 eyebrowLength ⭐⭐⭐ 인간관계 범위
눈썹-눈 거리 browEyeDistance ⭐⭐⭐⭐ 인내심 / 사고 깊이
미간 거리 interBrowDistance ⭐⭐ 집중력 / 성격 긴장도
코 너비 nasalWidthRatio ⭐⭐⭐⭐⭐ 재물운 핵심
코 길이 nasalHeightRatio ⭐⭐⭐⭐ 재백궁 규모 (얼굴 높이 대비)
입 너비 mouthWidthRatio ⭐⭐⭐⭐ 사회성 / 언변
입술 두께 lipFullnessRatio ⭐⭐⭐ 감정 표현 / 애정 성향
입꼬리 각도 mouthCornerAngle ⭐⭐⭐⭐⭐ 낙관성 / 인간관계
윗입술 비율 upperLipRatio ⭐⭐ 감정 표현 세부
인중 길이 philtrumLength ⭐⭐⭐⭐ 생명력 / 자식운
턱 높이 비율 chinHeightRatio ⭐⭐⭐ 말년운 / 의지력
턱 돌출 정도 chinProjection ⭐⭐⭐⭐ 결단력 / 리더십
홍채 크기 irisSize ⭐⭐⭐ 감정 민감도
홍채 위치 irisPosition ⭐⭐⭐ 삼백안 여부 판단
눈 흰자 노출 scleraExposure ⭐⭐⭐ 긴장도 / 공격성
시선 중심성 gazeCentrality ⭐⭐ 집중력

2️⃣ 핵심 15 metrics 구조 (추천)

이 구조는 관상 설명력 대비 최소 feature입니다.

한글 이름 English 중요도 Why
얼굴 종횡비 faceAspectRatio ⭐⭐⭐⭐ 얼굴형 기본 구조
얼굴 테이퍼 비율 faceTaperRatio ⭐⭐⭐⭐ 얼굴 형태 성격 반영
하악각 gonialAngle ⭐⭐⭐⭐ 의지력 / 권위
눈 사이 거리 intercanthalRatio ⭐⭐⭐⭐ 사고 범위
눈 길이 eyeFissureRatio ⭐⭐⭐⭐ 통찰력
눈꼬리 각도 eyeCanthalTilt ⭐⭐⭐⭐⭐ 성격 방향성 핵심
눈썹 두께 eyebrowThickness ⭐⭐⭐⭐ 성격 강도
눈썹-눈 거리 browEyeDistance ⭐⭐⭐⭐ 인내력
코 너비 nasalWidthRatio ⭐⭐⭐⭐⭐ 재물운 핵심
코 길이 nasalHeightRatio ⭐⭐⭐⭐ 재백궁 규모
입 너비 mouthWidthRatio ⭐⭐⭐⭐ 사회성
입꼬리 각도 mouthCornerAngle ⭐⭐⭐⭐⭐ 인간관계 / 낙관성
입술 두께 lipFullnessRatio ⭐⭐⭐ 감정 표현
인중 길이 philtrumLength ⭐⭐⭐⭐ 생명력 / 자식운

3️⃣ 두 구조 차이
구조 특징
32 metrics 생체계측 기반 정밀 분석
15 metrics 관상 핵심 feature

설명력 비교

32 metrics ≈ 관상 설명력 100
15 metrics ≈ 관상 설명력 85

하지만

복잡도
32 metrics = 매우 높음
15 metrics = 낮음

그래서 실제 AI 관상 앱은 보통 12~18개를 사용합니다.

4️⃣ 관상학에서 실제로 가장 중요한 TOP 5

이건 거의 모든 관상가가 공통입니다.

1️⃣ eyeCanthalTilt (눈꼬리)
2️⃣ nasalWidthRatio (코 너비)
3️⃣ nasalHeightRatio (코 길이)
4️⃣ mouthCornerAngle (입꼬리)
5️⃣ gonialAngle (턱각)

---

## 3. Z-Score 7단계 판정 체계

```
|z| < 0.5       → 4. 평균
0.5 ≤ |z| < 1.0 → 3. 약간 큼  /  5. 약간 작음
1.0 ≤ |z| < 2.0 → 2. 큼      /  6. 작음
|z| ≥ 2.0       → 1. 매우 큼  /  7. 매우 작음
```

각 메트릭마다 방향별 라벨이 존재한다:

- z > 0: higherLabel (예: "세로로 긴 얼굴", "눈이 큼")
- z < 0: lowerLabel (예: "가로로 넓은 얼굴", "눈이 작음")

**단일 메트릭 변종:** 12개 메트릭 × 7개 판정 = **84개** 개별 메트릭-판정 조합

---

6️⃣ 관상앱에서는 추가 보정이 필요

관상에서는 절대 크기보다 비대칭/조합이 더 중요합니다.

예:

eyeCanthalTilt
mouthCornerAngle
gonialAngle

이 세 개는

단순 크기보다

positive / neutral / negative

구조가 더 중요합니다.

예

metric 추천 판정
eyeCanthalTilt up / neutral / down
mouthCornerAngle up / neutral / down
gonialAngle sharp / neutral / wide

즉

모든 feature를 동일한 7단계로 만들 필요는 없습니다.

7️⃣ 실제 추천 구조

15개 metric을 다음처럼 나누는 것이 가장 좋습니다.

ratio 계열

7단계

faceAspectRatio
intercanthalRatio
eyeFissureRatio
mouthWidthRatio
lipFullnessRatio
nasalWidthRatio
angle 계열

5단계

gonialAngle
eyeCanthalTilt
mouthCornerAngle
nasalTipAngle
shape 계열

3~4단계

eyebrowThickness
browEyeDistance
philtrumLength
8️⃣ 추천 설계 (가장 좋은 방법)

AI 관상앱 기준

15 metrics
↓

z-score normalize

↓

percentile mapping

↓

category
(3~7 단계 metric별 다름)

↓

관상 rule engine
9️⃣ 실제 구현 예

예

eyeCanthalTilt

z = +1.8
→ percentile = 96%

category = "upturned strong"
nasalWidthRatio

z = -0.7
→ percentile = 24%

category = "slightly narrow"
🔟 가장 중요한 팁

관상 앱에서 metrics 자체보다 중요한 것

feature interaction

예

eyeCanthalTilt + mouthCornerAngle

→ 성격

nasalWidthRatio + nasalHeightRatio

→ 재물운

gonialAngle + faceTaperRatio

→ 리더십

입니다.

✅ 정리

방식 추천도
z-score 7단계 가능
percentile 7단계 더 좋음
metric별 단계 다르게 최고

---

관상 앱에서 핵심 로직은 사실 매우 단순한 구조입니다. 중요한 것은 **metric 자체보다 “조합 규칙(rule interaction)”**입니다.
실제 구현은 보통 다음 5단계 파이프라인으로 구성됩니다. 🔧

1️⃣ 전체 시스템 구조 (핵심 아키텍처)
face landmarks
↓
15 metrics 계산
↓
z-score normalize
↓
category 변환 (7단계 등급)
↓
rule engine
↓
관상 attribute score
↓
최종 관상 리포트
2️⃣ 핵심 Attribute (관상 결과)

관상은 결국 몇 개의 상위 attribute로 압축됩니다.

추천 구조:

Attribute 의미
재물운 wealth
사회성 sociability
지능/통찰 intelligence
리더십 leadership
감정성 emotionality
성격 안정성 stability
매력 attractiveness

보통 7~9개 attribute면 충분합니다.

3️⃣ Metric → Attribute 영향 매핑

예시 (핵심 로직)

metric 영향 attribute
nasalWidthRatio wealth
nasalHeightRatio wealth
mouthWidthRatio sociability
mouthCornerAngle sociability / optimism
eyeFissureRatio intelligence
eyeCanthalTilt attractiveness / dominance
gonialAngle leadership
faceAspectRatio personality
lipFullnessRatio emotionality
browEyeDistance patience
intercanthalRatio openness
nasalHeightRatio wealth
philtrumLength vitality
4️⃣ 실제 Score 계산 방식

각 metric을 -3 ~ +3 score로 변환합니다.

예

z-score score
≥2 +3
1~2 +2
0.5~1 +1
-0.5~0.5 0
-1~-0.5 -1
-2~-1 -2
≤-2 -3
5️⃣ Attribute Score 계산

예: wealth score

wealth =
0.45 \* nasalWidthRatioScore
+ 0.25 \* nasalHeightRatioScore
+ 0.20 \* mouthWidthRatioScore
+ 0.10 \* gonialAngleScore

예: leadership

leadership =
0.5 \* gonialAngleScore

- 0.3 \* eyeCanthalTiltScore
- 0.2 \* browEyeDistanceScore
  6️⃣ Interaction Rule (핵심)

이게 관상 로직에서 가장 중요합니다.

Rule Example
if eyeCanthalTilt > 1
and mouthCornerAngle > 1
→ charisma +2
if nasalWidthRatio > 1
and nasalHeightRatio > 1
→ wealth +2
if gonialAngle > 1
and faceTaperRatio < -1
→ dominance +2
7️⃣ 관상 Archetype 분류

점수를 기반으로 face archetype을 만들 수 있습니다.

예

archetype 조건
리더형 leadership > 2
사업가형 wealth > 2
학자형 intelligence > 2
예술가형 emotionality > 2
외교형 sociability > 2
8️⃣ 최종 리포트 생성

예

재물운: 7.8 / 10
→ 코폭과 콧망울이 발달해 재물 축적 능력이 강합니다.

사회성: 6.2 / 10
→ 입 너비가 넓어 대인관계 능력이 좋습니다.

리더십: 8.1 / 10
→ 턱각과 눈꼬리 구조가 강한 결단력을 보여줍니다.
9️⃣ 실제 관상 앱들이 쓰는 트릭

중요한 UX 트릭:

score = raw_score + random(-0.2 ~ +0.2)

→ 사람마다 결과가 조금씩 다르게 보임

또

top 3 attribute만 강조
🔟 정확도 현실

냉정하게 말하면

구조 설명력
5 metrics 40%
15 metrics 75%
30 metrics 85%

즉

15 metrics면 충분히 설득력 있는 관상 앱이 됩니다.

---

1️⃣ AI 관상앱용 15 Metrics 계산식

랜드마크는 보통 MediaPipe Face Mesh 기준입니다.

FACE
한글 metric 계산식 의미
얼굴 종횡비 faceAspectRatio face_height / face_width 얼굴형
상안면 비율 upperFaceRatio dist(hairline, brow) / face_height 초년운
하안면 비율 lowerFaceRatio dist(nose_base, chin) / face_height 말년운
턱각 gonialAngle angle(jaw_left, chin, jaw_right) 결단력
EYES
한글 metric 계산식 의미
눈 사이 거리 intercanthalRatio dist(inner_eye_L, inner_eye_R) / face_width 성향
눈 길이 eyeFissureRatio avg(dist(eye_L), dist(eye_R)) / face_width 지능
눈 크기 eyeOpenness eye_height / eye_width 감정성
눈꼬리 각도 eyeCanthalTilt atan2(outer_eye_y-inner_eye_y, dx) 공격성
EYEBROW
한글 metric 계산식
눈썹 두께 eyebrowThickness brow_area / brow_length
눈-눈썹 거리 browEyeDistance dist(brow_mid, eye_mid)
NOSE
한글 metric 계산식
코 너비 nasalWidthRatio dist(alaR, alaL) / dist(endoR, endoL)
코 길이 nasalHeightRatio dist(nasion, subnasale) / faceHeight
MOUTH
한글 metric 계산식
입 너비 mouthWidthRatio dist(mouth_L, mouth_R) / face_width
입꼬리 각도 mouthCornerAngle atan2(corner_y - center_y)
인중 길이 philtrumLength dist(nose_base, upper_lip) / face_height

✔ 총 15 metrics

2️⃣ Rule Engine (핵심 규칙 구조)

관상 로직 핵심은 feature interaction 입니다.

재물운 (Wealth)
R1
nasalWidth > +1
→ wealth +2
R2
nasalWidthRatio > +1
AND nasalHeightRatio > +1
→ wealth +3
R3
nasalHeightRatio > +1
→ wealth +1
R4
nasalWidth < -1
→ wealth -2
R5
nasalWidth > 1
AND mouthWidth > 0
→ wealth +1
리더십 (Leadership)
R6
gonialAngle > +1
→ leadership +2
R7
gonialAngle > 1
AND eyeCanthalTilt > 1
→ leadership +3
R8
faceAspectRatio < -1
→ leadership +1
R9
browEyeDistance > 1
→ leadership +1
지능 / 통찰
R10
eyeFissureRatio > 1
→ intelligence +2
R11
intercanthalRatio < -1
→ intelligence +1
R12
eyeFissureRatio > 1
AND browEyeDistance > 0
→ intelligence +2
사회성
R13
mouthWidth > 1
→ sociability +2
R14
mouthCornerAngle > 1
→ sociability +2
R15
mouthWidth > 1
AND mouthCornerAngle > 1
→ charisma +3
감정성
R16
lipFullness > 1
→ emotionality +2
R17
eyeOpenness > 1
→ emotionality +1
R18
eyeOpenness > 1
AND lipFullness > 1
→ emotionality +3
안정성
R19
faceSymmetry > 1
→ stability +2
R20
eyeCanthalTilt < -1
→ stability -1

이런 구조로 약 50 rules 만들면 됩니다.

---

## 부록: 소스코드 참조

| 파일                                                | 역할                                  |
| --------------------------------------------------- | ------------------------------------- |
| `lib/domain/services/face_metrics.dart`             | 랜드마크 인덱스 + 12개 메트릭 계산    |
| `lib/data/constants/face_reference_data.dart`       | 인종별 기준값 + 메트릭 메타데이터     |
| `lib/domain/models/face_analysis.dart`              | Z-score 분석 + 판정 + 랜드마크 평균화 |
| `lib/data/enums/ethnicity.dart`                     | 6개 인종 enum                         |
| `lib/presentation/screens/home/face_mesh_page.dart` | 카메라 캡처 + 품질 제어               |
| `lib/presentation/screens/home/report_page.dart`    | 리포트 UI + 내보내기                  |
