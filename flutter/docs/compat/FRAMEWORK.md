# 궁합 엔진 — 전통 관상학 5 프레임 SSOT

**마지막 업데이트**: 2026-04-21 · 엔진 v1 설계
**역할**: `lib/domain/services/compat/` 하위 신규 엔진의 단일 설계 근거. 本 문서가 모든 sub-score·rule·phrase·narrative 의 진본이다.

---

## 0. 왜 관상 엔진과 분리하는가

관상 엔진(`analyzeFaceReading`)은 **1 인 → 해석** 의 SSOT — 17/8 metric · 14 node · 10 attribute · archetype · 62 rule · narrative 까지 1-인 세계가 닫혀 있다. 궁합 엔진은 **(FaceReadingReport × FaceReadingReport) → 관계 해석** 이라는 전혀 다른 형상의 함수로, 입력 cardinality·MC sampler·invariant·narrative seed 가 모두 다르다. 겹치게 두면 관상 node tree 가 compat 전용 개념(12 궁 state, 五行 label)을 알아야 하게 되어 책임이 흩어진다. 궁합 엔진은 **관상 엔진이 만든 raw evidence(metrics · lateral · nodeScores · faceShape) 만 읽고**, 이미 해석된 attribute/archetype/rules 는 의존하지 않는다 — 해석된 값 위에 또 해석을 얹으면 double-interpretation.

---

## 1. 5 프레임 summary

| # | 프레임 | 출전 | 관여 metric/node | 산출물 |
|---|---|---|---|---|
| L1 | **五行 (오행)** 체형 상생상극 | 麻衣相法 「相法賦·五形」· 神相全編 「五形形格」 | 얼굴형 metric 7 개 + faceShape preset | `FiveElements(primary, secondary, confidence)` × 2 → `ElementRelation` |
| L2 | **十二宮 (십이궁)** palace state pair | 柳莊相法 · 神相全編 「十二宮」· 水鏡集 | 17 frontal + 8 lateral 의 ~22 개 | `Map<Palace, PalaceState>` × 2 → `List<PalacePairEvidence>` |
| L3a | **五官 (오관) 1:1 조합** | 神相全編 「五官總論」 | 眉 · 目 · 鼻 · 口 node + sub-metric | `List<OrganPairEvidence>` |
| L3b | **三停 (삼정) 合刑** | 삼정 전통 | upper/mid/lowerFaceRatio · 삼정 zone score | `ZoneHarmony` |
| L3c | **陰陽 剛柔 balance** | 음양론 | 기존 `YinYangBalance` + gonialAngle · cheekboneWidth · lipFullnessRatio | `YinYangMatch` |

각 frame 은 **독립 sub-score (0~100) + evidence list** 를 산출하며, Aggregator (§8) 가 4 sub-score → 총점 + label 로 수렴한다. Narrative 엔진은 frame 별로 섹션을 구성.

---

## 2. L1 — 五行 체형 분류기

### 2.1 五形 의미와 전통 서술

| 五形 | 한글 | 체형 표상 | 전통 성격 (簡) | 주요 이점 | 약점 |
|---|---|---|---|---|---|
| 木形 | 목형 | 길쭉·마른·骨格 선명, 상정 길고 중·하정 얇음 | 강직·청렴·지식욕 | 학문·사상 | 고독·완고 |
| 火形 | 화형 | 三角 / 顴骨 突, 아래 뾰족, 수염·체모 짙음 | 열정·급함·야심 | 추진력·개혁 | 성급·충돌 |
| 土形 | 토형 | 두툼·방정·厚重, 볼살·중정 풍부 | 신의·근면·포용 | 재물·장수 | 둔함 |
| 金形 | 금형 | 方形·각진·骨硬 白皙, 상하 균형 | 의리·결단·청렴 | 관록·결혼 수 | 냉정·비정 |
| 水形 | 수형 | 둥글·살집·부드러움, 하정 풍부 | 유연·총명·욕정 | 사교·재물 | 나태·음란 |

출전 요지: 木主仁 · 火主禮 · 土主信 · 金主義 · 水主智 (麻衣 五形總論).

### 2.2 五形 score 공식 (0~100 each, sum 정규화 후 top-2 선택)

각 型 의 score 는 **metric z-score 의 weighted sum → softmax 후 0~100 normalize**. 아래 weight 는 P2 초기값, MC 분포로 ±5% 범위 보정.

