# 14-node 부위별 expandable UI (Work Plan)

**작성**: 2026-04-18
**상태**: 📋 **계획 수립 완료, 구현 대기중**
**대상 파일**:
- `lib/presentation/screens/home/report_page.dart` (UI wrapper 추가)
- `lib/data/constants/node_text_blocks.dart` (신규 — 서술 텍스트 SSOT)
**관련 문서**: [NARRATIVE.md](NARRATIVE.md) · [../engine/TAXONOMY.md](../engine/TAXONOMY.md) · [../engine/ATTRIBUTES.md](../engine/ATTRIBUTES.md)

---

## 0. 배경 — 현재 누락된 것

리포트 UI 의 두 점수 섹션 비교:

| 섹션 | expandable | 탭 시 노출 |
|---|---|---|
| 10 attribute 점수 | ✅ `_ExpandableAttributeBar` | top-5 contributor (node:xx, 규칙 id, ±값) |
| 14-node tree 점수 | ❌ 정적 bar + 숫자 | — |

따라서 사용자가 "내 코가 z=1.5 인데 이게 관상학적으로 무슨 뜻인가?" 를 바로 알 수 없다. 이마·미간·눈썹·눈·코·광대·귀·인중·입·턱 각 부위의 **전통 관상 해석 블록** 이 필요.

---

## 1. 목표

1. **14-node tree** 의 leaf node 및 zone node 를 attribute 처럼 탭해서 펼 수 있게.
2. 펼치면 해당 node 의 z-band(high / mid / low) 에 맞는 관상학적 해석 본문 노출.
3. 성별(남/여)로 해석이 크게 갈리는 부위는 성별 분기 본문 준비.
4. 해당 node 에 귀속된 metric(z-score) 리스트도 함께 노출 (투명성).

---

## 2. 텍스트 데이터 구조

### 2.1 SSOT 파일: `lib/data/constants/node_text_blocks.dart`

```dart
class NodeTextBlock {
  final String label;              // '이마' · '미간(印堂)' 등
  final String? shared;            // 성별 공통 본문 (없으면 null)
  final String? male;              // 남성 특화 본문
  final String? female;            // 여성 특화 본문

  const NodeTextBlock({
    required this.label,
    this.shared,
    this.male,
    this.female,
  });
}

class NodeTextSet {
  final NodeTextBlock high;   // z ≥ +1.0
  final NodeTextBlock mid;    // |z| < 1.0
  final NodeTextBlock low;    // z ≤ -1.0

  const NodeTextSet({
    required this.high,
    required this.mid,
    required this.low,
  });
}

const Map<String, NodeTextSet> nodeTextBlocks = {
  'forehead': NodeTextSet(
    high: NodeTextBlock(
      label: '이마',
      shared: '넓고 시원하게 열린 이마. 관상학에서 상정(上停)이 …',
    ),
    mid: NodeTextBlock(label: '이마', shared: '…'),
    low: NodeTextBlock(label: '이마', shared: '…'),
  ),
  // … 14 node
};
```

### 2.2 Band 경계

attribute_derivation 과 일관:
- `z ≥ +1.0` → high
- `-1.0 < z < +1.0` → mid
- `z ≤ -1.0` → low

zone node (upper/middle/lower) 는 `rollUpMeanZ` 기준, leaf 는 `ownMeanZ` 기준.

### 2.3 본문 작성 지침

- **분량**: 각 block 200~350자.
- **톤**: 관상학 전통 용어 + 현대 생활 언어 혼용 (NARRATIVE.md 와 동일 voice).
- **성별 분기 필수 node**:
  - `eye` · `nose` · `mouth` · `cheekbone` — 성별별 해석이 큰 부위
  - 나머지는 `shared` 만으로도 가능
- **금지**:
  - "레거시 / 기존 / 예전" (CLAUDE.md 문서 규칙)
  - attribute 점수 재언급 (중복)
  - "몸이 먼저 반응" 류 트로프 (NARRATIVE.md MECE 원칙 준수)

