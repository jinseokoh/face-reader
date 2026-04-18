# Face Reader 비즈니스 로직 분석서

**마지막 업데이트**: 2026-04-18

본 문서는 관상 앱의 핵심 비즈니스 로직 — metric 선정 근거, 속성 도출 구조, archetype 분류 — 을 관상학적 맥락에서 설명한다.

---

## 1. 시스템 개요

카메라 또는 앨범에서 정면 + 3/4 측면 두 장의 얼굴을 캡처하면 MediaPipe Face Mesh가 **468개 랜드마크**를 추출하고, **17개 frontal + 8개 lateral metric**을 계산한다. 각 metric은 인종(6)·성별(2) reference (Farkas + MediaPipe 경험적 재보정)와 비교하여 **Z-score**를 산출하고, 14-node 트리 엔진의 5-stage pipeline을 통해 **10개 관상 속성 점수**(5.0~10.0)로 변환한다.

---

## 2. Metric 선정 근거

17개 frontal metric 은 관상학 전통(마의상법·유장상법·신상전편)의 부위별 해석 체계와 현대 craniofacial anthropometry(Farkas 1994, ICD meta-analysis PMC9029890, NIOSH dataset)를 교차 검증하여 선정했다.

### 관상학적 중요도 TOP 5

모든 관상 전통에서 공통으로 중시하는 metric:

| 순위 | Metric | 관상학적 의미 |
|---|---|---|
| 1 | eyeCanthalTilt | 감찰관 — 성격 방향성, 매력, 사회적 태도 |
| 2 | nasalWidthRatio | 재백궁 — 재물운 핵심 |
| 3 | nasalHeightRatio | 재백궁 규모 — 중년운 |
| 4 | mouthCornerAngle | 출납관 — 낙관성, 인간관계 |
| 5 | gonialAngle | 항산 — 의지력, 권위, 리더십 |

### 전체 17 Frontal Metric

| Category | Metric | 관상적 의미 |
|---|---|---|
| face | faceAspectRatio | 얼굴형 기본 구조 (장형/원형/방형) |
| face | faceTaperRatio | V형 vs 사각형, 성격 강도 |
| face | upperFaceRatio | 초년운, 지성, 사고방식 |
| face | midFaceRatio | 중년운, 사회적 활동성 |
| face | lowerFaceRatio | 말년운, 의지력 |
| face | gonialAngle | 의지력, 권위, 리더십 |
| eyes | intercanthalRatio | 사고 범위, 성격 개방성 |
| eyes | eyeFissureRatio | 통찰력, 사회성 |
| eyes | eyeCanthalTilt | 공격성, 매력, 사회적 태도 |
| eyes | eyebrowThickness | 의지력, 성격 강도 |
| eyes | browEyeDistance | 인내심, 사고 깊이 |
| nose | nasalWidthRatio | 재물운 핵심 |
| nose | nasalHeightRatio | 재백궁 규모 |
| mouth | mouthWidthRatio | 사회성, 언변 |
| mouth | mouthCornerAngle | 낙관성, 인간관계 |
| mouth | lipFullnessRatio | 감정 표현, 애정 성향 |
| mouth | philtrumLength | 생명력, 자식운 |

상세 공식은 `flutter/CLAUDE.md` §Frontal Metrics 참조.

---

## 3. 10 Attribute 도출 구조

관상 분석의 최종 산출은 10개 속성 점수(5.0~10.0)이다.

| Attribute | Korean | 핵심 노드 | 관상 근거 |
|---|---|---|---|
| wealth | 재물운 | 코(0.50), 광대(0.20) | 재백궁=코, 관골이 보좌 |
| leadership | 리더십 | 이마(0.40), 광대(0.25), 턱(0.20) | 관록궁=이마, 노복궁=턱 |
| intelligence | 통찰력 | 눈(0.40), 눈썹(0.25), 이마(0.20) | 감찰관=눈, 명궁 경계부 |
| sociability | 사회성 | 광대(0.40), 입(0.25), 턱(0.20) | 관골=”사회성을 보는 대표 부위” |
| emotionality | 감정성 | 눈(0.45), 눈썹(0.20), 입(0.20) | 감찰관 한국 관상학 5할 |
| stability | 안정성 | 턱(0.40), 이마(0.20), 코(0.20) | 항산=한국 관상 최우선 |
| sensuality | 바람기 | 눈(0.40), 입(0.25), 광대(0.20) | 감찰관+처첩궁 |
| trustworthiness | 신뢰성 | 코(0.35), 이마(0.25), 눈썹(0.20) | “코가 바르고 가지런해야 사람” |
| attractiveness | 매력도 | 눈(0.35), root(0.25P), 코(0.15) | “얼굴이 천 냥이면 눈이 구백 냥” |
| libido | 관능도 | 인중(0.40), 눈(0.25), 턱(0.20) | 인중=정력 제1 지표 |