```
wood =  +1.3 * z(faceAspectRatio)     // 長
        -0.8 * z(lowerFaceRatio)      // 하정 축소
        +0.6 * z(foreheadWidth)       // 상정 돌출
        -0.7 * z(cheekboneWidth)      // 볼 마름
        +0.4 * z(browEyeDistance)     // 이마 길이
        -0.5 * z(lipFullnessRatio)    // 얇은 입술

fire =  +1.1 * z(gonialAngle)         // 하정 뾰족 (각 좁음↓ → weight 로는 angle 큼)
        -0.9 * z(lowerFaceRatio)      // 하정 축소
        +0.9 * z(cheekboneWidth)      // 顴骨 突
        -0.6 * z(faceAspectRatio)     // 삼각
        +0.5 * z(eyebrowThickness)    // 濃眉
        +0.4 * z(eyeCanthalTilt)      // 上揚

earth = -1.1 * z(faceAspectRatio)     // 짧고 넓음
        +1.0 * z(cheekboneWidth)      // 厚
        +0.9 * z(lowerFaceRatio)      // 하정 풍부
        +0.7 * z(nasalWidthRatio)     // 코 두꺼움
        +0.5 * z(lipFullnessRatio)
        -0.4 * z(gonialAngle)         // 부드러운 턱각

metal = -0.2 * z(faceAspectRatio)     // 정사각 근처
        -1.1 * z(gonialAngle)         // 각진 턱각
        +0.8 * z(faceTaperRatio)      // 방정
        +0.6 * z(foreheadWidth)
        -0.4 * z(lipFullnessRatio)
        +0.5 * z(browEyeDistance)
        +0.3 * z(philtrumLength)

water = -1.0 * z(faceAspectRatio)     // 둥글
        +1.0 * z(lowerFaceFullness)   // 살집
        +0.8 * z(lipFullnessRatio)
        -0.9 * z(faceTaperRatio)      // taperRatio 낮음 = 둥글
        +0.5 * z(eyeFissureRatio)
        +0.4 * z(mouthWidthRatio)
```

Stage-0 face shape preset 이 확정된 경우 (`faceShapeConfidence >= 0.6`) 다음 boost 추가:
- `oblong` → wood +15, metal +5
- `heart` → fire +15, wood +3
- `round` → water +18, earth +5
- `square` → metal +20, earth +3
- `oval` → earth +8, water +5 (mild — oval 은 五行 mix 경향)

### 2.3 primary / secondary / confidence

정규화 후 top-2 을 `FiveElements(primary, secondary)` 로, confidence = `(top1 - top2) / top1` (0~1). `confidence < 0.08` 이면 secondary 를 같은 row 에 기록하되 narrative 는 "겸형(兼形)" 표현 사용.

### 2.4 五行 상생상극 matrix (5×5, base score 50)

상생(生) 고리: 木 → 火 → 土 → 金 → 水 → 木
상극(剋) 대각: 木 克 土 · 土 克 水 · 水 克 火 · 火 克 金 · 金 克 木

| A \ B | 木 | 火 | 土 | 金 | 水 |
|---|---|---|---|---|---|
| 木 | **比和 50** | 生 +20 → **70** | 剋 -22 → **28** | 被剋 -18 → **32** | 被生 +15 → **65** |
| 火 | 被生 +15 → **65** | **比和 45** (열 충돌) | 生 +22 → **72** | 剋 -20 → **30** | 被剋 -25 → **25** |
| 土 | 被剋 -22 → **28** | 被生 +18 → **68** | **比和 55** | 生 +22 → **72** | 剋 -18 → **32** |
| 金 | 剋 -20 → **30** | 被剋 -25 → **25** | 被生 +20 → **70** | **比和 48** | 生 +22 → **72** |
| 水 | 生 +18 → **68** | 剋 -25 → **25** | 被剋 -22 → **28** | 被生 +22 → **72** | **比和 42** (유약) |

`比和` (같은 五形) 은 base 40~55 에 성·기질 합치 boost. `tension` 이 아닌 `redundancy` 문제 — primary·secondary 교차 분석으로 세분화 (§2.5).

### 2.5 secondary overlay

primary×primary matrix 로 base score → secondary 반영 blend:

```
elementScore = 0.70 * matrix[myPrimary][albumPrimary]
             + 0.15 * matrix[myPrimary][albumSecondary]
             + 0.15 * matrix[mySecondary][albumPrimary]
             + 0.05 * (matrix[mySecondary][albumSecondary] - 50)
// clamp 5~99
```

confidence 낮을 때(< 0.08) secondary weight 를 0.15 → 0.20 으로 소폭 증가 (겸형일수록 secondary 가 의미 큼).

### 2.6 五形 전통 verdict 조각 (phrase pool 원자재)

phrase pool 의 `element` 카테고리에 frame 별 2~5 개 variant.

