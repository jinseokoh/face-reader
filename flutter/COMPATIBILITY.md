# 궁합 엔진 현황 및 개선 요청

## 목적
이 문서는 현재 궁합(Compatibility) 엔진의 구조와 로직을 설명하여, ChatGPT에게 질적 개선을 요청하기 위한 레퍼런스입니다.

---

## 0. 핵심 문제 진단

> **관상 엔진은 "설계 철학이 있는 해석 시스템"인데, 궁합 엔진은 "점수 합산기" 수준이다.**

궁합은 "두 사람의 리포트가 서로 어떻게 부딪히는지"를 설명해야지, 점수만 평균 내면 안 된다.
관상 엔진처럼 **"triggered rule + archetype + special + gender + attribute" 모든 레이어를 교차 해석**해야 한다.

---

## 1. 관상 엔진 (비교 기준: 높은 품질)

관상 분석 엔진은 아래와 같은 다층적 구조를 가집니다:

### 입력
- MediaPipe Face Mesh 468개 랜드마크에서 산출된 **17개 facial metrics** (Z-score 기반)

### 평가 파이프라인
1. **Base Weight Matrix**: 10개 attribute별로 4~6개 metric에 가중치 부여 (총 50+ weight 매핑)
2. **Gender Weight Deltas**: 남/여별로 특정 metric의 가중치 미세 조정 (+/-0.05)
3. **50개 Interaction Rules**: metric Z-score 조합 조건 → attribute 보너스/페널티
   - Common Rules 40개 (전체 적용)
   - Gender Rules 10개 (성별별 5개)
   - Age Rules 5개 (50세+ 전용)
4. **Sigmoid 정규화**: raw score → 0~10 scale
5. **Archetype 분류**: 상위 2개 attribute → primary/secondary archetype + 10개 special archetype 조건 검사
6. **Report Assembly**: triggered rule ID → 한국어 텍스트 블록 매핑 (55개 rule별 상세 해설)
   - Archetype별 성별 맞춤 소개문 (10 archetype × 2 gender = 20개)
   - Special archetype별 고유 해설 (10개)
   - 나이대별 클로징 (2개)

### 결과 품질
- 개인화된 상세 해석: 동일 archetype이라도 triggered rules 조합에 따라 완전히 다른 리포트
- 장점/단점 균형 있는 피드백
- 성별·나이·인종 3축 보정

---

## 2. 궁합 엔진 (현재: 개선 필요)

### 구조 개요

```
evaluateCompatibility(myReport, albumReport) → CompatibilityResult
```

### Step 1: Attribute Harmony (가중치 40%)

10개 attribute 각각에 대해 두 사람의 점수(0~10)를 비교:

| 패턴 | 조건 | 점수 산출 |
|------|------|----------|
| synergy | 둘 다 ≥ 7.0 | 하드코딩된 attribute별 고정값 (40~90) |
| complement | 한쪽 ≥ 7.0, 다른쪽 ≤ 3.0 | `60 + 20 * (1 - min/max)` |
| clash | 차이 ≥ 5.0 또는 둘 다 ≤ 3.0 | `20 + 20 * (1 - diff/10)` |
| neutral | 둘 다 4.0~6.0 | `50 + 10 * (1 - diff/2)` |
| mixed | 그 외 | `max(20, 80 - diff*8)` |

**Synergy 고정값:**
```
wealth: 70, leadership: 40, intelligence: 75, sociability: 80,
emotionality: 55, stability: 85, sensuality: 75, trustworthiness: 90,
attractiveness: 70, libido: 65
```

**문제점:**
- 패턴 분류가 단순한 threshold 기반 (7.0/3.0/5.0)
- synergy 점수가 하드코딩된 고정값 (맥락 무시)
- complement 점수 공식이 단조로움 (어떤 attribute끼리 보완하는지 고려 안함)
- **두 사람의 성별 조합을 전혀 고려하지 않음** (남-여, 남-남, 여-여에 따라 궁합 해석이 달라야 함)
- secondary archetype, triggered rules 기반 미세 보정 없음

### Step 2: Archetype Compatibility Matrix (가중치 30%)

10×10 정수 매트릭스로 하드코딩:

