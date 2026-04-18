# 관상학 분류 체계 (Physiognomy Taxonomy)

**버전**: 1.0
**확정일**: 2026-04-18
**상태**: 설계 확정, 구현 대기
**역할**: 관상 분석 엔진의 hierarchical tree 구조의 단일 진실 원본 (SSOT).

---

## 0. 개요

face-reader 앱의 관상 분석 엔진을 기존 flat 구조(metric → 10 attribute → score)에서
hierarchical 구조로 재설계하기 위한 분류 체계를 정의한다. 전통 동아시아 관상학 3대 고전
(마의상법·유장상법·신상전편)의 공통 뼈대와 현대 얼굴 과학(Farkas, Todorov, Zebrowitz,
BiSeNet 등)의 영역 분할을 교차 검증해 확정했다.

**확정 옵션**: α — 삼정(三停) 우선 tree + 오관(五官)·오악(五嶽)·사독(四瀆)·십이궁(十二宮)
메타데이터 오버레이.

---

## 1. 설계 원칙

1. **전통 충실** — 전통 3대 고전 卷一의 좌표계와 일치. 위→아래 부위 순회 순서.
2. **과학적 지지** — Farkas 네오클래식 수직 3등분·BiSeNet 파싱 영역과 정합.
3. **코드 실현 가능** — Dart tree 자료구조로 단순 표현. 노드 총 14개(루트 1 + 삼정 3 + leaf 10).
4. **밸런스 강제** — 각 부위 metric 예산을 루트에서 할당. 한 부위 과집중 구조적 차단.
5. **확장 가능** — 새 metric/규칙/해석 추가 시 노드 소속만 결정하면 됨.
6. **메타데이터 다중 태그** — 한 노드가 여러 전통 체계(오관/오악/사독/십이궁)에 동시 속할 수 있음.

---

## 2. 트리 구조

```
face (root)
├── 상정 (upper third)
│   ├── 이마 (forehead)
│   ├── 미간 (glabella)
│   └── 눈썹 (eyebrow)
├── 중정 (middle third)
│   ├── 눈 (eye)
│   ├── 코 (nose)
│   ├── 광대 (cheekbone)
│   └── 귀 (ear)
└── 하정 (lower third)
    ├── 인중 (philtrum)
    ├── 입 (mouth)
    └── 턱 (chin/jaw)
```

**총 14 노드** = 루트 1 + 삼정(zone) 3 + leaf(부위) 10.

### 2.1 자료 구조 규약 (코드 구현 가이드)

```dart
enum Zone { upper, middle, lower }
enum Organ { 보수관, 감찰관, 심변관, 출납관, 채청관 }
enum Mountain { 형산, 태산, 화산, 숭산, 항산 }
enum River { 강, 하, 회, 제 }
enum Palace { 명궁, 재백궁, 형제궁, 전택궁, 남녀궁, 노복궁, 처첩궁,
              질액궁, 천이궁, 관록궁, 복덕궁, 상모궁 }

class PhysiognomyNode {
  final String id;                    // 'forehead', 'eye' ...
  final String nameKo;                // '이마', '눈'
  final Zone zone;                    // upper/middle/lower
  final List<Organ> organs;           // 오관 태그
  final List<Mountain> mountains;     // 오악 태그
  final List<River> rivers;           // 사독 태그
  final List<Palace> palaces;         // 십이궁 태그
  final List<String> metricIds;       // 이 노드에 속하는 metric id
  final List<PhysiognomyNode> children;
}
```

---

## 3. 노드별 의미 및 메타데이터

### 3.1 상정 (upper third)

#### 이마 (forehead)
- **위치**: 헤어라인(landmark 10) ~ 눈썹 상단(~66/296)
- **관상학적 의미**: 지혜·초년 복·선천 운명·사회적 성취·이주 운
- **오악**: 형산(남)
- **십이궁**: 관록궁(중앙), 천이궁(양측)

#### 미간 (glabella)
- **위치**: 두 눈썹 사이(landmark 9 부근). 인당(印堂).
- **관상학적 의미**: 운명 핵심. 기색 변화 민감도 최상.
- **십이궁**: 명궁

#### 눈썹 (eyebrow)
- **위치**: landmarks 46~55 / 276~285
- **관상학적 의미**: 건강·수명·형제·친구 관계·명예
- **오관**: 보수관(保壽官)
- **십이궁**: 형제궁