- 木生火: "木火通明 — 지식이 열정을 만나 큰 그림이 타오릅니다."
- 火生土: "火土相生 — 추진과 신의가 맞물려 실행의 바퀴가 구릅니다."
- 土生金: "土金相合 — 결실을 거두는 조합, 재물과 관록이 함께 빛납니다."
- 金生水: "金水相涵 — 의리와 지혜가 어우러져 富貴旺相 의 전형입니다."
- 水生木: "水木清華 — 총명이 성장의 양분이 되는 長流형 관계."
- 木剋土: "木重土虛 — 이상이 현실을 눌러 생활의 뿌리가 흔들립니다."
- 土剋水: "厚土塞流 — 현실 무게가 총명과 유연을 덮을 수 있습니다."
- 水剋火: "水淹烈火 — 열정이 식는 조합, 자극이 잠기는 위험."
- 火剋金: "火灼秋金 — 의리가 충동에 녹아 관계가 거칠어질 여지."
- 金剋木: "金斷枯木 — 강직끼리 부딪혀 부러지는 파열음."
- 兩木 / 兩火 / 兩水: 각 比和 의 고유 문장 (§6 phrase pool 에 변주 3~5).

---

## 3. L2 — 十二宮 palace state pair engine

### 3.1 12 궁 위치 · 의미 · metric 매핑

공식 위치는 `docs/engine/TAXONOMY.md` 의 14-node 와 교차. 매핑은 신상전편 표준 + 관상 엔진에 이미 존재하는 node score 를 우선 재활용.

| # | 궁 | 위치 | 전통 의미 | 주된 metric / node | 결혼 중요도 |
|---|---|---|---|---|---|
| 1 | **命宮** | 印堂 (미간) | 일생의 根幹 · 기개 | `browSpacing` or `intercanthalRatio` · node:`glabella` | ★★★ (사상 호응) |
| 2 | **財帛宮** | 코 전체 (準頭·蘭台·廷尉) | 재물 · 축적 능력 | `nasalWidthRatio` · `nasalHeightRatio` · `noseTipProjection` · node:`nose` | ★★ |
| 3 | **兄弟宮** | 눈썹 (眉) | 형제애 · 동료 운 | `eyebrowThickness` · `browEyeDistance` · node:`eyebrow` | ★ |
| 4 | **田宅宮** | 눈과 눈썹 사이 · 상안검 | 주거 · 가정 안정 | `browEyeDistance` · `eyeFissureRatio` (높이) | ★★ |
| 5 | **男女宮** | 누당 · 눈 아래 와잠 | 자녀 · 성적 매력 | `eyeFissureRatio` · `eyeCanthalTilt` · node:`eye` · lateral `lowerLipEline` | ★★★ (자녀·애정) |
| 6 | **奴僕宮** | 지각 · 턱 옆 (地閣 兩側) | 부하 · 인맥 · 교우 | `lowerFaceRatio` · `gonialAngle` · `lowerFaceFullness` · node:`chin` | ★ |
| 7 | **妻妾宮 (夫妻宮)** | 魚尾 (눈꼬리 옆 奸門) | 배우자 · 부부 궁합 | `eyeCanthalTilt` · `browEyeDistance`(outer) · lateral `upperLipEline` 주변 | ★★★★ (최핵심) |
| 8 | **疾厄宮** | 山根 (nose root, 비근) | 건강 · 저항력 | lateral `nasofrontalAngle` · `dorsalConvexity` (산근 깊이) · `intercanthalRatio` | ★ |
| 9 | **遷移宮** | 驛馬 (이마 옆 끝) | 이주 · 외출 운 | `upperFaceRatio` · `faceAspectRatio` · node:`forehead` outer | — |
| 10 | **官祿宮** | 중정 (이마 중앙) | 관운 · 직업 · 사회적 지위 | `upperFaceRatio` · `foreheadWidth` · node:`forehead` center | ★ |
| 11 | **福德宮** | 天倉 (이마 위 좌우) | 복 · 덕 · 정신적 평온 | `upperFaceRatio` · `browEyeDistance` · node:`glabella` 주변 | ★★ (공통 가치관) |
| 12 | **父母宮** | 日角·月角 (이마 위 좌우) | 부모 운 · 조상 음덕 | `upperFaceRatio` 좌·우 asymmetry · `foreheadWidth` | — |

**결혼 중요도 weight**: 妻妾 0.28 · 男女 0.22 · 命 0.15 · 田宅 0.13 · 福德 0.12 · 財帛 0.05 · 奴僕 0.03 · 疾厄 0.01 · 兄弟/官祿/遷移/父母 각 < 0.01.
합 = 1.00, normalize 후 PalacePair aggregator 에 주입.

