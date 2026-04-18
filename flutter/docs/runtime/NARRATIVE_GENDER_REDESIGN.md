# 서술 엔진 성별 분기 전면 재설계 (Work Plan)

**작성**: 2026-04-18
**상태**: ✅ **완료** (engine v3, 2026-04-18). 연애·바람기·관능도 남/여 분리 pool, 섹션 400~600자, '색기'→'관능도' 통일.
**대상 파일**: `lib/domain/services/life_question_narrative.dart`
**관련 문서**: [NARRATIVE.md](NARRATIVE.md) — v2 엔진 설계 (v3 에서 섹션 분리 추가)

---

## 0. 배경 — 왜 재설계해야 하는가

### 0.1 현 상태 진단

파이프라인(점수) 레벨은 성별로 분기:
- `attribute_derivation._genderDelta` — 10 attribute 가중치 행렬
- `attribute_normalize` — 성별별 21-point quantile
- `archetype_text_blocks.archetypeIntros` — archetype intro 성별 분기
- `age_adjustment` — 50+ 보정

**그런데 서술 엔진(life_question_narrative.dart v2) 은 분기가 거의 없다.**

| 항목 | 현재 |
|---|---|
| 성별 슬롯 쌍 | **2쌍만** (`noble_m/f`, `person_m/f`) |
| 8 섹션 fragment | **전부 성별 공통 단일 pool** |
| 연애/바람기/색기 | 전통적으로 남녀 해석이 가장 크게 갈리는 영역인데 **성별 분기 fragment 없음** |

### 0.2 버그 (P0)

`_genderedKey()` 는 `@{noble}` (접미사 없이) 호출했을 때만 gender 분기하도록 설계됨:

```dart
String _genderedKey(String key, _Features f) {
  if (_slotPools.containsKey('${key}_g')) {
    return f.isMale ? '${key}_m' : '${key}_f';
  }
  return key;
}
```

그런데 실제 fragment 들은 `@{noble_m}` 를 **하드코딩**:

```dart
// life_question_narrative.dart 예시 라인
'@{noble_m} 지략과 통솔이 겹쳐 흐르는 상입니다...'
// → key = 'noble_m' 으로 들어감
// → _slotPools['noble_m_g'] 존재 안 함 → key 그대로 반환
// → 여성 독자에게도 'noble_m' pool (대장부/장부/사내) 사용
```

**결과**: 여성이 intelligence/leadership high 일 때 "장부", "대장부", "사내" 같은 어휘를 받는다. 확실한 버그.

하드코딩된 위치 (2026-04-18 기준):

```
lib/domain/services/life_question_narrative.dart:
  292, 306, 325, 330, 340, 353, 376  — @{noble_m} 하드코딩
```

---

## 1. 목표

1. **P0 버그 제거**: fragment 에 하드코딩된 `@{noble_m}`/`@{person_m}` 모두 `@{noble}`/`@{person}` 으로 교체, `_genderedKey` 가 정상 작동하도록.
2. **성별 분기 섹션 신설**: 연애·바람기·색기 3 섹션은 남/여가 거의 완전히 다른 서술.
3. **성별 슬롯 풀 확장**: 도화·기·오라·결 등 성별로 어휘가 갈리는 슬롯 쌍 추가.
4. **테스트 보강**: 동일 fixture 로 남/여 본문이 **80% 이상 다른 텍스트** 임을 검증.

---

## 2. 단계별 계획

### Phase 1 — P0 버그 픽스 (30분 작업)

> 즉시 머지 가능. 재설계와 독립.

**변경**:
```diff
- '@{noble_m} 지략과 통솔이 겹쳐 흐르는 상입니다...'
+ '@{noble} 지략과 통솔이 겹쳐 흐르는 상입니다...'
```

**방법**:
1. `Grep "@\{noble_m\}|@\{person_m\}|@\{noble_f\}|@\{person_f\}"` 로 모든 위치 감사
2. 전부 `_m`/`_f` 접미 제거 → `@{noble}`, `@{person}` 로 통일
3. `_genderedKey` 가 `_slotPools['noble_g']` marker 를 보고 자동 분기

**테스트**:
```dart
test('여성 fixture 에 대장부/장부 어휘 미포함', () {
  final r = _buildReport(gender: Gender.female, age: AgeGroup.thirties);
  final full = assembleLifeQuestions(r);
  for (final w in ['대장부', '장부', '사내', '지장']) {
    expect(full.contains(w), isFalse, reason: '여성 리포트에 남성 어휘: $w');
  }
});
test('남성 fixture 에 여중군자/규수/안주인 어휘 미포함', () {
  final r = _buildReport(gender: Gender.male, age: AgeGroup.thirties);
  final full = assembleLifeQuestions(r);
  for (final w in ['여중군자', '규수', '안주인']) {
    expect(full.contains(w), isFalse, reason: '남성 리포트에 여성 어휘: $w');
  }
});
```