### 3.2 중정 (middle third)

#### 눈 (eye)
- **위치**: 33/263 외안각, 133/362 내안각, 159/386 상안검, 145/374 하안검
- **관상학적 의미**: 지혜·감정·재물·관운·인간관계 전반
- **오관**: 감찰관(監察官)
- **사독**: 하(河)
- **십이궁**: 전택궁(상안검), 남녀궁(와잠), 처첩궁(눈꼬리)

#### 코 (nose)
- **정면 위치**: 1 코끝, 4 columella, 94 subnasale, 98/327 콧방울, 168 nasion
- **측면 위치**: dorsal curve, nasofrontal, nasolabial, tip projection
- **관상학적 의미**: 재물·자존·의지·중년 운
- **오관**: 심변관(審辨官)
- **오악**: 숭산(중)
- **사독**: 회(淮)
- **십이궁**: 재백궁(전체), 질액궁(산근)

#### 광대 (cheekbone)
- **위치**: 234/454 외측, 93/323 광대 돌출부
- **관상학적 의미**: 권위·사회적 자아·대외 활동력
- **오악**: 태산(좌), 화산(우)

#### 귀 (ear)
- **위치**: MediaPipe face mesh 는 귀 세부를 커버 안 함. 234/454 는 귀 앞 기준점일 뿐.
- **관상학적 의미**: 지혜·장수·초년운·소통
- **오관**: 채청관(採聽官)
- **사독**: 강(江)
- **⚠️ 기술 제약**: 정면 mesh 로 귓불·이륜 측정 불가. v1.0 에서는 **측정 미지원** 선언.

### 3.3 하정 (lower third)

#### 인중 (philtrum)
- **위치**: landmark 2 subnasale ~ 13 lip top
- **관상학적 의미**: 자녀 복·생식력·수명
- **십이궁**: 자녀궁 부분 중첩

#### 입 (mouth)
- **정면 위치**: 61/291 입꼬리, 0/17 상하순 중앙
- **측면 위치**: upper/lower lip E-line, mentolabial angle
- **관상학적 의미**: 언변·재능·음식 복·구설수
- **오관**: 출납관(出納官)
- **사독**: 제(濟)

#### 턱 (chin/jaw)
- **위치**: 152 턱끝, 172/397 하악선, 148/377 턱 좌우
- **관상학적 의미**: 말년 안정·인내·품격·부하 운·주거 운
- **오악**: 항산(북)
- **십이궁**: 노복궁

---

## 4. 메타데이터 오버레이 요약

### 4.1 오관(五官) — 기능적 기관

| 관 | 정식 명칭 | 노드 |
|---|---|---|
| 보수관 | 保壽官 | 눈썹 |
| 감찰관 | 監察官 | 눈 |
| 심변관 | 審辨官 | 코 |
| 출납관 | 出納官 | 입 |
| 채청관 | 採聽官 | 귀 |

### 4.2 오악(五嶽) — 돌출 영역 볼륨 평가

| 악 | 노드 |
|---|---|
| 형산(남) | 이마 |
| 태산(동) | 광대(좌) |
| 화산(서) | 광대(우) |
| 숭산(중) | 코 |
| 항산(북) | 턱 |

### 4.3 사독(四瀆) — 유통 평가 (통/막힘)

| 독 | 노드 |
|---|---|
| 강(江) | 귀 |
| 하(河) | 눈 |
| 회(淮) | 코 |
| 제(濟) | 입 |

### 4.4 십이궁(十二宮) — 인생 영역 매핑

| 궁 | 노드 |
|---|---|
| 명궁 | 미간 |
| 재백궁 | 코 전체 |
| 형제궁 | 눈썹 |
| 전택궁 | 눈(상안검) |
| 남녀궁 | 눈(와잠) |
| 노복궁 | 턱 |
| 처첩궁 | 눈(눈꼬리) |
| 질액궁 | 코(산근) |
| 천이궁 | 이마(양측) |
| 관록궁 | 이마(중앙) |
| 복덕궁 | 이마·턱 균형 (cross-node overlay) |
| 상모궁 | 얼굴 전체 (cross-node overlay) |

> **복덕궁·상모궁**은 leaf 노드가 아니라 "여러 노드 간 균형" 을 보는 메타 개념.
> 트리 노드로 표현하지 않고 root-level aggregation 으로 처리.