### 3.2 PalaceState 계산

각 궁의 state 는 **3 단계 (weak/balanced/strong) + 최대 2 개 sub-flag**. weak/strong 의 경계는 `|z| ≥ 1.0` (중심 metric 의 평균 z 기준), sub-flag 는 전통적으로 이름이 붙어있는 돌출 feature.

```
PalaceState(
  palace: Palace.spouse,
  level: Level.weak | balanced | strong,
  zMean: double,          // 해당 궁 관여 metric 의 평균 z
  absZMax: double,        // 가장 극단 metric 의 |z|
  flags: Set<PalaceFlag>, // e.g. {fishTailWrinkle, auspiciousGlow, deepScar}
)
```

**대표 sub-flag 예시**:
- `命宮`: `glabellaBright` (미간 넓·깨끗), `glabellaTight` (미간 좁음 → 옹졸), `scarOrDent`
- `財帛宮`: `bulbousTip` (코끝 복스럽), `hookedNose` (매부리), `thinBridge`
- `男女宮`: `plumpLowerEyelid` (와잠 통통), `hollowLowerEyelid` (함몰 → 자녀궁 약)
- `妻妾宮`: `smoothFishTail` (매끈), `fishTailWrinkle` (魚尾紋 많음 → 부부 불화)
- `疾厄宮`: `sanGenHigh` (산근 높음 → 건강 양호), `sanGenLow` (함몰 → 질병궁 약)
- `福德宮`: `cloudlessForehead` (이마 밝고 평탄), `dentedTemple` (天倉 함몰)

sub-flag 매핑은 P3 에서 metric z 와 lateral flag 조합으로 산출 (예: `fishTailWrinkle` 은 `eyeCanthalTilt` |z| 고 + age_group 30+ 조합, `sanGenLow` 는 lateral `nasofrontalAngle` z<-1).

### 3.3 PalacePair rule 카탈로그

**PP-## rule** — 두 사람의 같은 궁을 비교한 rule. 총 12 궁 × 최대 6 패턴. 각 rule 은 `(myLevel, albumLevel, sub-flag 조합)` → `delta` + 전통 verdict comment.

대표 rule (P3 초기 카탈로그, 총 ~40 개 목표):

| id | 조건 | delta | 전통 verdict |
|---|---|---|---|
| `PP-SP-SS` | 妻妾 둘 다 strong · smoothFishTail | +22 | "魚尾清潤 — 부부궁이 거울처럼 밝아 금슬이 종신토록 빛납니다." |
| `PP-SP-SW` | 妻妾 한 쪽 strong · 한 쪽 weak | +6 | 보완 — 강한 쪽이 약한 쪽의 외정을 단속. |
| `PP-SP-WW` | 妻妾 둘 다 weak · fishTailWrinkle | -24 | "魚尾紋交 — 눈꼬리 잔주름이 서로를 스쳐 부부의 정이 스칩니다." |
| `PP-MW-SS` | 男女(자녀) 둘 다 strong · plumpLowerEyelid | +18 | "淚堂飽滿 — 자녀운이 겹쳐 혈육의 경사가 기대됩니다." |
| `PP-MW-WW` | 男女 둘 다 weak · hollowLowerEyelid | -18 | "淚堂皆陷 — 가정의 따뜻함이 엷어 자녀·친밀의 인연이 박합니다." |
| `PP-MG-BOTH_BRIGHT` | 命宮 둘 다 strong · glabellaBright | +16 | "印堂雙明 — 사상이 통해 일상의 대화에서도 빛이 납니다." |
| `PP-MG-BOTH_TIGHT` | 命宮 둘 다 weak · glabellaTight | -20 | "印堂雙結 — 두 사람 모두 속을 꽉 묶어 답답함이 증폭됩니다." |
| `PP-FG-BOTH_OPEN` | 福德 둘 다 strong · cloudlessForehead | +14 | "天倉雙開 — 복과 덕이 나란히 흘러 풍요로운 공간을 만듭니다." |
| `PP-FG-BOTH_DENT` | 福德 둘 다 weak · dentedTemple | -12 | "天倉俱陷 — 가정의 여유가 메말라 사소한 일이 크게 닳습니다." |
| `PP-TH-SS` | 田宅 둘 다 strong | +10 | "田宅厚潤 — 사는 공간이 두 사람의 바탕이 됩니다." |
| `PP-WE-SS` | 財帛 둘 다 strong · bulbousTip | +10 | "準頭齊豊 — 재운의 축이 나란히 서 경제 파트너십에 유리." |
| `PP-WE-SS-HOOKED` | 財帛 둘 다 strong · hookedNose 겹침 | -8 | "雙鉤相照 — 재운은 강하나 사람을 향한 이득 계산이 충돌." |
| `PP-IL-BOTH_LOW` | 疾厄 둘 다 weak · sanGenLow | -8 | "山根雙陷 — 건강·중년 고비에 동시 약점, 서로를 염려해야." |
| `PP-OF-SS` | 관록 둘 다 strong | +6 | "中正朗朗 — 사회적 보폭이 비슷해 자부심이 교차." |
| `PP-OF-CLASH` | 관록 한 쪽 strong / 한 쪽 weak | -4 | 사회적 높낮이 차로 자존심 대립 여지. |
| … | 총 ~40 rule (P3 카탈로그) | | |