---

### Phase 2 — 성별 슬롯 풀 확장 (2~3시간 작업)

관상학 전통에서 남녀 어휘가 다른 영역을 슬롯 쌍으로 체계화.

#### 2.1 신규 슬롯 쌍 목록

| 슬롯 | 남 (`_m`) | 여 (`_f`) | 용도 |
|---|---|---|---|
| `peach` | 도화기(桃花氣), 풍류의 결, 한량의 정취 | 도화(桃花), 홍도화, 복숭아꽃 기색, 요색(妖色) | 색기 섹션 주축 |
| `aura` | 위엄(威嚴), 호연지기(浩然之氣), 기백(氣魄), 호방한 기운 | 요염(妖艶), 유한한(幽閑) 결, 단아한 기운, 수기(水氣)의 정취 | 오라 묘사 |
| `romance_role` | 구애하는 쪽, 다가서는 역할, 먼저 움직이는 자리 | 선택받는 쪽, 불러오는 자리, 지켜보고 응하는 역할 | 연애 시작 구도 |
| `relation_stance` | 뿌리내리는 장부, 한 자리를 지키는 사내 | 품는 여인, 정을 두터이 하는 안사람 | 관계 지속 서술 |
| `infidelity_risk` | 바깥으로 뻗는 호기심, 새 자리를 탐하는 기질 | 마음이 옮겨가는 결, 정이 이중(二重)으로 흐르는 기색 | 바람기 묘사 |
| `charm_source` | 기상(氣相), 호쾌한 말투, 장대한 풍채 | 자태(姿態), 그윽한 눈빛, 단아한 선(線) | 매력 출처 |
| `advice_voice` | 대장부의 도리, 군자의 길 | 여중군자의 도리, 숙덕(淑德)의 결 | 조언 톤 |

각 슬롯은 4~6 변종. `_g` marker entry 필수.

```dart
'peach_g': [],
'peach_m': ['도화기(桃花氣)', '풍류의 결', '한량의 정취', '풍모의 윤기'],
'peach_f': ['도화(桃花)', '홍도화(紅桃花)', '복숭아꽃 기색', '요색(妖色)의 윤기'],
```

#### 2.2 기존 슬롯 재점검

| 슬롯 | 조치 |
|---|---|
| `energy_yang`/`yin` | 성별 분기 아님 (동양 우주론 기반 음양). **유지**. |
| `fortune_word` | 복록/관록/재록 — 성별 공통. **유지**. |
| `palace_mate` | 처첩궁 — 남자 시점 명칭. **여성용 `palace_spouse_f = ['부군궁(夫君宮)', '남편의 자리']` 추가 고려** → 복잡도 ↑. **v2.5 에서는 '처첩궁' 을 성별 공통 기술 용어로 유지**, 문장의 주어 prefix 만 성별로 분기. |

---

### Phase 3 — 성별 분기 섹션 전면 재작성 (가장 큰 작업, 1~2일)

대상: **연애 · 바람기 · 색기** 3 섹션.

#### 3.1 설계 원칙

- 섹션별 **남/여 독립 beat pool** — 기존 `_romanceBeats` 를 `_romanceBeatsMale` + `_romanceBeatsFemale` 로 분리.
- `assembleLifeQuestions` 에서 `f.isMale ? _romanceBeatsMale : _romanceBeatsFemale` 로 선택.
- 각 pool 은 공통 구조 유지: opening → strength → shadow → advice 4 beat.
- fragment 는 해당 성별 기준으로 관상학적 해석이 달라지는 지점을 반영.

#### 3.2 섹션별 축(axis) 설계

##### 연애운 (새 이성과의 만남)

| 축 | 남성 시각 | 여성 시각 |
|---|---|---|
| 주도권 | 다가서는 역할, 먼저 움직임 | 선택하는 역할, 불러오는 구도 |
| 매력 출처 | 기상·말투·기백 (동작 기반) | 자태·눈빛·선(線) (정적 기반) |
| 타이밍 | "사냥하듯" 집중 공세기 | "낚시하듯" 점진적 관찰기 |
| 리스크 | 급발진·독점욕 | 결정 지연·과도한 검증 |
| 전통 관상 | 관록궁·구각(口角)·준두 힘 | 처첩궁·누당(淚堂)·와잠(臥蠶) 결 |

##### 바람기 (기존 관계 중 외도 경향)

