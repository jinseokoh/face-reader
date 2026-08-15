# NARRATIVE v2 — 작업 인계

서술 코퍼스를 **현재 시제 + 백분위 근거** 로 다시 쓰는 작업. 이 문서 하나로
이어서 작업할 수 있어야 한다.

---

## 0. 왜 하는가

App Store **4.3(b)** 로 두 번 리젝됐다 (`e699a06d`, build 6 / build 15).
정식 appeal 을 준비 중이고 문안은 [`APPEAL.md`](./APPEAL.md) 에 있다.

편지의 핵심 문장이 이거다:

> *"We are not asking the Board to accept that facial measurement predicts
> anything, and we make no such claim to users."*

**지금 리포트는 이 문장을 반박한다.** 본문에 `말년 곡선`(6회) · `노년`(16회) ·
`평생`(35회) 이 있고, *"30대부터 들이는 돈의 총량이 말년 곡선의 기울기를 거의
그대로 정합니다"* 같은 미래 단정이 그대로 나간다.

**v2 는 그 문장을 사실로 만들기 위한 코퍼스다.**

---

## 1. 확정된 톤 — D안

네 가지를 비교해서 D 로 정했다.

| | 예시 | 판정 |
| --- | --- | --- |
| A 선언 (v1) | 재물운이 평균대 위에서 단단한 편입니다. 30대부터 들이는 돈의 총량이 말년 곡선의 기울기를 정합니다. | ❌ 미래 단정 |
| B 측정 서술 | 위험을 감수하는 항목의 값이 낮고, 안정을 택하는 항목의 값이 높습니다. | 안전하나 건조 |
| C 확률 | 이런 구성에서는 안정을 택하는 경향이 더 자주 나타납니다. | ⚠️ 근거 불명 |
| **D 백분위 + 서술** | **재력이 같은 성별·얼굴형 분포에서 상위 18% 구간입니다. 한 번의 큰 결정보다 같은 선택을 반복하는 쪽에 값이 몰려 있습니다.** | ✅ |

### D 를 고른 이유

**C 의 함정** — "연구에 따르면 확률적으로" 를 쓰면 안 된다. Kachur et al.(2020)
이 잰 건 **Big Five** 지 `재력`·`흡인력` 이 아니다. 그 연구를 암시하면 다루지도
않은 것에 근거를 갖다 붙이는 셈이고, 심사관이 확인하면 역효과다.

**D 의 근거는 외부가 아니라 자체 분포다.** `attribute_normalize.dart` 의
21-point quantile 테이블(성별 × 얼굴형)에서의 위치라 **문장이 참임이 구조적으로
보장된다.** 그리고 `단단한 편입니다` 보다 정보량이 많다.

### 문장 규칙

```
[백분위 사실]  재력이 같은 성별·얼굴형 분포에서 @{pct:wealth} 구간입니다.
[경향 서술]    한 번의 큰 결정보다 같은 선택을 반복하는 쪽에 값이 몰려 있습니다.
```

| 금지 | 대신 |
| --- | --- |
| 미래 시제 — `말년`·`평생`·`노년`·`~정합니다` | 전부 현재형 |
| 은유 — `돈이 머물고 싶어하는 얼굴`·`진가가 난다` | 제거 |
| 단정 — `~합니다` | 관찰 — `~더 자주 관찰됩니다`·`~쪽이 많습니다` |
| 외부 연구 인용 | 자체 분포만 |
| 결과 예측 | 성향 서술 |

분량은 v1 과 같게 (2문장). 존칭어체 유지.

---

## 2. 이미 만들어진 것

### 2.1 코퍼스 버전 골격

```
flutter/lib/domain/services/
├── life_question_narrative.dart    ← 엔진 + v1 섹션 정의
└── narrative_corpus_v2.dart        ← part. v2 섹션 정의 + v2 풀
```

`part` 이므로 `_Frag`·`_Features`·`_BeatPool` 같은 private 타입을 그대로 쓴다.
식별자는 `_v2` 접두사로 v1 과 충돌을 피한다.

```dart
enum NarrativeVersion { v1, v2 }

typedef _SectionDef = ({
  String title,
  int salt,
  List<_BeatPool> Function(_Features f) pools,
  bool Function(_Features f)? when,   // 활력의 30세 조건이 여기로
});

String assembleLifeQuestions(FaceReadingReport r,
    {NarrativeVersion version = NarrativeVersion.v1})
```

### 2.2 원격 전환 (재배포 불필요)

`app_config` 에 플랫폼별 컬럼 2개를 추가했고 **라이브 DB 반영 완료.**

```sql
update public.app_config set ios_narrative_version = 2 where id = 1;
```

- `AppConfigService.instance.narrativeVersion` 이 앱 시작 시 채워진다
- 조회 실패·컬럼 없음 → **v1 fallback** (네트워크 사고에 안전)
- 호출부 2곳 배선 완료 — `metaphor_repository.dart` · `report_page.dart`

### 2.3 백분위 노출

```dart
// shared/lib/domain/services/attribute_normalize.dart
double attributePercentile(double raw, Attribute attr, Gender g, FaceShape s)
```

`_rawToPercentile` 을 공개했다. **모델·직렬화 변경 없음** — `AttributeEvidence
.rawTotal` 이 이미 있어서 조회 시점에 계산한다.

`_Features.percentiles` (`Map<Attribute, double>`, 0..1) 로 들어가고,
동적 슬롯이 그걸 문장에 꽂는다.

```dart
// life_question_narrative.dart — Step 0
@{pct:wealth}  →  '상위 18%' / '하위 22%'
```

`_v2PctPhrase()` 가 포맷한다. 1~50 으로 clamp — `상위 0%` 같은 과장 방지.