### 2.4 Metric 매핑 표시용 label

각 node 에 귀속된 metric 은 이미 `lib/domain/models/physiognomy_tree.dart` 에 선언됨. UI 에서 펼쳤을 때 metric z-score 를 친화적 레이블로 노출:

```dart
const Map<String, String> metricDisplayLabels = {
  'nasalWidthRatio': '코 너비',
  'nasalHeightRatio': '코 길이',
  'nasolabialAngle': '코끝 각도',
  // …
};
```

---

## 3. UI 설계

### 3.1 새 widget: `_ExpandableNodeBar`

`_ExpandableAttributeBar` (report_page.dart:38~) 를 본떠 작성:

```dart
class _ExpandableNodeBar extends StatefulWidget {
  final String nodeId;
  final String label;          // '    이마' 처럼 indent 포함
  final double z;              // rollUpMeanZ (leaf 면 ownMeanZ 와 동일)
  final NodeEvidence evidence;
  final Gender gender;
  final Map<String, MetricResult> metrics;   // 이 node 의 직계 metric
  final bool isZone;           // upper/middle/lower → 굵은 글꼴 유지
  // …
}
```

### 3.2 펼친 뷰 구성

```
[z-bar]  이마                           +1.23
              ────────────────────────── ▼
               (펼치면)
               ┌──────────────────────────┐
               │ 상정(上停)이 넓고 시원하게  │  ← NodeTextBlock.shared
               │ 열린 상으로, 학문과 관직의 │   (high band)
               │ 기운이 …                   │
               │                          │
               │ ── 세부 측정값 ──         │
               │ 상부 비율   +0.8           │
               │ 이마 너비   +1.5           │
               │ 헤어라인    +0.3           │
               └──────────────────────────┘
```

### 3.3 gender 선택 로직

```dart
String resolveBody(NodeTextBlock block, Gender gender) {
  if (gender == Gender.male && block.male != null) return block.male!;
  if (gender == Gender.female && block.female != null) return block.female!;
  return block.shared ?? '';
}
```

### 3.4 `_buildNodeScoreSection` 수정

현 report_page.dart:818~917 의 `Padding + Row + _NodeZBar` 블록을 `_ExpandableNodeBar` 호출로 치환. 기존 삼정 radar 위젯 (`_SamjeongRadar`) 은 그대로 유지.

---

## 4. 단계별 계획

### Phase 1 — 데이터 SSOT 작성 (4~6시간)

- [ ] `lib/data/constants/node_text_blocks.dart` 파일 생성
- [ ] 14 node × 3 band = 42 block 작성 (shared only)
- [ ] 성별 분기가 큰 4 node (eye·nose·mouth·cheekbone) 에 `male` / `female` 본문 추가 → +24 block
- [ ] `metricDisplayLabels` 맵 작성 (17+8 = 25 entry)
- [ ] unit test: 모든 node 의 모든 band 가 작성됐는지, 각 본문 150자 이상인지 검증

### Phase 2 — UI wrapper (2~3시간)

- [ ] `_ExpandableNodeBar` 위젯 신설 (Attribute bar 구조 재사용)
- [ ] 펼친 뷰: NodeTextBlock body + metric z 리스트
- [ ] `_buildNodeScoreSection` 을 expandable bar 사용하도록 교체
- [ ] zone node (upper/middle/lower) 는 subnode 묶음 설명을 펼침 대신 header 로 유지할지 결정
  - 옵션 A: zone 도 동일하게 펼침 (삼정 조화 설명)
  - 옵션 B: zone 은 굵게, leaf 만 펼침
  - **권장**: 옵션 A — 삼정 불균형 해석이 풍부해서 가치 있음
- [ ] `face` root 는 제외할지 포함할지 결정 (현재 표시됨) — 포함하고 "얼굴 전체 프로포션" 블록 제공