| 축 | 남성 시각 | 여성 시각 |
|---|---|---|
| 발현 조건 | 외부 접촉·자극 노출 시 | 감정적 결핍·일상 권태 시 |
| 신호 | 기존 관계에서 말수 감소, 새 자리에서 활력 | 관계 내 섭섭함이 누적, 새로운 공감에 이끌림 |
| 억제 요소 | 자존심·사회적 평판 | 정(情)의 두께·가정 중심성 |
| 전통 관상 | 어미(魚尾) 주름·귀와 코의 기운 불균형 | 누당(淚堂) 어두움·입술 윤기 변화 |

##### 색기 (정적 오라)

| 축 | 남성 시각 | 여성 시각 |
|---|---|---|
| 오라 성격 | 호방·풍류·한량의 정취 | 요염·유한·그윽함 |
| 발산 방식 | 당당한 체형·기백 | 눈매·입가·목선의 곡선 |
| 관상학 용어 | 풍채(風采)·기백(氣魄)·대장부의 기운 | 도화(桃花)·유한함(幽閑)·수기(水氣) |
| 전통 경계 | "여색을 탐하지 않는 의젓함" | "음기가 과하면 박명(薄命)" |

#### 3.3 beat 개수 가이드

각 섹션당 4 beat × 남/여 2 pool × 평균 4 fragment × 평균 2 variant
= 섹션당 ≈ **64 variant** (기존 ≈ 32)

전체 3 섹션 재작성으로 variant 공간 약 2 배 확장.

#### 3.4 MECE 유지 (재강조)

v2 에서 이미 피드백 받은 사항:
- **연애 ≠ 바람기 ≠ 색기**.
- "몸이 먼저 반응한다" 류 표현은 색기 섹션에만.
- 연애는 "만남의 역학", 바람기는 "기존 관계 중 외도", 색기는 "정적 오라".

재설계에서도 이 MECE 를 성별별로 별도 유지.

---

## 3. 구현 순서 (체크리스트)

### ⬜ Phase 1 — 버그 픽스

- [ ] `Grep '@\{noble_m\}|@\{person_m\}|@\{noble_f\}|@\{person_f\}'` 모든 위치 감사
- [ ] 각 위치 `_m`/`_f` 접미 제거 → `@{noble}`, `@{person}` 통일
- [ ] `_slotPools` 에 `noble_g` / `person_g` marker 확인 (이미 있음)
- [ ] 신규 테스트: 여성 fixture 에 남성 어휘 없음 / 남성 fixture 에 여성 어휘 없음
- [ ] `flutter test test/life_question_narrative_test.dart` green

### ⬜ Phase 2 — 슬롯 풀 확장

- [ ] 신규 슬롯 쌍 7 개 추가 (peach·aura·romance_role·relation_stance·infidelity_risk·charm_source·advice_voice)
- [ ] 각 슬롯 `_g` marker + `_m` / `_f` pool 4~6 변종
- [ ] 기존 v2 fragment 중 의미가 맞는 곳 일부를 신규 슬롯으로 치환 (전면 치환은 Phase 3 에서)
- [ ] 테스트: 각 신규 슬롯이 성별별로 다른 어휘를 반환하는지 확인

### ⬜ Phase 3 — 섹션 재작성

- [ ] `_romanceBeats` → `_romanceBeatsMale` / `_romanceBeatsFemale` 분리
- [ ] `_philanBeats` → `_philanBeatsMale` / `_philanBeatsFemale` 분리
- [ ] `_sensualBeats` → `_sensualBeatsMale` / `_sensualBeatsFemale` 분리
- [ ] 각 pool 에 opening·strength·shadow·advice 4 beat × 4~6 fragment × 2~3 variant
- [ ] `assembleLifeQuestions` 에서 성별 분기:
  ```dart
  MapEntry('연애운', _buildSection(
    f, f.isMale ? _romanceBeatsMale : _romanceBeatsFemale, 40)),
  ```
- [ ] 신규 테스트: 동일 fixture 남/여 실행 시 본문 텍스트 85%+ 상이
  ```dart
  test('동일 fixture 남/여 본문 상이함', () {
    final male = assembleLifeQuestions(_buildReport(Gender.male, thirties));
    final female = assembleLifeQuestions(_buildReport(Gender.female, thirties));
    final diff = _characterDiffRatio(male, female);
    expect(diff, greaterThan(0.85));
  });
  ```
- [ ] MECE 검증: 세 섹션이 서로 같은 문장 블록을 재사용하지 않는지 수동 리뷰
- [ ] 길이 검증: 각 섹션 ≥ 450자 유지

### ⬜ 마감

- [ ] `flutter analyze` clean
- [ ] `flutter test` 전체 green (현 92 + 신규 ~5)
- [ ] `docs/runtime/NARRATIVE.md` 업데이트 — 성별 분기 섹션 목록 추가
- [ ] 이 문서 상단 상태를 `✅ 완료` 로 갱신