### 2.4 섹션 제목

| v1 | v2 |
| --- | --- |
| 타고난 재능 | 타고난 재능 |
| **건강** (수정됨) | 건강 |
| **재력** (수정됨) | 재력 |
| 대인관계 | 대인관계 |
| **연애** (수정됨) | 연애 |
| **관능도 / 활력** ← iOS 만 활력 | 활력 |
| 종합 조언 | 종합 조언 |

v1 도 같이 정리했다. **`관능도` 만 플랫폼 분기** — `Platform.isIOS ? '활력' :
'관능도'`. Android 는 현행 유지 요청.

### 2.5 속성 라벨 (양 플랫폼 공통)

세 항목 다 **엔진이 계산하는 것과 이름이 어긋나 있었다.**

| enum | v1 이전 | 현재 | 엔진이 실제로 재는 것 |
| --- | --- | --- | --- |
| `wealth` | 재물운 / Wealth Fortune | **재력 / Financial Strength** | 계측 z-score |
| `sensuality` | 바람기 / Sensuality | **흡인력 / Magnetism** | `곁에 있으면 끌린다` |
| `libido` | 관능도 / Sexual Energy | **활력 / Vitality** | 9노드 가중합 = 에너지 |

칩도 같이 — `#재물복`→`#재력형`, `#재물복약함`→`#재력약함`, `#뜨거움`→`#하이텐션`.
흡인력 칩은 원래 `#끌림강함/약함` 이라 무변경.

**`trustworthiness/신뢰성` 은 절대 건드리지 마라.** Todorov 의 valence 축이라
유일하게 문헌이 받쳐주는 항목이다.

---

## 3. 남은 작업

### 3.1 진행률

문장 리터럴 **544개** 중 opening 풀 하나(13문장) 완료.

| 섹션 | 풀 | 상태 |
| --- | --- | --- |
| **재력** | opening(10 frag) | ✅ `_v2WealthOpening` |
| 재력 | vignette(5) · strength(6) · shadow(5) · advice(13) | ⬜ |
| 건강 | 5풀 | ⬜ 운명 어휘 밀도 2위 |
| 연애 | 남/여 분리 5풀 ×2 | ⬜ |
| 활력 | 남/여 분리 5풀 ×2 | ⬜ |
| 대인관계 | 5풀 | ⬜ 원래 현재형이 많아 작업량 적음 |
| 타고난 재능 | 5풀 | ⬜ 동상 |
| 종합 조언 | 4풀 | ⬜ |

**교체 순서 (운명 어휘 밀도순)** — 재력 → 건강 → 연애 → 활력 → 대인관계 →
타고난 재능 → 종합 조언

### 3.2 작업 방법

1. v1 풀의 **조건 구조를 1:1 로 미러링한다.** `_Frag(_bandPair(...))` 조건은
   그대로 두고 문장만 새로 쓴다. 조건 로직·가중치·엔트로피는 한 줄도 안 건드린다
2. `_v2` 접두사로 새 풀을 만든다 — `_v2WealthVignette` 등
3. `_v2WealthBeats` 리스트에서 해당 항목을 v1 → v2 로 교체
4. **조건 커버리지 주의** — v1 에 있는 조건이 v2 에 없으면 그 조합의 사용자가
   빈 섹션을 받는다. `_Frag.hard((f) => true)` fallback 은 반드시 있어야 한다

`_v2WealthOpening` 이 완성된 참조 구현이다. 그대로 따라 하면 된다.

### 3.3 아직 안 정한 것

- **`#재력형` 칩** — 다른 강함 칩(`#리더감`·`#명석함`)에 비해 밋밋. 그대로 갈지
- **v1 의 `건강과 수명`→`건강` 이후 본문 정합성** — 제목은 바꿨는데 본문에
  수명 얘기가 남아 있다
- **어필 제출 시점** — v2 를 어디까지 채우고 낼지. 최소선은 `재력`·`건강`

---

## 4. 검증

```bash
cd flutter
flutter analyze     # baseline 4건(전부 info)만 남아야 한다
flutter test        # 168 green
```

`test/life_question_narrative_test.dart` 가 섹션 개수·제목을 검사한다.
**테스트는 host 실행이라 `Platform.isIOS == false`** → `관능도` 로 나온다.
iOS 분기를 바꾸면 이 테스트를 같이 봐야 한다.

v2 를 실제로 보려면 DB 에서 켜거나, 테스트에서
`assembleLifeQuestions(report, version: NarrativeVersion.v2)` 로 부른다.

---

## 5. 이 작업 밖의 상태

| | |
| --- | --- |
| **6 pillar 피벗** | `docs/superpowers/specs/2026-08-14-taste-matching-pivot-design.md` 에 설계 확정·커밋. **appeal 결과 나올 때까지 완전 보류.** 코드 미착수 |
| **chemymatrix 신규 앱** | appeal 실패 시 실행. 도메인 `chemymatrix.kr` 미등록 확인됨 |
| **MeSo 레코드 롤백** | `PLAN.md`. appeal 결과에 따라 결정 |
| **Android** | `관상은 과학이다` 절대 고수. Play 전용, 사용자 활동 중. **동결** |
| **포럼 글** | 모더레이션 대기 중 |

---

## 6. 참고 문헌 (APPEAL.md 와 동일)

**쓸 수 있는 것** — Farkas 국제 인체계측 연구 · CDC 3D Facial Norms Database ·
Oosterhof & Todorov (2008) PNAS

**쓰면 안 되는 것** — Kachur et al. (2020) 효과크기 0.243 · Megastudy (2023)
23% · Current Opinion (2024) *"not very accurate"*. **예측 정확도를 주장하는
순간 이 셋이 그대로 반박이 된다.**
