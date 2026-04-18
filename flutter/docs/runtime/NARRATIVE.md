# 인생 질문 서술 엔진 (Life Question Narrative)

**마지막 업데이트**: 2026-04-18
**상태**: v3 운영 — 성별 분리 pool + 관능도 rename + 400~600자 tight
**SSOT 코드**: `lib/domain/services/life_question_narrative.dart`

---

## 0. 목적

관상 리포트의 본문은 8개 "인생 질문" 섹션으로 구성된다.

1. 타고난 재능
2. 재물운
3. 대인관계
4. 연애운 — **남/여 별도 pool** (`_romanceBeatsMale` / `_romanceBeatsFemale`)
5. 바람기 *(20대 이상)* — **남/여 별도 pool**
6. 관능도 *(30대 이상)* — **남/여 별도 pool**. 구 '색기' 섹션을 attribute.dart labelKo 와 일치시켜 rename.
7. 건강과 수명
8. 종합 조언

v3 변경점 (2026-04-18):
- 연애·바람기·관능도 3 섹션을 **치환이 아닌 별도 BeatPool** 로 분리. 총 6 개 pool.
- 하드코딩된 `@{noble_m}` 제거 → `@{noble}` 로 통일 (`_genderedKey` 가 정상 분기).
- 섹션당 평균 400~600자 타이트화 (v2 의 600 평균에서 축소).
- 관능도 섹션: 오랜 관계의 농밀한 결, 음주·파티 기(氣) 누수, 만족 선까지 지속되는 욕구 — 성별별 상이한 프레임으로 전문가 톤.

단일 얼굴 → 단일 본문이라는 결정론은 유지하면서, **서로 다른 얼굴끼리는 거의 겹치지 않는 prose** 를 뽑아내는 것이 설계 목표. 같은 템플릿을 문장 단위로 바꿔치기하는 수준이 아니라 어휘·관상 용어·인용 궁/악까지 face hash 로 섞이도록 구조화.

---

## 1. 전체 구조

```
FaceReadingReport
       │
       ▼
  _extractFeatures(r)   ─┐
                         │  — top/second/bottom attribute
                         │  — band: high (≥8.0) · mid (6.5~8.0) · low (<6.5)
                         │  — firedRules / nodeOwnZ / nodeAbsZ / strongestNode
                         │  — primary/secondary/specialArchetype
                         │  — seed = face hash (metrics + attributes + nodes)
                         ▼
  _Features
       │
       │   섹션당 4 beat pool (opening·strength·shadow·advice)
       ▼
  _BeatPool = List<_Frag>
       │
       │   _Frag = (predicate, variants[])
       │   predicate 로 valid fragment 선별 → face seed 로 하나 선택
       │   variant 한 개를 face seed 로 선택
       ▼
  _resolveText(variant, features, seed)
       │
       │   Step 0: '@__PRIMARY_ARCHETYPE__' 류 → 런타임 archetype 레이블
       │   Step 1: @{slot}                   → _slotPools 에서 seed 로 선택
       │   Step 2: {a|b|c}                   → 인라인 alternation
       ▼
  최종 문장 (섹션당 평균 600자 내외, 최소 450자)
```

섹션 결과는 `## 섹션명\n본문` 형식으로 join. `report_assembler.dart` 가 archetype intro + special archetype + age closing 을 앞뒤로 감싼다.

---

## 2. Face Hash Seed

`_computeSeed(r)` — FNV 계열 해시로 metrics · attributes · nodeScores 를 섞어 32-bit seed 를 만든다.

```dart
int h = 1469598103;
for (m in metrics)    h = h * 1099511628 + (rawValue*1e6).round();
for (m in metrics)    h = h * 31         + (zScore*1e4).round();
for (a in attributes) h = h * 17         + index;
for (a in attributes) h = h * 13         + (normalized*1000).round();
for (n in nodeScores) h = h * 7          + (ownMeanZ*1e4).round();
for (n in nodeScores) h = h * 11         + (ownMeanAbsZ*1e4).round();
return h & 0x7FFFFFFF;
```