### 3.4 PalacePair sub-score 계산

```
for each Palace p:
    state_my = PalaceState(my, p)
    state_album = PalaceState(album, p)
    fired = matchPalaceRules(p, state_my, state_album)   // List<PPRuleEvidence>
    palaceDelta[p] = sum(r.delta for r in fired)

baseline = 50
palaceTotal = baseline + Σ_p palaceDelta[p] * weight[p]
palaceSubScore = clamp(palaceTotal, 5, 99)
```

`weight[p]` 은 §3.1 결혼 중요도. rule delta 는 cap ±25 (step-function dominance 방지 — 관상 엔진 v2.7 rule cap 0.5 와 동일 원리, 단 compat 은 delta range 큼).

---

## 4. L3a — 五官 1:1 조합 rule

眉 · 目 · 鼻 · 口 4 organ 을 1:1 비교. `耳` 는 현 metric 불충분으로 skip. organ pair 는 **patternKey → phrase + delta** table.

### 4.1 眉 pair (nodes:eyebrow, `eyebrowThickness` · `browEyeDistance`)

- `bothThick_thick`: 둘 다 濃眉 → 기질 충돌 경고 (`-6`) · "雙濃相對 — 의지 둘이 맞부딪혀 불꽃이 잦습니다."
- `thick_thin`: 한쪽 濃·한쪽 淡 → 주도권 분담 (`+12`) · "一濃一淡 — 이끄는 이와 따르는 이의 호흡."
- `bothBalanced`: 평균 근처 → `+4`
- `bothThin_bright`: 둘 다 淡眉 + browEyeDistance 넓음 → 냉정 균형 (`+8`)
- `hookBrow_both`: 눈썹 결이 흐트러짐 (eyebrowThickness z>1.2 양쪽) → `-8`

### 4.2 目 pair (node:eye, `eyeFissureRatio` · `eyeCanthalTilt` · `lipFullnessRatio` → 복합 의미 주의)

- `fenghuang_vs_taohua` (鳳眼 × 桃花眼): my `eyeCanthalTilt z ≥ 0.8` × album `lipFullnessRatio z ≥ 0.8` OR 반대 → `+24` · "鳳配桃花 宜室宜家 — 단단한 눈매와 촉촉한 입술이 가장 조화로운 조합."
- `both_dragon` (龍眼): 둘 다 `eyeFissureRatio z>0.7` + `eyeCanthalTilt 중간` → `+16` · "雙龍相對 — 기개 있는 눈끼리 서로 인정."
- `both_peach` (桃花 ×桃花): 둘 다 `lipFullnessRatio z>1.0` + eyeCanthalTilt z>0.5 → `+6` (초반 끌림) 장기 `-8` (경쟁) → net delta 동적, comment 로 양면 강조.
- `drooping_both` (懶眼): 둘 다 `eyeCanthalTilt z<-0.8` → `-10` · "雙凴眼 — 무기력이 겹쳐 관계 온도가 식습니다."
- `sharp_vs_soft`: 한쪽 `sharp` (tilt>+0.8, fissure z<-0.3 좁고 올라감) × 한쪽 `soft` (tilt<-0.3, 둥근 눈) → `+14` · 상보.

### 4.3 鼻 pair (node:nose, `nasalWidthRatio` · `nasalHeightRatio` · lateral `noseTipProjection` · lateral `dorsalConvexity`)

- `both_high_bridge`: 둘 다 `noseTipProjection z>1.0` + `nasalHeightRatio z>0.8` → `-6` · "雙峰對峙 — 재운은 강하나 주도권 비슷해 충돌 여지."
- `high_vs_modest`: 한쪽 高 · 한쪽 低 → `+10` · 경제 주도 분담.
- `aquiline_aquiline`: 둘 다 `aquilineNose` flag → `-10` · 두 매부리.
- `aquiline_snub`: 한쪽 aquiline · 한쪽 snubNose → `+8` · 자극적 상보.
- `garlic_tip_bulbous`: 둘 다 `nasalWidthRatio z>0.8` (蒜頭鼻) → `+14` · "雙蒜齊立 — 소박하고 끈기 있는 재물 궁합."
- `thin_both`: 둘 다 `nasalWidthRatio z<-0.8` → `-8` · "雙刀鼻 — 계산적 강박 겹침."

