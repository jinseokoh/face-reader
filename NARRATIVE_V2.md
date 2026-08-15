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

### 온보딩 카피 — 같은 규칙의 압축

세 문장이 D안 전체를 요약하고, [`APPEAL.md`](./APPEAL.md) 의 카테고리 분리
논지와 결이 같다. 온보딩 이미지에 이 문안을 쓴다.

> 우리는 관상으로 앞일을 점쳐드리지 않습니다.
> 얼굴에서 468개 점을 재고 같은 성별 같은 얼굴형 분포 위에 올립니다.
> 그래서 나오는 건 예언이 아니라 등수입니다.

편지의 *"We are not asking the Board to accept that facial measurement
predicts anything"* 이 한국어 사용자 문안으로 옮겨진 것이다. **비예측 선언이
물러서는 말이 아니라 카테고리 분리의 증거**라는 점에서 어필과 같은 축에 있다 —
운세 앱은 예측을 팔고, 이 앱은 팔지 않는다.

`_v2ConcludeAdvice` 의 마지막 beat 도 같은 말을 리포트 본문에서 한다.

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

## 3. 코퍼스 — 완료

### 3.1 진행률

**7 섹션 전부 v2 코퍼스로 교체 완료.** `_v2Sections` 가 v1 풀을 하나도
가리키지 않는다. `narrative_corpus_v2.dart` 1442줄 / `_Frag` 346개.

| 섹션 | 풀 | 상태 |
| --- | --- | --- |
| 타고난 재능 | opening · vignette · strength · shadow · advice | ✅ |
| 건강 | 5풀 | ✅ |
| 재력 | 5풀 | ✅ |
| 대인관계 | 5풀 | ✅ |
| 연애 | opening·vignette·advice 공용 + strength·shadow 남/여 | ✅ |
| 활력 | opening·vignette·strength·advice 공용 + shadow 남/여 | ✅ |
| 종합 조언 | 4풀 | ✅ |

### 3.2 v1 과 달라진 것

1. **조건 구조는 1:1 미러링.** `_Frag(_bandPair(...))` 조건·가중치·엔트로피는
   한 줄도 안 건드리고 문장만 새로 썼다. 각 풀 마지막은 반드시
   `_Frag.hard((f) => true)` fallback 이라 커버리지 구멍이 없다.
2. **성별 분리 축소.** v1 은 연애·활력을 남/여 완전 분리 풀로 뒀는데, 조건
   집합이 완전히 같은 풀(연애 opening·advice, 활력 opening·strength·advice)은
   측정 서술이 성별로 달라질 근거가 없어 공용 풀 하나로 합쳤다. 조건이 실제로
   다른 연애 strength·shadow 만 분리를 유지한다.
3. **활력 = 에너지로 되돌림.** §2.5 에서 `관능도`→`활력` 로 라벨을 고쳤는데,
   본문이 성적 서사로 남으면 이름과 내용이 다시 어긋난다. libido(9노드
   가중합 = 에너지 총량) · sensuality(곁에 있으면 끌린다 = 흡인력) 를 실제로
   재는 대로 서술한다.
4. **어투 통일.** v1 의 관능도 풀만 반말이었다. 전부 존칭어체.
5. **종합 조언 마지막 beat 에 비예측 선언을 명시했다** — *"이 리포트는 얼굴
   계측값이 같은 성별·얼굴형 분포에서 어디에 놓이는지를 읽은 것이지, 앞일을
   맞히는 게 아닙니다."* [`APPEAL.md`](./APPEAL.md) 의 핵심 문장이 본문에
   그대로 들어간 셈이다.

### 3.3 결정된 것

- **`#재력형` → `#돈감각`** — `#리더감`·`#명석함` 과 같은 "명명된 능력" 레지스터.
  약함 칩 `#재력약함` 은 `#멘탈약함` 계열과 나란해서 그대로 둔다.
- **`건강` 본문 정합성** — `수명` 16회를 포함해 운명 어휘가 v2 본문에서 0.
- **어필 제출 시점** — 코퍼스는 더 이상 제약이 아니다. 남은 건
  `ios_narrative_version = 2` 스위치를 켜는 시점 판단.

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

**v2 커버리지 확인 결과** (성별 2 × 연령대 9 × z 스케일 7 = 126 리포트):
미해결 슬롯 0 · 미해결 placeholder 0 · 금지 어휘 0 · 빈/얇은 섹션 0 ·
섹션 수 30세 미만 6 / 30세 이상 7. 상시 테스트로 남기진 않았다.

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