같은 얼굴 → 같은 metric·node → 같은 seed → 같은 서술. 다른 얼굴은 30+ 차원의 실수가 조합되어 사실상 유일한 seed 가 된다.

### 섹션·빗(beat)·슬롯 salting

단일 seed 로 모든 선택을 뽑으면 상관이 생긴다. 실제 선택은 파생 seed 사용:

```dart
beatSeed    = (seed ^ (beatSalt * 2654435761)) & 0x7FFFFFFF
variantSeed = (beatSeed ^ 0x1DEA1BEE) & 0x7FFFFFFF
slotIndex   = (beatSeed + slotKey.hashCode).abs() % pool.length
altIndex    = (beatSeed + altBody.hashCode).abs() % opts.length
```

`beatSalt` 은 섹션(10/20/30/…/80) + beat index 로 유니크. 결과: 섹션간/빗간 독립된 의사난수 stream.

---

## 3. Beat-Fragment 문법

### 3.1 `_Frag`

```dart
class _Frag {
  final bool Function(_Features) applies;
  final List<String> variants;
}
```

- `applies` — 이 fragment 가 현재 feature 에 해당되는지. 마지막 fallback fragment 는 `(_) => true`.
- `variants` — 1~3개의 문장 변종. 내부에 `@{slot}` · `{a|b|c}` · archetype 플레이스홀더 가능.

### 3.2 `_BeatPool`

`List<_Frag>`. 보통 섹션당 4개 pool (opening → strength → shadow → advice).

### 3.3 Helper predicates

| 이름 | 의미 |
|---|---|
| `_highOf(A)` | 해당 attribute band 가 high |
| `_lowOf(A)` | 해당 attribute band 가 low |
| `_highPair(A,B)` | 두 attribute 모두 high |

그 외 직접 람다: `(f) => f.age.isOver50`, `(f) => f.specialArchetype != null`, `(f) => f.fired('P-06')` 등.

### 3.4 배타 predicate (연령)

`_concludeStage` 는 각 연령 band 가 단독으로 매칭되도록 배타 조건 작성:

```dart
(f) => f.age.isOver50                                      // 50+
(f) => f.age.isOver30 && !f.age.isOver50                   // 30~49
(f) => f.age.isOver20 && !f.age.isOver30                   // 20~29
(f) => !f.age.isOver20                                     // 10대
```

beat pool 안에 복수 fragment 가 `valid` 로 들어가면 seed 로 하나 임의 선택되기 때문에, 의도된 단일 결과가 필요한 곳은 위와 같이 배타적으로 적어야 한다.

---

## 4. Slot Pools (어휘 변종 풀)

### 4.1 텍스트 치환 syntax

| 형태 | 예 | 처리 |
|---|---|---|
| `@{slotName}` | `@{palace_destiny}` | `_slotPools[slotName]` 에서 seed 로 1개 선택 |
| `{a\|b\|c}` | `{맥락\|의도\|흐름}` | 파이프 리스트에서 seed 로 1개 선택 |
| `@__PRIMARY_ARCHETYPE__` | — | `features.primaryArchetype` 으로 치환 |
| `@__SECONDARY_ARCHETYPE__` | — | `features.secondaryArchetype` 으로 치환 |
| `@__SPECIAL_ARCHETYPE__` | — | `features.specialArchetype ?? '특별 관상'` |

### 4.2 성별 분기 슬롯

`noble`, `person` 등 성별마다 어휘가 달라야 하는 슬롯은 `_m` / `_f` 접미사 쌍으로 두고, 호출 시 `_genderedKey()` 가 features.gender 기반으로 resolved:

```dart
'noble_g': [],                                 // 마커
'noble_m': ['대장부(大丈夫)의', '장부의', '지장(智將)의', …],
'noble_f': ['여중군자(女中君子)의', '단아한', '기품 있는', …],
```