가중치 상세: `docs/engine/ATTRIBUTES.md` §2.2

### 5-Stage Pipeline

```
Stage 1: Base Linear — Node-weight matrix x 10 속성
Stage 1b: Distinctiveness — attractiveness/intelligence/emotionality abs-z 가산
Stage 2: Zone Rules (10개) — 삼정 조화/대립 패턴
Stage 3: Organ Rules (14개) — 오관 쌍 조합
Stage 4: Palace Rules (8개) — 십이궁 cross-node overlay
Stage 5: Gender/Age/Lateral — 성별 weight delta + 50+ 규칙 + 측면 flag
```

구현: `lib/domain/services/attribute_derivation.dart`

---

## 4. Archetype 분류

정규화된 10 속성 중 상위 2개로 primary/secondary archetype 결정.

| Attribute | Archetype Label |
|---|---|
| wealth | 사업가형 |
| leadership | 리더형 |
| intelligence | 학자형 |
| sociability | 외교형 |
| emotionality | 예술가형 |
| stability | 현자형 |
| sensuality | 연예인형 |
| trustworthiness | 신의형 |
| attractiveness | 미인형 |
| libido | 정열형 |

### Special Archetype (10개)

복합 조건 충족 시 부여되는 특수 상:

| ID | Name | 조건 |
|---|---|---|
| SP-1 | 제왕상 | wealth >= 7.5 AND leadership >= 7.0 |
| SP-2 | 도화상 | sensuality >= 7.5 AND attractiveness >= 7.5 |
| SP-3 | 군사상 | intelligence >= 7.5 AND stability >= 7.0 |
| SP-4 | 연예인상 | sociability >= 7.5 AND attractiveness >= 7.0 |
| SP-5 | 복덕상 | wealth >= 7.0 AND trustworthiness >= 7.0 |
| SP-6 | 대인상 | leadership >= 7.0 AND stability >= 7.0 AND trustworthiness >= 7.0 |
| SP-7 | 풍류상 | libido >= 7.5 AND sensuality >= 7.0 |
| SP-8 | 천재상 | intelligence >= 7.0 AND emotionality >= 7.0 |
| SP-9 | 광인상 | stability <= 3.0 AND emotionality >= 7.5 |
| SP-10 | 사기상 | trustworthiness <= 3.0 AND sociability >= 7.0 |

구현: `lib/domain/services/archetype.dart`

---

## 5. 소스코드 참조

| 파일 | 역할 |
|---|---|
| `lib/domain/services/face_metrics.dart` | 랜드마크 인덱스 + 17 frontal metric 계산 |
| `lib/domain/services/face_metrics_lateral.dart` | 8 lateral metric + yaw 분류 |
| `lib/data/constants/face_reference_data.dart` | 6 인종 x 2 성별 reference (mean/SD) |
| `lib/domain/services/physiognomy_scoring.dart` | 14-node tree + scoreTree() |
| `lib/domain/services/attribute_derivation.dart` | 5-stage pipeline + weight matrix |
| `lib/domain/services/attribute_normalize.dart` | Monte Carlo quantile 정규화 |
| `lib/domain/services/archetype.dart` | Archetype 분류 |
| `lib/domain/models/face_analysis.dart` | 전체 파이프라인 오케스트레이션 |
| `lib/domain/services/report_assembler.dart` | 한국어 리포트 텍스트 조립 |

---

## 연관 문서

- [OVERVIEW.md](../architecture/OVERVIEW.md) — 상위 아키텍처 (3 Track 구조)
- [ATTRIBUTES.md](ATTRIBUTES.md) — weight matrix + rule 명세
- [NORMALIZATION.md](NORMALIZATION.md) — raw -> 5~10 정규화
- [COMPATIBILITY.md](COMPATIBILITY.md) — 궁합 엔진