---

## 4. 디자인 결정 / 주의사항

### 4.1 왜 단일 pool 에 `_highOf(Attribute.libido) && f.isMale` predicate 로 분기 안 하는가

현재 `_Frag.applies` 는 feature 기반 predicate. 이론상 `(f) => f.isMale && f.bandOf(sensuality) == high` 라고 쓸 수 있지만:

1. **가독성**: 남/여 fragment 가 섞이면 pool 이 2 배로 부풀어 선택 비율이 불균형.
2. **시드 편향**: valid 리스트에서 seed 로 하나 고를 때 "반대 성별 fragment 가 valid 에 안 들어가도록" 모든 fragment 에 `f.isMale &&`/`!f.isMale &&` 붙여야 함 — 매우 쉽게 누락.
3. **관상학적 독립성**: 연애·바람기·색기는 남/여 시각이 거의 겹치지 않는다. 풀을 분리하는 편이 관리 쉬움.

따라서 **섹션 레벨에서 pool 자체를 분기**하는 방식이 맞다.

### 4.2 슬롯 레벨 vs 섹션 레벨 분기의 분업

- **슬롯 레벨** (noble/person/peach/aura 등): 어휘 수준 분기. 모든 섹션에서 공유 쓰임.
- **섹션 레벨** (romance/philan/sensual pool 분리): 논리 구조 분기. 관상학적 해석이 근본적으로 다른 섹션에만 적용.

재능·재물·대인·건강·조언 섹션은 **섹션 레벨 분기 불필요** — 슬롯 레벨 분기로 충분. 관상학적으로 남녀 해석 차이가 주로 어휘·주어 차이에서 오기 때문.

### 4.3 "처첩궁" 같은 용어 처리

기술 용어 (十二宮 명칭) 는 전통적으로 남성 기준 명명이 많다:
- 처첩궁(妻妾宮) — "아내와 첩" 이라는 명칭
- 남녀궁(男女宮) — 자녀의 궁 (중성)
- 노복궁(奴僕宮) — 부하·하인의 궁 (중성)

**결정**: 십이궁 명칭은 관상학 전통 용어로 유지 (여성 리포트에도 '처첩궁' 그대로 사용). 대신 그 궁을 **설명하는 문장** 에서 성별에 맞는 주어/관점을 씀.

예:
- 남성: "당신의 @{palace_mate}에는 처를 품는 기운이 @{intense} 서려 있어..."
- 여성: "당신의 @{palace_mate}에는 부군과 오래 맞추는 결이 @{intense} 서려 있어..."

---

## 5. 완료 기준 (Acceptance Criteria)

1. `flutter analyze lib/domain/services/life_question_narrative.dart` — 0 warning.
2. `flutter test` — 전체 green, 신규 성별 테스트 포함.
3. 동일 fixture 에 대해 남/여 본문 text diff ratio ≥ 85%.
4. 여성 리포트에 `'장부'`, `'대장부'`, `'사내'`, `'지장'` 어휘 0 건.
5. 남성 리포트에 `'여중군자'`, `'규수'`, `'안주인'` 어휘 0 건.
6. 각 섹션 평균 길이 550~650자 범위 (현재 기준 유지).
7. `docs/runtime/NARRATIVE.md` 성별 분기 섹션 목록 반영.

---

## 6. PC2 에서 이어받기 위한 context

**현재 작업 기준 commit**: `1e32fe2 update docs` (혹은 이 문서 커밋 이후).

**재개할 때 읽어야 할 파일 순서**:
1. 이 문서 (`docs/runtime/NARRATIVE_GENDER_REDESIGN.md`) — 전체 계획
2. `docs/runtime/NARRATIVE.md` — v2 엔진 현재 설계
3. `lib/domain/services/life_question_narrative.dart` — 구현 대상
4. `test/life_question_narrative_test.dart` — 기존 테스트 구조

**재개 첫 명령 예시**:
> "NARRATIVE_GENDER_REDESIGN.md 의 Phase 1 부터 시작하라."

**중간 중단 시 상태 보존**:
- 각 Phase 체크리스트 위 ⬜ 을 ✅ 로 갱신.
- "구현중" Phase 이면 어떤 fragment 까지 작성했는지 이 문서에 한 줄 메모 추가.

---

## 연관 문서

- [NARRATIVE.md](NARRATIVE.md) — v2 엔진 설계 (Beat-Fragment Grammar)
- [../engine/ATTRIBUTES.md](../engine/ATTRIBUTES.md) — 10 attribute 정의 (sensuality, libido, attractiveness 등 성별 분기와 연결된 속성)
- [../engine/RATIONALE.md](../engine/RATIONALE.md) — 관상 전통 출처 (마의상법·유장상법 여상편)