변종은 fragment 안에서 `@{noble}` 로 쓴다 — `_g` 존재를 보고 `_m`/`_f` 자동 선택.

### 4.3 슬롯 카테고리 (현 구현 45개)

| 카테고리 | 슬롯 예 | 용도 |
|---|---|---|
| 수식 정도 | `intense` · `faint` · `deep` · `subtle` | 기운의 강도 |
| 인물 수식 | `noble_m/f` · `person_m/f` · `rare` · `gentle` · `strong_adj` | 주어·관형어 |
| 관상 동사 | `observe` · `act` | "읽어내는" · "밀어붙이는" 류 |
| 공간 수식 | `open_wide` · `clear_adj` | 명궁·인당 묘사 |
| 십이궁 | `palace_career/wealth/destiny/social/servant/mate/sex/home/health/bro` | 관록궁·재백궁·명궁·… |
| 오악 | `mount_n/s/c/e/w` | 항산·형산·숭산·태산·화산 |
| 오관 | `organ_brow/eye/nose/mouth` | 보수관·감찰관·심변관·출납관 |
| 삼정 | `zone_up/mid/down` | 상정·중정·하정 |
| 기·상 | `energy_yang/yin` · `peach` · `structure` · `heart` | 양기·음기·도화·골상·마음 |
| 사자성어 | `talent_word` · `fate_word` · `path_word` · `fortune_word` | 재능·명·길·복록 |
| 결과 동사 | `result_shine` · `result_carry` | "빛납니다"·"서려 있습니다" |

각 슬롯마다 3~6개 변종. 같은 비트 안에서 슬롯 여러 개가 곱해지면 조합이 쉽게 수십만 단위로 팽창한다.

---

## 5. 섹션 구성

각 섹션은 4 beat (일부 섹션 3 beat) 로 `opening → strength → shadow → advice` 흐름. 각 pool 은 3~11 fragment, 각 fragment 는 1~3 variant.

| # | 섹션 | beatSalt | 특징 |
|---|---|---|---|
| 1 | 타고난 재능 | 10 | top attribute 조합별 opening + 4가지 강점 유형 + 위험 + 조언 |
| 2 | 재물운 | 20 | 재백궁 중심. wealth high/low + leadership high + stability high 등 |
| 3 | 대인관계 | 30 | 천이궁·노복궁 · sociability/emotionality band 에 따른 관계 스타일 |
| 4 | 연애운 | 40 | **새 이성과의 만남** MECE. 매력도·사회성 중심, "몸이 반응" 표현 금지 |
| 5 | 바람기 | 50 (age≥20) | **기존 관계 중 외도 경향**. 자제력·호기심·집중도 프레임 |
| 6 | 색기 | 60 (age≥30) | **정적 오라(aura)**. 행위와 독립된 분위기·음기 프레임 |
| 7 | 건강과 수명 | 70 | 질액궁 · lowerFace · chin · 인중 기반 |
| 8 | 종합 조언 | 80 | archetype 레이블 런타임 치환 + 연령 stage 배타 분기 + 공통 조언 |

### MECE 구분 (연애 / 바람기 / 색기)

v1 에서 세 섹션이 모두 "몸이 먼저 반응한다" 류 표현을 반복한다는 피드백으로 어휘가 섞이지 않도록 분리:

- **연애운** = **만남·구애의 역학**. 새 이성에게 어떻게 매력이 투영되는가.
- **바람기** = **관계 진행중 외도 잠재력**. 자제력·호기심·주의 분산.
- **색기** = **정적 오라**. 행위와 무관한 분위기·기운.

---

## 6. 연령 게이팅

`assembleLifeQuestions` 에서 섹션 포함 여부 결정:

```dart
if (f.age.isOver20) parts.add('바람기', …);
if (f.age.isOver30) parts.add('색기', …);
```

결과:

| 연령 | 섹션 수 | 포함 섹션 |
|---|---|---|
| 10대 | 6 | 재능·재물·대인·연애·건강·조언 |
| 20대 | 7 | + 바람기 |
| 30대+ | 8 | + 바람기 + 색기 |

50+ 는 섹션 수는 동일하지만 "종합 조언" 의 stage beat 가 `덜어내는 기술` 으로 분기 — 테스트가 명시 keyword 를 검증.

---

## 7. 품질 가드

`test/life_question_narrative_test.dart` 4 fixture:

| 케이스 | 검증 |
|---|---|
| 30대 남성 | 섹션 수 == 8, 각 섹션 ≥ 450자 (목표 평균 ~600자) |
| 20대 여성 | 섹션 수 == 7, `## 바람기` 포함, `## 색기` 미포함 |
| 10대 남성 | 섹션 수 == 6, 바람기·색기 둘 다 미포함 |
| 50대 여성 | 섹션 수 == 8, 종합 조언에 `덜어내는` 키워드 포함 |

fixture z-vector 는 "재물·권력 중정 강세" (evidence_snapshot_test 와 동일). 얇은 smoke test — 실제 서술 품질은 수동 리뷰.

---

## 8. report_assembler 와의 관계

```dart
AssembledReport assembleReport(FaceReadingReport report) {
  buf.write(_archetypeIntro(report));           // data/constants/archetype_text_blocks.dart
  buf.write(assembleLifeQuestions(report));     // 이 엔진
  buf.write(specialArchetypeTexts[special]);    // 옵션
  buf.write(ageClosings[isOver50]);             // data/constants/archetype_text_blocks.dart
  ...
}
```

archetype intro / special / age closing 은 여전히 정적 텍스트 블록. "본문" 에 해당하는 8 섹션만 이 엔진이 생성한다.

---

## 9. 확장 가이드

### 9.1 슬롯 추가

1. `_slotPools` 에 `'mySlot': [...]` 엔트리 추가 (3+ 변종 권장).
2. 성별 분기 필요하면 `mySlot_g: []` + `mySlot_m: [...]` + `mySlot_f: [...]`.
3. fragment 안에서 `@{mySlot}` 로 사용.

### 9.2 beat 추가

1. `_<section><Stage>` const `List<_Frag>` 선언.
2. `_<section>Beats` 리스트에 순서대로 포함.
3. 마지막 fragment 는 반드시 `(_) => true` fallback (seed 가 valid 리스트를 빈 리스트로 만들지 않도록).

### 9.3 fragment predicate 설계

- **비배타 pool**: 순수 변종용 — 여러 조건이 겹쳐도 무작위 선택 OK.
- **배타 pool** (연령·archetype 상태 등 분기): `!other` 조건 명시.
- 항상 마지막 fallback fragment 로 valid 비어 있는 경우 방지.

### 9.4 변종 팽창 테크닉

- `@{slot}` vs `{a|b|c}` 혼용 — 전자는 재사용, 후자는 로컬 일회용.
- 한 variant 에 3~5 개 슬롯 채우면 조합이 슬롯 크기의 곱으로 폭발.
- archetype placeholder 는 소수 섹션(종합 조언)에만 — 과다 사용 시 반복 탐지 쉬워짐.

---

## 10. 파일

```
lib/domain/services/life_question_narrative.dart     # 엔진 (이 문서)
lib/domain/services/report_assembler.dart            # 조립 래퍼
lib/data/constants/archetype_text_blocks.dart        # intro / special / closing 정적 텍스트
test/life_question_narrative_test.dart               # smoke test
```

---

## 연관 문서

- [OUTPUT_SAMPLES.md](OUTPUT_SAMPLES.md) — 엔진이 받는 FaceReadingReport 스키마
- [../engine/ATTRIBUTES.md](../engine/ATTRIBUTES.md) — 10 attribute 정의
- [../engine/TAXONOMY.md](../engine/TAXONOMY.md) — 14 node tree (궁·악·관 메타)