### Phase 3 — 통합·검증 (1~2시간)

- [ ] 기기 실행: 실 리포트에서 탭 → 펼침 동작 확인
- [ ] 긴 본문 텍스트 스크롤 확인
- [ ] 성별 분기 시각 검증 — 동일 fixture 남/여 스크린샷 비교
- [ ] `flutter test` 전체 green
- [ ] `flutter analyze` clean

### Phase 4 — 문서 마감

- [ ] `docs/runtime/NARRATIVE.md` 에 "부위별 expandable UI" 링크 추가
- [ ] `docs/architecture/OVERVIEW.md` §4 Runtime Pipeline 에 UI 구성 반영
- [ ] 이 문서 상단 상태를 `✅ 완료` 로 갱신
- [ ] CLAUDE.md 🚧 섹션에서 해당 행 삭제

---

## 5. 완료 기준 (Acceptance Criteria)

1. 14 node 모두 탭 → 펼침 동작.
2. 각 펼친 뷰는 band 에 맞는 본문 200자 이상 + metric z-score 리스트 표시.
3. 성별 분기 4 node (eye·nose·mouth·cheekbone) 는 남/여 리포트에서 서로 다른 본문 노출.
4. `flutter analyze` · `flutter test` 전부 green.
5. 스크롤·폰트·배경색 등 기존 `_ExpandableAttributeBar` 와 시각 톤 일치.

---

## 6. 왜 이 설계인가 (선택 근거)

**Q. 왜 node 별 본문을 정적 const 로? narrative 엔진처럼 beat-fragment 로 생성하지 않는 이유?**

- node 설명은 **동일 band 안에서는 같은 말이 반복되어도 OK**. 오히려 일관성이 신뢰감.
- narrative 섹션은 "전체 얼굴을 관통하는 서술" 이라 variation 이 중요하지만, node 는 "이 부위만 독립 해석" 이라 탁상 사전 스타일이 맞음.
- 42~66 block 수준은 수작업 유지가 현실적.

**Q. 왜 band 3단계 (high/mid/low) 뿐?**

- attribute_derivation 의 organ rule 트리거가 보통 `|z| ≥ 1.0` 에서 작동. 3단계로 충분.
- 세분화하면 본문 작성량이 배로 늘고, band 경계에서 본문이 확 바뀌어 부자연스러움.

**Q. zone node (upper/middle/lower) 도 펼쳐야 하는가?**

- 삼정 조화/불균형 해석은 전통 관상학의 핵심. **펼쳐야 한다.**
- zone 펼친 뷰는 "상정이 중정보다 한결 높다" 같은 **상대 비교** 서술을 담을 수 있어 leaf 와 다른 가치.

---

## 7. PC2 에서 이어받기

**재개 지시**:
> "NODE_EXPANDABLE_UI.md 의 Phase 1 부터 시작하라."

**재개할 때 읽어야 할 파일**:
1. 이 문서
2. `docs/engine/TAXONOMY.md` — 14 node 전통 의미·metric 매핑 SSOT
3. `lib/presentation/screens/home/report_page.dart` — `_ExpandableAttributeBar` (참조 구조) + `_buildNodeScoreSection` (교체 대상)
4. `lib/domain/models/physiognomy_tree.dart` — 각 node 에 귀속된 metric id

---

## 연관 문서

- [NARRATIVE.md](NARRATIVE.md) — 인생 질문 서술 엔진 (본 작업과 별개 트랙)
- [NARRATIVE_GENDER_REDESIGN.md](NARRATIVE_GENDER_REDESIGN.md) — 서술 엔진 성별 분기 재설계 (병렬 진행 가능)
- [../engine/TAXONOMY.md](../engine/TAXONOMY.md) — 14 node 전통 의미 SSOT
- [../engine/ATTRIBUTES.md](../engine/ATTRIBUTES.md) — attribute → node 귀속 관계