### 4.4 口 pair (node:mouth, `mouthWidthRatio` · `lipFullnessRatio` · `mouthCornerAngle`)

- `both_full_lip`: 둘 다 `lipFullnessRatio z>1.0` → `+10` · 감각적 공명.
- `big_vs_small`: `mouthWidthRatio` 차 ≥ 1.5 sigma → `+8` · "一大一小 — 말하는 이와 듣는 이."
- `both_wide_smile`: 둘 다 `mouthCornerAngle z>0.5` → `+14` · "雙笑迎門 — 일상 행복도 상승."
- `both_corner_down`: 둘 다 `mouthCornerAngle z<-0.5` → `-10` · "雙角下垂 — 침묵의 벽."
- `cherry_small_both`: 둘 다 입 작고 얇음 → `-4` (표현 위축).

### 4.5 aggregate

```
organSubScore = 50
             + Σ_organ clamp(Σ ruleDelta_organ, -28, +28) * organWeight
// organWeight: eye 0.34, mouth 0.26, nose 0.24, brow 0.16
// clamp 5~99
```

---

## 5. L3b — 三停 (삼정) 合刑

상정 (智) · 중정 (意) · 하정 (情) 세 zone 각각의 **우세 여부** (strong / balanced / weak) 를 산출하여 pair matching.

### 5.1 zone state 산출

각 zone score = node-tree 의 해당 zone 평균 z (e.g. 상정 = forehead+glabella node ownMeanZ 평균). `z_mean ≥ +0.6` → strong, `≤ -0.6` → weak, 그 외 balanced.

### 5.2 matching pattern table (3 zone × 3^2 = 9 pattern per zone, 총 81 조합 중 주요 ~20)

| pattern | 의미 | delta |
|---|---|---|
| `upper_both_strong` | 이상·학문 합치 | +10 |
| `upper_one_strong` | 이상가 + 실용가 보완 | +6 |
| `upper_both_weak` | 사상 동기 빈약 | -6 |
| `mid_both_strong` | 의지 충돌 (양강) | -4 |
| `mid_one_strong` | 의지 주도-조력 | +12 |
| `lower_both_strong` | 정·애정 공명 | +14 |
| `lower_both_weak` | 애정 표현 빈곤 | -10 |
| `upper_strong_lower_strong_cross` | 한 명 上 우세 × 한 명 下 우세 | +16 · "이상·현실 상호 보완" |
| `all_zone_mirror` | 세 zone 양쪽 모두 서로 닮음 | +8 · 공유 가치관 |
| `all_zone_complement` | 세 zone 이 서로 정반대 | +12 · 드라마틱 상보 |

합: `zoneDelta = clamp(Σ patternDelta, -24, +30)`.

---

## 6. L3c — 陰陽 剛柔 balance

`YinYangBalance` 축 기존 계산기 재활용. pair matching 은 축의 상대 위치로:

- `yangHeavy_yinHeavy`: 한 명 강한 陽 (+1.2σ 이상) × 한 명 강한 陰 (-1.2σ 이하) → `+18` (古典 理想)
- `yangHeavy_yangHeavy`: 둘 다 강한 陽 → `-12`
- `yinHeavy_yinHeavy`: 둘 다 강한 陰 → `-8`
- `balanced_pair`: 둘 다 중앙 → `+2`
- `yang_balanced` / `yin_balanced`: 한 명 중앙 → `+6`

보조: **性別과의 정합**. 남 → 陽 기대, 여 → 陰 기대. 전통 기대 반대일 때 (남 陰 · 여 陽) 는 **modern pattern** 으로 해석 — `-4` 이지만 narrative 에 "역할 현대적 교차" 표현 (낙인 아님).

---

## 7. L3a + L3b + L3c 합산 → `氣質合` sub-score

```
qi_score = 50
        + 0.55 * organDelta     // L3a
        + 0.25 * zoneDelta      // L3b
        + 0.20 * yinYangDelta   // L3c
// clamp 5~99
```

---

## 8. Aggregator — 4 sub-score → 총점 + label

4 sub-score:

| sub | 이름 | L | weight (총점 반영) |
|---|---|---|---|
| `elementScore` | 五形和 | L1 | **0.20** |
| `palaceScore` | 宮位調 | L2 | **0.40** |
| `qiScore` | 氣質合 | L3 | **0.25** |
| `intimacyScore` (별도, §9) | 性情諧 | 男女+妻妾+lip+eye tilt 교차 | **0.15** |

총점:

```
rawTotal = 0.20 * elementScore
         + 0.40 * palaceScore
         + 0.25 * qiScore
         + 0.15 * intimacyScore

// spread 유지 — 중앙 편향 해소
deviation = rawTotal - 50
total = clamp(50 + deviation * 1.4, 5, 99)
```

### 8.1 label 4 tier

MC 20k (seed=42) pair 분포의 p-percentile 로 경계 재보정 (P5). 초기 목표 분포 — **10% / 30% / 30% / 30%**:

| label | 한자·뜻 | 분포 목표 | 경계 (MC 재보정 대상) |
|---|---|---|---|
| `天作之合` | 천작지합 (하늘이 맺음) | 10% | total ≥ ~85 |
| `相敬如賓` | 상경여빈 (서로 존중) | 30% | ~72 ~ 85 |
| `磨合可成` | 마합가성 (갈아 맞추면 됨) | 30% | ~58 ~ 72 |
| `刑剋難調` | 형극난조 (상극 조율 어려움) | 30% | < ~58 |

### 8.2 invariant (회귀 차단 게이트)

1. **4 sub-score 분포**: 각 sub-score 의 MC p10~p90 spread ≥ 25 (단조 flat 방지).
2. **label fairness**: MC 20k 기준 10/30/30/30 ± 5%.
3. **pair-symmetric invariance**: `compat(A, B).total == compat(B, A).total` (대칭). sub-score 는 일부 비대칭(眉 패턴 등) 허용.
4. **element matrix sanity**: 相剋 평균 total < 比和 평균 < 相生 평균 (MC 샘플).
5. **no single rule dominance**: palace rule 하나의 delta 가 palace sub-score 의 `|Δ|` 30% 이상 차지 금지 (rule cap ±25 로 강제됨).
6. **attribute/archetype 미의존**: `analyzeCompatibility` 는 `FaceReadingReport.attributes / rules / archetype` 를 읽지 않음 (lint test 로 import 검증).

---

## 9. 性情諧 (intimacy) sub-score

**남녀 30~50대 opposite-gender** 게이트 통과 시만 fire. 그 외는 `intimacyScore = 50` (중립, 총점 반영 최소).

재료 metric:
- `男女宮` state · `妻妾宮` state (§3)
- `lipFullnessRatio` · `mouthCornerAngle` (입가 감각)
- `eyeCanthalTilt` · lateral `upperLipEline` / `lowerLipEline` (Ethel profile)
- `philtrumLength` (정열 · 관능)

`intimacyScore` 계산:

```
intimacy = 50
         + fn_maleFemaleGong  // 男女宮 pair delta  (범위 ±18)
         + fn_cheopgung       // 妻妾宮 pair delta  (±18)
         + fn_lipGeometry     // lip pair + philtrum (±14)
         + fn_eyeCharisma     // eye tilt + yin-yang (±10)
// clamp 5~99
```

narrative 섹션 「情性之合」 에서만 노출. 同性 pair 또는 연령 이탈 시 `intimacyScore = 50` · 해당 섹션 숨김.

---

## 10. CompatibilityReport 스키마 (v1)

```dart
class CompatibilityReport {
  static const int kCompatSchemaVersion = 1;
  final int schemaVersion;

  // 입력 식별자
  final String myReportId;      // FaceReadingReport.supabaseId
  final String albumReportId;
  final DateTime evaluatedAt;

  // L1
  final FiveElements myElement;
  final FiveElements albumElement;
  final ElementRelation elementRelation;   // 生/比和/剋 label + 점수

  // L2
  final Map<Palace, PalaceState> myPalaces;
  final Map<Palace, PalaceState> albumPalaces;
  final List<PalacePairEvidence> palaceMatches;

  // L3
  final List<OrganPairEvidence> organMatches;
  final ZoneHarmony zoneHarmony;
  final YinYangMatch yinYangMatch;

  // L4 (intimacy)
  final IntimacyEvidence intimacy;         // gate 통과 여부 + 하위 evidence

  // aggregate
  final CompatSubScores sub;               // 4 개 sub-score
  final double total;                      // 5~99
  final CompatLabel label;                 // 天作之合 / 相敬如賓 / 磨合可成 / 刑剋難調

  // narrative (pair-hash seed, load 시 재계산)
  final CompatNarrative narrative;
}
```