---

## 5. 현대 과학 교차 검증

| tree 층 | 전통 근거 | 현대 근거 |
|---|---|---|
| 삼정 3분할 | 마의상법 卷一 | Farkas 네오클래식 수직 3등분 캐논 |
| 이마·눈·코·입·턱 독립 노드 | 오관 + 卷二 부위 순회 | Todorov(sellion·chin), Zebrowitz(forehead·eye·chin) |
| 눈썹 독립 | 오관.보수관 | FACS AU1~4, BiSeNet brow 독립 레이블 |
| 코 frontal+lateral 통합 | 오악.숭산 | Farkas 비부(nasal) 영역 |
| 귀 독립 | 오관.채청관, 사독.江 | Farkas 이부 / Todorov·Zebrowitz 경시 — ⚠️ 불일치 |

**일관된 수렴**: 이마·눈썹·눈·코·입·턱 은 전통·현대 모두 독립 분석 단위로 수렴.

**불일치 지점**:
- **귀** — 전통 중시 vs 현대 경시 + MediaPipe 기술 제약 → v1.0 미지원.
- **이마** — 전통·Zebrowitz 지지 vs BiSeNet 은 skin 에 포함 → 독립 노드 유지.
- **인중** — 전통 중요 vs 현대 CV 독립 레이블 없음 → 독립 노드 유지.

---

## 6. 참고 문헌

### 전통 관상서
- 마의상법(麻衣相法) 5권 — 북송. 출처: 百度百科, 국학대사, 微信読書
- 유장상법(柳莊相法) 3권 — 명대 원충철. 출처: 中华典藏, 豆瓣
- 신상전편(神相全編) / 수경집(水鏡集) 4권 — 명말청초. 출처: Chinese Text Project, 書格

### 한국어 2차 자료
- 한국민족문화대백과 "관상" 항목 — https://encykorea.aks.ac.kr/Article/E0004873
- 오서연, 관상 이야기 시리즈 (US Journal)
- 성대신문 "십이궁부터 공부하라"
- 경인일보 "사독·육요"

### 현대 얼굴 과학
- Farkas LG. *Anthropometry of the Head and Face* (Raven Press, 1994)
- Todorov A. *Face Value* (Princeton, 2017)
- Zebrowitz LA. *Reading Faces* (1997)
- Oosterhof & Todorov 2008, PNAS — https://www.pnas.org/doi/10.1073/pnas.0805664105
- BiSeNet / CelebAMask-HQ face parsing — https://github.com/switchablenorms/CelebAMask-HQ
- FACS (Ekman & Friesen, 1978+) — https://www.paulekman.com/facial-action-coding-system/

---

## 7. 이 문서 업데이트 규칙

- 트리 자체 변경은 **대부님 승인 필수** (전체 리팩터의 뿌리 SSOT).
- 새 노드 추가 시 본 문서 먼저 업데이트 → 그 다음 코드.
- 메타데이터(오관/오악/사독/십이궁) 태그 변경 시 근거 소스 명시.
- 노드 metric 매핑은 `TAXONOMY_METRIC_MAPPING.md` 에서 관리 (본 문서는 체계 정의만).

---

## 8. 구현 노트 (Phase 1A/1B 완료, 2026-04-18)

- 코드 SSOT: `flutter/lib/domain/models/physiognomy_tree.dart`
- sanity 테스트: `flutter/test/physiognomy_tree_sanity_test.dart` (11/11 통과)
- **Tree 밖 classifier 전용 feature** (Track 1 TFLite 의 28-feature 입력 구성 용):
  `eyebrowLength`, `browSpacing`, `noseBridgeRatio` — `computeAll()` 은 이 3개를
  계속 계산하지만 tree·metricInfoList·해석 규칙에는 포함하지 않는다.
  Track 1 classifier 재학습 없이 tree 리팩터를 진행하기 위한 분리 경계.
- 신규 정규화 7 metric: `foreheadWidth`, `cheekboneWidth`, `chinAngle`, `eyeAspect`,
  `eyebrowCurvature`, `eyebrowTiltDirection`, `upperVsLowerLipRatio`.
  East Asian MediaPipe-추정 mean/sd 를 6 인종에 동일 fallback (lateral 패턴 참조).
  empirical 측정 누적 시 per-ethnicity 보정 예정.