```
         wea  lea  int  soc  emo  sta  sen  tru  att  lib
wea      50   65   80   60   45   75   55   70   55   50
lea      65   35   85   60   50   75   50   70   55   45
int      80   85   60   65   75   80   55   70   60   50
soc      60   60   65   55   65   70   65   80   65   55
emo      45   50   75   65   55   60   70   60   65   60
sta      75   75   80   70   60   70   55   80   60   50
sen      55   50   55   65   70   55   65   55   70   70
tru      70   70   70   80   60   80   55   65   60   50
att      55   55   60   65   65   60   70   60   55   70
lib      50   45   50   55   60   50   70   50   70   45
```

**문제점:**
- Primary archetype만 비교 (secondary 무시)
- 단일 점수만 산출 (왜 그 점수인지 설명 없음)
- 성별 조합에 따른 매트릭스 분화 없음

### Step 3: Special Archetype Interaction (가중치 15%)

switch-case로 10개 special archetype별 고정 delta:

| Special | 기본 delta | 특수 조건 |
|---------|-----------|----------|
| 제왕상 | +15 | 상대도 제왕상/광인상이면 -10 |
| 복덕상 | +20 | 없음 (항상 긍정) |
| 도화상 | +5 | 없음 |
| 군사상 | +5 / +15 | 상대가 리더/사업가면 +15 |
| 연예인상 | +10 | 없음 |
| 대인상 | +15 | 없음 |
| 풍류상 | +5 / -10 | 상대가 안정/신뢰면 -10 |
| 천재상 | +5 / +10 | 상대가 학자면 +10 |
| 광인상 | -15 | 없음 |
| 사기상 | -25 | 없음 |

**문제점:**
- 대부분 고정 delta (맥락 무시)
- 두 special archetype 간 조합 규칙이 빈약 (제왕+광인 정도만)
- 해설 텍스트가 1줄 템플릿

### Step 4: Triggered Rules Cross-analysis (가중치 15%)

```
base = 50
+ 5 per 보완 (내 positive rule이 상대 약점 attribute 보완)
- 5 per 공유 약점 (둘 다 negative rule on same attribute)
clamp(20, 80)
```

**문제점:**
- 규칙이 너무 단순 (positive/negative 여부만 확인)
- 어떤 rule ID끼리 시너지/충돌하는지 전혀 고려 안함
- 50개 rule의 풍부한 조합 가능성을 활용하지 못함

### Step 5: 종합 점수
```
total = attributeAvg * 0.40 + archetypeScore * 0.30 + specialScore * 0.15 + ruleScore * 0.15
```

### Step 6: Summary Text Generation

**현재 구조:**
1. "{myLabel}과(와) {albumLabel}의 만남" 제목
2. archetypeCompatTexts에서 조합 텍스트 조회
3. categoryScores 상위 3개 → "강점" 섹션
4. categoryScores 하위 2개 → "주의할 점" 섹션
5. specialNote 있으면 추가

**문제점:**
- attributeCompatTexts에 풍부한 텍스트(40개 블록)가 있으나 summary에 포함되지 않음
- "강점/주의할 점"이 점수 + 라벨만 나열 (해설 없음)
- 성별 조합에 맞춘 어조/내용 없음
- 관상 리포트 대비 텍스트 밀도가 현저히 낮음

---

## 3. 텍스트 블록 현황

### attributeCompatTexts (40 블록)
10개 attribute × 4개 패턴 (synergy/complement/clash/neutral), 각 title + body.
품질은 양호하나 **엔진이 summary에 활용하지 않고 있음**.

### archetypeCompatTexts (100 블록)
10×10 archetype 조합별 2~3문장 텍스트.
**단일 key 조회만 수행**, 성별 분화 없음.

### specialArchetypeInteractionTexts (20 블록)
10개 special × positive/warning.
**엔진이 이 텍스트를 전혀 사용하지 않음** (switch-case에서 자체 생성한 1줄 텍스트만 사용).

---

## 4. 관상 엔진 대비 궁합 엔진의 핵심 격차

| 영역 | 관상 엔진 | 궁합 엔진 |
|------|----------|----------|
| Rule 개수 | 50개 interaction rules | 5개 패턴 분류 |
| 성별 반영 | 3단계 (weight delta, gender rules, archetype intro) | 없음 |
| 텍스트 활용 | 55개 rule text + 20개 archetype intro + 10개 special text | summary에 거의 미활용 |
| 개인화 | triggered rules 조합에 따라 완전히 다른 리포트 | 패턴 분류 + 고정 매트릭스 |
| 근거 제시 | metric Z-score → rule trigger → 해설 체인 | threshold 기반 분류만 |
| Secondary 활용 | secondary archetype 라벨 제공 | 무시 |
| Special 처리 | 10개 special별 고유 해설문 | 1줄 템플릿 |