**Capture-only 원칙**: Hive 에 저장하는 건 `myReportId` · `albumReportId` · `evaluatedAt` · `schemaVersion` 뿐. 나머지(element/palace/organ/zone/yinyang/intimacy/narrative) 는 load 시 두 FaceReadingReport 로부터 재계산. 엔진 버전 업은 Hive 건드리지 않음.

---

## 11. Narrative 엔진 (L4 phase P6)

섹션 6 개 · pair-hash seed 로 variant 선택.

| # | 섹션 | 주 재료 | 길이 목표 |
|---|---|---|---|
| 1 | **총평** (overview) | total label + 4 sub-score snapshot | 180~280자 |
| 2 | **五形相配** | L1 element matrix + 전통 verdict | 200~320자 |
| 3 | **宮位照應** | L2 주요 PP 발동 rule (top 3) + 전통 verdict | 260~400자 |
| 4 | **氣質合章** | L3 organ + zone + yinyang, 가장 특이 1~2 pattern | 240~360자 |
| 5 | **情性之合** (gate: 30~50 opposite) | L4 intimacy evidence | 200~320자 |
| 6 | **長久之道** (long-term + 조언) | stability/trust 대응하는 node pair + label-기반 advice | 220~320자 |

**phrase pool (`compat_phrase_pool.dart`)**:
- `elementRelationPhrases`: 25 relation × 각 3~5 variant
- `palaceRulePhrases`: 각 PP rule 마다 1~3 variant (id → list)
- `organPairPhrases`: 각 organ pattern 마다 2~4 variant
- `zonePatternPhrases`: 20 pattern × 각 2 variant
- `yinYangPhrases`: 5 pattern × 3 variant
- `intimacyPhrases`: 4 axis × 각 3 variant
- `labelOverviewPhrases`: 4 label × 각 5 variant (총평 opener)
- `longTermAdvicePhrases`: label + stability 조합

**variant seed**: `pairHash = hash(myReportId) * 31 + hash(albumReportId)` 고정. 동일 pair 재평가 시 동일 문장 (결정적).

---

## 12. 레퍼런스

- **麻衣相法** (麻衣道者) — 相法賦·五形總論·十二宮
- **神相全編** (陳摶 輯) — 五官總論·十二宮解·相法妙訣
- **柳莊相法** (袁珙) — 婚姻宮·六親宮 해석
- **水鏡集** (范仲淹傳) — 陰陽剛柔 매칭
- 現代 綜合: 陳鼎龍 「面相學·婚姻篇」, 石井一考 「顔相と結婚運」

Online refs (초기 research 경로):
- [Mien Shiang - Wikipedia](https://en.wikipedia.org/wiki/Mien_Shiang)
- [Chinese Face Reading Chart (mysticaleast)](https://mysticaleast.net/chinese-face-reading-chart-complete-guide/)
- [Merigold — Chinese Face Mapping](https://merigold.co/blogs/news/learning-about-chinese-face-mapping)
- [面相十二宮詳解 (lnka.tw)](https://www.lnka.tw/html/topic/1586.html)
- [Mysterious East — Complete Guide](https://mysticaleast.net/chinese-face-reading-chart-complete-guide/)

---

## 13. 구현 체크리스트 (P2~P7)

| Phase | 산출 파일 | 이 문서의 § 에 해당 |
|---|---|---|
| **P2** | `element_classifier.dart`, `element_matrix.dart` | §2 (L1) |
| **P3** | `palace_state.dart`, `palace_pair_matcher.dart`, `palace_rules.dart` | §3 (L2) |
| **P4** | `organ_pair_rules.dart`, `zone_harmony.dart`, `yinyang_matcher.dart`, `intimacy.dart` | §4·5·6·9 (L3·L4) |
| **P5** | `compat_pipeline.dart`, `compat_aggregator.dart`, `compat_calibration.dart` | §8·8.1·8.2 |
| **P6** | `compat_narrative.dart`, `compat_phrase_pool.dart` | §11 |
| **P7** | UI — `compatibility_report_page.dart` rewrite | — |

---

## 14. 확장 규칙 (엔진 버전 bump 원칙)

- 새 PP rule 추가 → schema 영향 없음. narrative phrase pool 만 추가.
- 새 metric 도입 → `FaceReadingReport` schema bump 선행. 이 문서의 §2·§3 metric 매핑 갱신.
- 五行 weight/matrix 조정 → `kCompatSchemaVersion` 유지 (해석만 바뀌고 capture 는 그대로).
- label 경계 재보정 → `compat_calibration_test.dart` MC 재실행 후 §8.1 표 갱신.
- sub-score weight 조정 → §8 표 + `compat_aggregator.dart` 동시 갱신. invariant (§8.2) 재검증.