---

## 5. 개선 요청 사항

궁합 엔진을 관상 엔진 수준으로 끌어올리기 위해 아래 영역의 개선안을 요청합니다:

### 5.1 Attribute Harmony 고도화
- 성별 조합(남-여, 남-남, 여-여)에 따른 차별화된 해석 규칙
- 단순 threshold가 아닌, attribute 간 상호작용 규칙 (예: 한쪽 leadership 높고 다른쪽 stability 높으면 시너지)
- Cross-attribute synergy/clash 규칙 추가

### 5.2 Archetype 매트릭스 고도화
- Secondary archetype 반영
- 성별 조합에 따른 매트릭스 분화
- 점수 뿐 아니라 해석 근거 제공

### 5.3 Special Archetype Interaction 강화
- 10×10 special 조합 규칙 (현재는 단일 special만 처리)
- specialArchetypeInteractionTexts 활용
- 상세 해설 생성

### 5.4 Triggered Rules 교차 분석 강화
- Rule ID 수준의 시너지/충돌 매핑
- 두 사람의 triggered rules 조합에서 의미 있는 패턴 추출
- 관상 rule_text_blocks의 풍부한 해설 활용

### 5.5 Summary 텍스트 품질
- attributeCompatTexts의 title/body를 summary에 통합
- 관상 리포트 수준의 텍스트 밀도 (현재 대비 3~5배)
- 성별 맞춤 어조
- 장점과 단점의 균형 잡힌 서술

### 5.6 기타
- 가중치 비율 재검토 (현재 40/30/15/15)
- 점수 산출 공식의 비선형성 도입 (극단적 케이스에서 선형 보간의 한계)

---

## 6. 참고: 사용 가능한 데이터

궁합 엔진이 접근 가능한 두 사람의 FaceReadingReport 필드:

```dart
// 각 사람별
Map<Attribute, double> attributeScores     // 10개 attribute, 0~10 scale
Map<String, MetricResult> metrics          // 17개 facial metrics (rawValue, zScore, zAdjusted, metricScore)
ArchetypeResult archetype                  // primary, secondary, primaryLabel, secondaryLabel, specialArchetype
List<TriggeredRule> triggeredRules          // 발동된 rule ID + effects
Ethnicity ethnicity                         // 6개 인종
Gender gender                              // male/female
AgeGroup ageGroup                          // 연령대
```

## 7. 참고: 10개 Attribute의 한국어 라벨

| Attribute | Korean | 설명 |
|-----------|--------|------|
| wealth | 재물운 | 사업적 감각, 재물 축적 |
| leadership | 리더십 | 주도력, 통솔력 |
| intelligence | 통찰력 | 지적 능력, 분석력 |
| sociability | 사회성 | 소통 능력, 외교력 |
| emotionality | 감정성 | 감수성, 정서적 깊이 |
| stability | 안정성 | 침착함, 인내력 |
| sensuality | 바람기 | 매혹력, 유혹 성향 |
| trustworthiness | 신뢰성 | 성실함, 약속 이행 |
| attractiveness | 매력도 | 외적 끌림, 인상 |
| libido | 관능도 | 정력, 성적 에너지 |

## 8. 참고: 10개 Archetype과 10개 Special Archetype

### Primary Archetype (10개)
| Attribute | Label | 설명 |
|-----------|-------|------|
| wealth | 사업가형 | Entrepreneur |
| leadership | 리더형 | Leader |
| intelligence | 학자형 | Scholar |
| sociability | 외교형 | Diplomat |
| emotionality | 예술가형 | Artist |
| stability | 현자형 | Sage |
| sensuality | 연예인형 | Celebrity |
| trustworthiness | 신의형 | Integrity |
| attractiveness | 미인형 | Beauty |
| libido | 정열형 | Passionate |

### Special Archetype (10개)
| ID | Name | 조건 |
|----|------|------|
| SP-1 | 제왕상 (帝王相) | wealth ≥ 7.5 AND leadership ≥ 7.0 |
| SP-2 | 도화상 (桃花相) | sensuality ≥ 7.5 AND attractiveness ≥ 7.5 |
| SP-3 | 군사상 (軍師相) | intelligence ≥ 7.5 AND stability ≥ 7.0 |
| SP-4 | 연예인상 (演藝人相) | sociability ≥ 7.5 AND attractiveness ≥ 7.0 |
| SP-5 | 복덕상 (福德相) | wealth ≥ 7.0 AND trustworthiness ≥ 7.0 |
| SP-6 | 대인상 (大人相) | leadership ≥ 7.0 AND stability ≥ 7.0 AND trustworthiness ≥ 7.0 |
| SP-7 | 풍류상 (風流相) | libido ≥ 7.5 AND sensuality ≥ 7.0 |
| SP-8 | 천재상 (天才相) | intelligence ≥ 7.0 AND emotionality ≥ 7.0 |
| SP-9 | 광인상 (狂人相) | stability ≤ 3.0 AND emotionality ≥ 7.5 |
| SP-10 | 사기상 (詐欺相) | trustworthiness ≤ 3.0 AND sociability ≥ 7.0 |

---

## 9. 개선 전략 (설계 구조 → 구체 규칙 → 프롬프트)

### 9.1 Attribute Harmony 고도화 (40% 영역)

현재는 threshold만 본다. **"상호작용 기반"**으로 바꿔야 한다.

#### ① Cross-attribute 시너지 규칙 추가 (핵심)

단일 attribute 비교가 아닌, **서로 다른 attribute가 만드는 궁합**:

| A의 강점 | B의 강점 | 해석 |
|----------|----------|------|
| leadership 높음 | stability 높음 | 리더-보좌 궁합 (++) |
| emotionality 높음 | trustworthiness 높음 | 감정 안정 조합 (+) |
| sensuality 높음 | emotionality 낮음 | 감정 온도차 (-) |
| intelligence 높음 | emotionality 높음 | 깊은 대화 가능 (++) |
| sociability 높음 | trustworthiness 높음 | 사회적 안정 (++) |
| libido 높음 | emotionality 높음 | 강한 끌림 (++) |

#### ② 성별 조합 반영 (필수)

같은 점수라도 해석이 달라져야 한다:

| 조합 | 예시 | 해석 차이 |
|------|------|----------|
| 남(leadership) + 여(stability) | 전통적 역할 분담 해석 |
| 여(leadership) + 남(stability) | 균형형 리더십 해석 |
| 남(sensuality) + 여(trustworthiness) | 매력 vs 안정 긴장 |
| 여(sensuality) + 남(trustworthiness) | 다른 뉘앙스의 긴장 |

**점수는 같아도 해석이 다르다.**

### 9.2 Archetype 매트릭스 강화 (30%)

현재는 primary만 사용. 확장 필요:

- primary vs primary (기존 유지)
- **primary vs secondary** (추가)
- **secondary vs secondary** (추가)

그리고 **"점수만" 말하지 말고 "왜 그런 점수가 나왔는지"를 설명**해야 한다.

### 9.3 Special Archetype 조합 강화 (15%)

현재는 단일 special만 본다. **SP × SP 조합 규칙 추가:**

| A Special | B Special | 결과 | 해석 |
|-----------|-----------|------|------|
| 제왕상 | 군사상 | ++ | 전략 + 실행 조합 |
| 제왕상 | 광인상 | -- | 극단 충돌 |
| 도화상 | 신의형 | + | 매력 + 안정 |
| 풍류상 | 현자형 | - | 가치관 차이 |
| 천재상 | 대인상 | ++ | 이상 + 현실 |

이걸 텍스트로 풀어줘야 리포트가 살아난다.

### 9.4 Triggered Rules 교차 분석 (15%)

현재 +5/-5만 준다. **Rule Pairing**으로 개선:

**보완 예시:**
- A의 rule: "충동성 높음" + B의 rule: "인내력 높음" → 상호 보완
- A의 rule: "분석력 높음" + B의 rule: "감성 높음" → 깊은 대화 가능

**충돌 예시:**
- A의 rule: "의심 많음" + B의 rule: "감정 기복 심함" → 충돌
- A의 rule: "주도권 강함" + B의 rule: "주도권 강함" → 경쟁

이걸 설명으로 풀어야 한다.

### 9.5 Summary 구조 개편 (가장 중요)

현재 점수 나열 수준 → 아래 구조로 개편:

```
1) 총평 — 이 관계의 전반적 성격
2) 강점 (3개) — attribute 기반 + 실제 설명
3) 주의점 (2개) — 충돌 포인트
4) 감정·생활 궁합 — 일상에서 생길 일
5) 장기 관계 전망 — 인연 흐름
6) 조언 — 구체적 행동 조언
```

### 9.6 가중치 재조정 제안

현재 40/30/15/15 → 해석 다양성을 위해:

```
attribute 35% / archetype 25% / special 20% / rule 20%
```

---

## 10. Rule Pair 매트릭스 설계 (구체 예시)

### 설계 원칙

한 사람의 rule과 다른 사람의 rule이 만나면:
- **Synergy (+)**: 서로 보완·안정
- **Amplify (++)**: 강점이 더 강해짐
- **Clash (-)**: 갈등 가능성
- **Volatile (--)**: 관계 불안정

### Core Pair Matrix

#### ① 안정성 × 감정성

| A 안정성 | B 감정성 | 결과 | 해석 |
|----------|----------|------|------|
| 높음 | 높음 | + | 감정 안정, 위로 가능 |
| 높음 | 낮음 | + | 침착함이 관계 유지 |
| 낮음 | 높음 | - | 감정 기복 증폭 |
| 낮음 | 낮음 | -- | 무관심·단절 위험 |

#### ② 리더십 × 안정성

| A 리더십 | B 안정성 | 결과 | 해석 |
|----------|----------|------|------|
| 높음 | 높음 | ++ | 리더-보좌 구조 |
| 높음 | 낮음 | - | 충돌 가능 |
| 낮음 | 높음 | + | 균형형 |
| 낮음 | 낮음 | - | 방향성 부족 |

#### ③ 통찰력 × 감정성

| A 통찰력 | B 감정성 | 결과 | 해석 |
|----------|----------|------|------|
| 높음 | 높음 | ++ | 깊은 대화 가능 |
| 높음 | 낮음 | + | 이성적 조율 |
| 낮음 | 높음 | - | 감정 과잉 |
| 낮음 | 낮음 | -- | 소통 단절 |

#### ④ 사회성 × 신뢰성

| A 사회성 | B 신뢰성 | 결과 | 해석 |
|----------|----------|------|------|
| 높음 | 높음 | ++ | 사회적 안정 |
| 높음 | 낮음 | - | 겉과 속 불일치 |
| 낮음 | 높음 | + | 신뢰 기반 관계 |
| 낮음 | 낮음 | -- | 고립 가능 |

#### ⑤ 관능도 × 감정성

| A 관능도 | B 감정성 | 결과 | 해석 |
|----------|----------|------|------|
| 높음 | 높음 | ++ | 강한 끌림 |
| 높음 | 낮음 | - | 감정 불균형 |
| 낮음 | 높음 | + | 안정적 애정 |
| 낮음 | 낮음 | - | 애정 약함 |

### Rule Pair 코드 구조 예시

```json
{
  "A": "high_leadership",
  "B": "high_stability",
  "effect": "synergy",
  "weight": 1.2,
  "comment": "주도성과 안정성이 결합되어 현실적 시너지가 발생"
}
```

**30~50개만 만들어도 리포트 퀄리티가 확 올라간다.**

---

## 11. ChatGPT에게 바로 쓸 수 있는 프롬프트

```
두 사람의 관상 분석 결과를 바탕으로 궁합을 해석하라.

입력으로 다음 정보를 받는다:
- 두 사람의 attribute 점수 (0~10, 10개 항목)
- primary/secondary archetype
- special archetype (있는 경우)
- triggered rules 목록
- 성별

아래 관점으로 반드시 모두 분석하라:

1. 성격·기질 궁합
   - attribute 조합 기반으로 설명

2. 생활·현실 궁합
   - 돈, 책임감, 생활 패턴 중심

3. 감정·애정 궁합
   - 감정 표현, 안정성, 애정 방식

4. 장기 인연 가능성
   - 안정성, 신뢰, 지속성 기반

5. 갈등 가능성과 조정 포인트
   - 충돌 가능 지점과 완화 방법

6. 특수 조합 해석
   - archetype 및 special archetype 조합 설명

규칙:
- 점수 나열 금지
- 반드시 서술형
- 장점과 단점 모두 언급
- 현실적인 조언 포함
```

---

## 12. 결론

> 지금 궁합 엔진은 **"계산기"** 수준이고, 관상 엔진처럼 **"해석 엔진"**으로 바꿔야 한다.
> 구조는 이미 충분하다. **문제는 교차 해석과 텍스트 활용이다.**

현실적 적용 방법:
- attribute 기반 cross-pair 규칙 **30개**
- special archetype pair **10~15개**
- weight는 +1/+2/-1/-2 단순화
- triggered rule 기반 보정
- **이 정도만 해도 관상 엔진급 디테일이 나온다.**
