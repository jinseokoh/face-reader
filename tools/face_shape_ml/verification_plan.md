# 관상앱 Metric Verification Plan — Two-Track Architecture

> **Goal**: 18개 metric 리스트의 정당성을 증명하고, 누락된 관상 attributes를 enumerate하고, Track #1 (관상 결정론적) + Track #2 (얼굴형 CNN) 투트랙 시스템 설계를 확정한다.

---

## 0. Executive Summary

현재 앱이 망가진 이유는 **두 개의 완전히 다른 문제를 하나의 파이프라인에 섞었기 때문**이다:

| 문제 | 성격 | 해결 방식 |
|------|------|----------|
| 얼굴형 5-class 분류 (Heart/Oblong/Oval/Round/Square) | 전세계 공통, 라벨 데이터 풍부 (Kaggle) | **학습 기반 (CNN/MLP)** |
| 관상학적 attribute 판독 (눈썹 모양, 눈꼬리 방향, 입꼬리 등) | 도메인-지식 기반, 라벨 데이터 없음 | **결정론적 기하 계산** |

한 모델이 두 문제를 동시에 풀 수 없다. CNN은 `fineEyebrow=True`의 의미를 학습할 데이터가 없고, z-score rule은 얼굴형 5-class를 분류할 표현력이 없다. 따라서 **두 트랙을 분리**한다.

### Track #1 — Physiognomic Attribute Track (결정론적)
MediaPipe 468 landmark → 관상학적 attribute vector → 관상 report
- 학습 없음, 재현 가능, 설명 가능
- 검증: 고전 관상서 reference + 수동 샘플 review
- 산출물: attribute score [0~1] × N개

### Track #2 — Face Shape / Archetype Track (학습 기반)
Face crop (or landmarks) → CNN/MLP → 5-class face shape + archetype
- Kaggle 5000장으로 pretrain → 한국인 38-sample CSV로 fine-tune
- 검증: held-out test accuracy
- 산출물: argmax + softmax confidence

두 트랙은 **완전히 독립**. Track #2 모델을 교체해도 Track #1은 그대로, Track #1 attribute를 추가해도 Track #2는 재학습 불요.

---

## 1. Part A — 관상 Taxonomy (五官 × 三停 × 五形)

### 1.1 五官 (오관) — 五官相法의 5개 중심 기관

| 관 | 부위 | 관상 의미 | MediaPipe 측정 가능? |
|----|------|----------|---------------------|
| 眉 (미) — 保壽官 | 눈썹 | 수명, 형제, 성격 결단력 | ✓ 여러 landmark |
| 目 (목) — 監察官 | 눈 | 지혜, 현재 운, 심성 | ✓ 정확 |
| 鼻 (비) — 審辨官 | 코 | 재물, 중년운, 자존심 | ✓ 정확 (2D 제한) |
| 口 (구) — 出納官 | 입 | 식록, 애정, 말씀씀이 | ✓ 정확 |
| 耳 (이) — 採聽官 | 귀 | 초년운, 장수, 총명 | △ 정면샷 제한 |

### 1.2 三停 (삼정) — 얼굴 3등분

| 삼정 | 범위 | 관상 의미 | MediaPipe 측정 |
|------|------|----------|---------------|
| 上停 (상정) | 이마 상단 ~ 눈썹 | 초년운 (15~30세), 사고력, 부모운 | `dist(forehead_top, brow)` / faceHeight |
| 中停 (중정) | 눈썹 ~ 코끝 (subnasale) | 중년운 (31~50세), 의지, 자아 | `dist(brow, subnasale)` / faceHeight |
| 下停 (하정) | 코끝 ~ 턱 | 말년운 (51세~), 애정, 자식, 재물 | `dist(subnasale, chin)` / faceHeight |

**이상형**: 三停均等 (세 구역이 거의 같은 길이). 현재 `upperFaceRatio/midFaceRatio/lowerFaceRatio`가 이에 해당 **BUT 버그 있음** (§3.1).

### 1.3 五形 얼굴형 — 오행 분류

| 五形 | 특징 | 서양 분류 근사 |
|------|------|--------------|
| 金形 | 네모, 각진 턱 | Square |
| 木形 | 길고 마른, 세로긴 | Oblong |
| 水形 | 둥글고 살집 | Round |
| 火形 | 위 넓고 아래 뾰족 (V) | Heart |
| 土形 | 두껍고 후덕 | (Square/Round 혼합) |

→ **Track #2에서 5-class로 학습**. 土形은 대체로 Square/Round와 혼동, 일단 서양 5-class 체계로 학습 후 내부 매핑.

### 1.4 十二宮 (십이궁) — 12개 운명 부위 (참조용)

| 宮 | 위치 | 의미 | 현재 측정? |
|----|------|------|----------|
| 命宮 | 미간 (glabella) | 전체운, 정신 | ✗ (추가 가능) |
| 官祿宮 | 이마 중앙 | 관직, 사회운 | △ (이마 모양) |
| 財帛宮 | 코 전체 | 재물 | △ (현재 너비/높이만) |
| 兄弟宮 | 눈썹 | 형제관계, 성격 | ✓ (두께만, 모양 없음) |
| 夫妻宮 | 눈꼬리 (어미) | 배우자, 애정 | △ (tilt만) |
| 田宅宮 | 눈꺼풀 | 부동산, 주거 | ✗ |
| 男女宮 | 눈밑 (와잠) | 자식, 자녀운 | ✗ |
| 疾厄宮 | 콧대 | 건강 | ✗ (콧대 굴곡 없음) |
| 遷移宮 | 이마 양쪽 | 이동, 변화 | ✗ |
| 奴僕宮 | 턱 양쪽 | 부하, 주거환경 | △ |
| 福德宮 | 눈썹 위 | 복, 재산 | ✗ |
| 父母宮 | 이마 최상단 | 부모운 | ✗ |

→ 十二宮 전수는 현재 거의 미측정. Track #1 확장 대상.

---

## 2. Part B — 현재 18개 Metric 재분류

이전 audit (`feature_audit.md`)은 "얼굴형 분류에 기여하는가?"만 봤다. 관상 가치를 함께 고려하면 분류가 달라진다.

### 2.1 재분류 매트릭스

| Metric | 얼굴형 기여 (audit) | 관상 기여 | **배정** |
|--------|-------------------|----------|---------|
| `faceAspectRatio` | 🟢 강 (-6.5pp) | 🟢 五形 구분 | **Track #2 (주), Track #1 보조** |
| `faceTaperRatio` | 🟢 강 (-1.5pp) | 🟢 金/火 구분 | **Track #2 (주), Track #1 보조** |
| `lowerFaceFullness` | 🔴 약 (-0.4pp) | 🟢 下停 풍만 (말년운) | **Track #1** |
| `upperFaceRatio` | 🔴 노이즈 (+1.5pp) | 🟢 上停 (초년운) | **Track #1** |
| `midFaceRatio` | 🟡 중 | 🟢 中停 (중년운) | **Track #1** ⚠ 버그수정 후 |
| `lowerFaceRatio` | 🟡 중 | 🟢 下停 (말년운) | **Track #1** |
| `gonialAngle` | 🟢 강 (-1.7pp) | 🟢 턱 각도, 결단력 | **둘 다** |
| `intercanthalRatio` | 🟡 | 🟢 印堂 넓이 간접지표 | **Track #1** |
| `eyeFissureRatio` | 🟢 강 (-2.0pp) | 🟢 눈 크기 | **둘 다** |
| `eyeCanthalTilt` | 🔴 노이즈 | 🟢🟢 鳳眼/丹鳳眼/垂眼 판별 핵심 | **Track #1** ⚠ 부호보존 |
| `eyebrowThickness` | 🔴 노이즈 | 🟢🟢 濃眉/淡眉 핵심 | **Track #1** |
| `browEyeDistance` | 🟡 | 🟢 田宅宮 넓이 | **Track #1** |
| `nasalWidthRatio` | 🔴 노이즈 | 🟢 財帛宮 (콧망울) | **Track #1** |
| `nasalHeightRatio` | — | **중복 (midFaceRatio와 동일 공식)** | **삭제** |
| `mouthWidthRatio` | 🟡 | 🟢 입 크기, 食祿 | **Track #1** |
| `mouthCornerAngle` | 🔴 노이즈 (audit 기준) | 🟢🟢 仰月口/俯月口 핵심 | **Track #1** ⚠ 부호보존 |
| `lipFullnessRatio` | 🟢 강 (-4.6pp) | 🟢 후덕함, 情 | **둘 다** |
| `philtrumLength` | 🟡 | 🟢 子女宮, 壽命 | **Track #1** |

### 2.2 삭제/수정 결정

- **삭제**: `nasalHeightRatio` (코드 버그, `midFaceRatio`와 수식 동일. 상관 r=1.000)
- **수정 (부호 복원)**:
  - `eyeCanthalTilt`: 현재 평균 각도(부호포함). **확인 필요**: 실제 Flutter 구현에서 절댓값인지 부호 유지인지. 부호가 있어야 眼頭下垂 vs 眼尾上揚 구분 가능
  - `mouthCornerAngle`: 同上. 仰月(위로) vs 俯月(아래로) 핵심이 부호
- **의미 보존**: audit가 "noise"로 판정한 6개 (eyebrowThickness, upperFaceRatio, nasalWidthRatio, mouthCornerAngle, lowerFaceFullness, eyeCanthalTilt) 중 **5개는 관상 필수**. Track #1에 유지.

### 2.3 Track 배정 최종

**Track #1 관상 전용 (입력 → attribute)**:
```
lowerFaceFullness, upperFaceRatio, midFaceRatio, lowerFaceRatio,
intercanthalRatio, eyeCanthalTilt, eyebrowThickness, browEyeDistance,
nasalWidthRatio, mouthWidthRatio, mouthCornerAngle, philtrumLength
(+ 둘 다 카테고리: faceAspectRatio, faceTaperRatio, gonialAngle,
   eyeFissureRatio, lipFullnessRatio)
= 총 17개 (nasalHeightRatio 제거)
```

**Track #2 얼굴형 분류 (입력)**:
- **옵션 A** (현재 완성): `faceAspectRatio, faceTaperRatio, gonialAngle, eyeFissureRatio, lipFullnessRatio` + 보조 metric → 18d MLP → 70.4%
- **옵션 B** (권장): 얼굴 crop 112x112 → **MobileNetV3 CNN** → 5-class
  - 예상 정확도: 85%+ (Kaggle 유사 논문 기준)
  - 모델 크기: ~2MB (TFLite FP16)

---

## 3. Part B+ — Missing Attributes (관상 필수, 현재 부재)

### 3.1 버그 수정 먼저

| 파일 | 증상 | 수정 |
|------|------|------|
| `flutter/lib/domain/services/face_metrics.dart` | `midFaceRatio` = `dist(nasion, subnasale) / faceHeight` 이고, `nasalHeightRatio` 수식이 **동일**. 상관 r=1.000 | `nasalHeightRatio` 공식 변경 OR 삭제. 本来 의도: **콧대 길이 / 얼굴 폭** 같은 별개 비율이었어야 함 |

### 3.2 추가할 관상 Attribute (Track #1 확장 후보)

> 각 항목: **관상 의미 | MediaPipe landmark 매핑 | 측정 가능도**

#### (A) 눈썹 관련 (兄弟宮)
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `eyebrowCurvature` | 直眉(직선)/彎眉(곡선) — 직선은 강직, 아치는 부드러움 | 눈썹 7 landmark (46,53,52,65,55 등)에 곡선 fit → 곡률 반경 | 🟢 명확 |
| `eyebrowLength` | 眉長過目 (눈보다 길다 = 형제 많음, 좋음) | `dist(내측끝, 외측끝) / eyeWidth` | 🟢 명확 |
| `eyebrowHeadHeight` vs `eyebrowTailHeight` | 劍眉(검미: 끝이 올라감, 강함), 八字眉(팔자: 끝이 처짐, 우울) | `lm[눈썹끝].y - lm[눈썹머리].y` (정규화) | 🟢 명확 |
| `eyebrowDensity` (선택) | 濃密/稀疏 — 모발 밀도 | Landmark로는 **불가**, 이미지 픽셀 분석 필요 | 🔴 CNN 필요 |
| `browSpacing` (= intercanthal 유사) | 印堂 넓이. 넓으면 관대, 좁으면 속좁음 | `dist(R_BROW_INNER, L_BROW_INNER)` | 🟢 **추가 예정** |

#### (B) 눈 관련 (夫妻宮, 田宅宮, 男女宮)
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `eyeVerticalOpening` | 鳳眼(가로길다)/圓眼(동그랗다) 판별 — 가로/세로 비율이 핵심 | `dist(eye_top, eye_bottom) / dist(inner, outer)` per eye | 🟢 명확, **추가 예정** |
| `eyeTiltDirection` (부호) | 上揚(끝이 올라감, 총명)/下垂(끝이 처짐, 자비) | 현재 `eyeCanthalTilt`를 **부호포함**으로 저장 | 🟡 기존 수정 |
| `innerEyeFold` (쌍꺼풀) | 有眼皮/無眼皮 | MediaPipe에 별도 랜드마크 없음. z-depth에서 fold detect 시도 가능하나 불안정 | 🔴 CNN 필요 |
| `underEyeFullness` (와잠) | 男女宮 — 자식운, 臥蠶 | `lm[145].y - lm[133].y` 근처. 미세변화 → 신뢰도 낮음 | 🟡 약함 |
| `eyeSpacing` | 양 눈 사이 = 印堂 | 이미 `intercanthalRatio`에 포함 | ✓ 기존 |

#### (C) 코 관련 (財帛宮, 疾厄宮)
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `noseTipProtrusion` | 懸膽鼻(코끝 돌출) — 재물 ↑ | `lm[1].z` 활용 (z는 카메라 상대적, 불안정하지만 가능) | 🟡 |
| `noseLengthRatio` | 콧대 길이 / 얼굴 길이 | `dist(nasion=168, nose_tip=1) / faceHeight` | 🟢 **추가 예정, 원래 nasalHeightRatio 의도** |
| `noseBridgeStraightness` | 直鼻/鷹鼻(매부리)/塌鼻(주저앉음) — 건강운 | 콧대 landmark(168→6→197→195→5→4→1) 에 직선 fit 후 residual | 🟡 z 필요 |
| `noseAlaSpread` | 蒜頭鼻 (콧망울 큼 = 돈 모음) | 현재 `nasalWidthRatio` | ✓ 기존 |
| `noseTipShape` | 둥근/뾰족/위로 들림 | z 정보 + 주변 landmark. **불안정** | 🔴 CNN 권장 |

#### (D) 입 관련 (出納官)
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `mouthCornerDirection` (부호) | 仰月口(위) — 복록, 俯月口(아래) — 고생 | 기존 `mouthCornerAngle`을 **부호포함** | 🟡 기존 수정 |
| `upperLipFullness` vs `lowerLipFullness` | 윗입술 > 아랫입술 = 情 많음 / 반대 = 이기적 | `dist(0, 13)` vs `dist(14, 17)` 비율 | 🟢 **추가 예정** |
| `lipThickness` | 厚脣 (두꺼움 = 정 많음) / 薄脣 (얇음 = 냉정) | 기존 `lipFullnessRatio` | ✓ 기존 |
| `mouthCompression` | 다문 입 형태 — closed shape | 내측 입술 (13, 14) 거리 | 🟢 |

#### (E) 턱/얼굴윤곽 관련 (奴僕宮)
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `chinShape` (round/square/pointed) | 方頤(네모)/圓頤(둥글)/尖頤(뾰족) — 말년운 성향 | 턱 landmark (148, 176, 149, 150, 152, 378, 379, 365, 397) 에 shape descriptor | 🟢 |
| `chinProtrusion` | 地閣豐滿 (턱 돌출 = 말년운 좋음) | `lm[152].z` 또는 `lm[152].y - 平均` | 🟡 z 불안정 |
| `jawAngularity` | 각진 정도 — 기존 `gonialAngle` | ✓ 기존 | ✓ |
| `lowerFaceFullness` | 볼살 정도 | ✓ 기존 | ✓ |

#### (F) 이마 관련 (官祿宮, 父母宮)
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `foreheadShape` (M/round/square) | M자형(예술감성), 둥근이마(온순), 각진이마(의지강) | 이마 상단 landmark (10, 151, 67, 69, 66, 107 등) shape descriptor | 🟡 hairline 모호 |
| `foreheadHeight` | 上停 길이 | 기존 `upperFaceRatio` | ✓ 기존 |
| `foreheadWidth` | 天庭 넓이 | `dist(좌측 관자놀이, 우측 관자놀이)` — landmark 127, 356 | 🟢 **추가 예정** |
| `templeHollow` (遷移宮) | 관자놀이 꺼짐 | 2D 측정 어려움 | 🔴 |

#### (G) 광대/볼 관련
| Attribute | 관상 의미 | Landmark 매핑 | 가능도 |
|-----------|----------|--------------|--------|
| `cheekboneProminence` | 顴骨 (광대 높음 = 권력/강한자아) | `lm[116].z` vs `lm[234].z`. 2D로는 광대 landmark 돌출 여부 | 🟡 z 필요 |
| `cheekboneWidth` | 광대 폭 / 얼굴 폭 | `dist(116, 345) / faceWidth` | 🟢 **추가 예정** |

### 3.3 요약 — 추가 예정 Attribute (Phase 1)

고전 관상 가치 × 측정 신뢰도 🟢만 우선 추가:

```
1. eyebrowLength           # 兄弟宮
2. eyebrowTiltDirection    # 劍眉/八字眉 (부호)
3. eyebrowCurvature        # 直眉/彎眉
4. browSpacing             # 印堂
5. eyeAspect               # 鳳眼/圓眼 (세로/가로)
6. eyeTiltDirection        # 부호 복원 (기존 수정)
7. noseLengthRatio         # 콧대 길이/얼굴 길이 (nasalHeightRatio 대체)
8. upperVsLowerLipRatio    # 윗입술/아랫입술
9. mouthCornerDirection    # 부호 복원 (기존 수정)
10. chinShape              # 方/圓/尖 (round/square/pointed categorical)
11. foreheadWidth          # 天庭
12. cheekboneWidth         # 顴骨 폭
```

**Phase 2 후보** (z-depth 필요, 또는 CNN 대체):
- eyebrowDensity, innerEyeFold, noseBridgeStraightness, noseTipShape, foreheadShape, cheekboneProminence, chinProtrusion

이들은 MediaPipe 2D로는 어려움. **별도 CNN sub-model** (eyebrow region → fold present? etc)로 나중에 추가.

---

## 4. Part C — Validation Methodology

### 4.1 Track #1 (관상 attribute) 검증

**문제**: 관상 라벨 데이터셋이 존재하지 않음. "eyebrowCurvature=0.73은 정답인가?" 를 자동 검증 불가.

**3단계 검증 절차**:

#### Step 1 — **수학적 sanity check** (자동)
- 각 attribute의 분포 확인: `features.csv`에서 5000 sample 전체의 평균/표준편차/범위 출력
- 이상치 10장 sampling → 육안 확인 (관상앱에서 쓸 만한 값인지)
- 두 attribute 간 의도치 않은 상관(r>0.9) 없는지 재확인 (midFaceRatio 버그 재발 방지)

#### Step 2 — **고전 레퍼런스 매칭** (수동, 대부님 1차 리뷰)
- 각 attribute마다 **고전 관상 교과서에서 정의한 극단값** 예시 이미지를 수집 (e.g., 劍眉 전형 vs 八字眉 전형)
- Python으로 추출한 수치가 classical description과 일치하는지 대부님이 판정
- 산출물: `out/attribute_sanity_samples.md` — 각 attribute × 극단 샘플 2~3장 썸네일

#### Step 3 — **사용자 수동 라벨링** (소량)
- 대부님이 본인 + 가족 10~30장에 대해 "이 사람은 劍眉다/八字眉다" 식으로 직접 라벨링
- Python 계산값과 대부님 판정이 일치하는지 confusion matrix
- 일치율 >80% 면 해당 attribute 통과

> **핵심**: Track #1은 "정확히 맞느냐"가 아니라 "**일관되게 관상 변별력을 주느냐**"가 기준. 한 사람에게 劍眉 점수가 0.8 나오면 다른 劍眉인 사람도 비슷하게 나와야 함.

### 4.2 Track #2 (얼굴형 분류) 검증

**자동 검증 가능**.

- **Baseline**: 현재 `train_face_shape.py` Model A = 70.4% (ratios MLP, 18d)
- **Target**: CNN 85%+ on Kaggle test set
- **Korean bias check**: 한국인 38-sample CSV에 대한 accuracy 별도 측정
- **Deployment parity**: TFLite FP16 vs Keras 일치율 >99% (이미 extract_landmarks에서 100% 달성)

### 4.3 통합 검증 — 실제 앱 UX에서

- Track #1 attributes + Track #2 face shape 두 출력을 앱 화면에 통합
- 5~10명 테스트 (본인, 가족, 동료)
- 체크리스트:
  - [ ] 같은 사람을 여러 각도로 찍었을 때 attribute가 ±10% 내 안정
  - [ ] 얼굴형 분류가 5회 중 4회 일치 (confidence >0.5)
  - [ ] 관상 report가 "맞다/애매/틀리다" 중 "맞다" 60%+
  - [ ] 반응속도 Flutter에서 <300ms (MediaPipe + TFLite)

---

## 5. Track #1 Architecture (관상 결정론적)

### 5.1 Data Flow

```
Camera frame
   └─> MediaPipe FaceMesh (468 landmarks, existing)
         └─> face_metrics.dart (Dart 구현, 기존 확장)
               ├─> [기존 17개 refined metric]
               └─> [신규 12개 Phase 1 attribute]
                     └─> attribute_engine.dart (기존 rule-based scoring 확장)
                           └─> 관상 report (textual + visual)
```

### 5.2 변경 파일 (Flutter)

| 파일 | 작업 |
|------|------|
| `flutter/lib/domain/services/face_metrics.dart` | `nasalHeightRatio` 삭제, 12개 attribute 추가 (함수 `computeAll()` 확장) |
| `flutter/lib/domain/services/attribute_engine.dart` | 신규 attribute에 대한 관상 rule 추가 (e.g., `劍眉 if eyebrowTiltDirection > threshold`) |
| `flutter/lib/domain/models/face_analysis.dart` | `FaceShape` 결정 로직 삭제 (Track #2로 이동). Attribute vector만 pass-through |
| `flutter/lib/presentation/screens/.../report_screen.dart` | 신규 attribute를 UI에 노출 |

### 5.3 변경 파일 (Python, 검증용)

| 파일 | 작업 |
|------|------|
| `tools/face_shape_ml/extract_landmarks.py` | `compute_ratios()` 확장. Phase 1 attribute 포함 → 총 29 feature |
| `tools/face_shape_ml/validate_attributes.py` | **NEW**. 각 attribute 분포/극단값/sanity visualize |

---

## 6. Track #2 Architecture (얼굴형 CNN)

### 6.1 Data Flow

```
Camera frame
   └─> MediaPipe FaceMesh 또는 face detector (bbox)
         └─> 112x112 얼굴 crop + alignment
               └─> MobileNetV3 CNN (TFLite FP16, ~2MB)
                     ├─> 5-class softmax → face_shape
                     └─> (optional) embedding → archetype map
```

### 6.2 학습 파이프라인

1. Kaggle niten19 5000장 → MobileNetV3 pretrain (transfer from ImageNet)
2. 한국인 38-sample CSV → fine-tune head only (bias correction)
3. Data augmentation: horizontal flip, ±10° rotation, brightness, mild jitter (얼굴형은 pose에 민감하므로 과한 augmentation 금지)
4. Export TFLite FP16 + parity check (agreement ≥0.99)

### 6.3 생성 파일

| 파일 | 역할 |
|------|------|
| `tools/face_shape_ml/train_cnn.py` | **NEW**. CNN 학습 스크립트 |
| `tools/face_shape_ml/out/face_shape_cnn.tflite` | 배포 모델 |
| `flutter/lib/data/services/face_shape_classifier.dart` | **NEW** 또는 rename from existing. tflite_flutter로 추론 |

---

## 7. Implementation Roadmap

| Phase | 내용 | 산출물 | 예상 소요 |
|-------|------|-------|---------|
| **P0** | 버그수정: midFaceRatio ≡ nasalHeightRatio 중복 제거 | `face_metrics.dart` patch | 30분 |
| **P1** | `extract_landmarks.py`에 12개 Phase 1 attribute 추가 → 분포 sanity check | `features_v2.csv`, `validate_attributes.py` | 2시간 |
| **P2** | 관상 극단값 샘플 수집 → 대부님 1차 리뷰 | `attribute_sanity_samples.md` | 반나절 |
| **P3** | 12개 attribute를 Flutter `face_metrics.dart`에 포팅 (Python parity) | Flutter PR | 반나절 |
| **P4** | `attribute_engine.dart` 에 관상 rule 확장 | 관상 report enrichment | 반나절 |
| **P5** | Track #2 CNN 학습 (`train_cnn.py`) | `face_shape_cnn.tflite`, 85%+ accuracy | 반나절 (GPU) |
| **P6** | Flutter 통합: CNN classifier + attribute report 연동 | 앱에서 실측 | 반나절 |
| **P7** | 사용자 테스트 10명 + feedback | 수정본 | 1~2일 |

총 ≈ 3~4일 집중 작업 (대부님 리뷰 시간 제외).

---

## 8. 무엇이 검증되었고, 무엇이 여전히 가정인가

### ✅ 이미 증명됨
- MediaPipe ↔ Python ↔ TFLite FP16 numerical parity 100%
- 5000장 Kaggle 데이터로 18-feature MLP 70.4% (face shape만 기준 baseline)
- `nasalHeightRatio` = `midFaceRatio` **코드 중복 버그** (상관 r=1.000, 5000 샘플로 확인)
- 18개 중 5개는 얼굴형 분류에 강한 신호, 6개는 얼굴형에는 노이즈

### ⚠ 가정 (이 플랜이 검증)
- Phase 1 12개 attribute가 관상학적으로 의미있는 변별력 준다 (Step 2/3 수동 검증 필요)
- CNN 85% 달성 가능 (유사 논문 기준, 실측 필요)
- 한국인 38-sample이 fine-tuning에 충분 (부족하면 data augmentation 또는 추가 수집)

### ❌ 의도적으로 후순위로 밀린 것
- 쌍꺼풀, 콧대 직선도, 광대 돌출도 — MediaPipe 2D 한계로 Phase 2 이후
- 귀 attribute (정면샷 제약)
- 十二宮 중 田宅宮/男女宮/疾厄宮 세밀부위 (얼굴 sub-region CNN 필요)

---

## 9. 대부님 Decision Points

이 문서가 요구하는 결정:

1. **Phase 1 12개 attribute 리스트** 이대로 승인? 추가/제거할 것?
2. **부호 복원 대상** (eyeCanthalTilt, mouthCornerAngle): 현재 Flutter 구현이 절댓값인지 확인 후 수정 필요 — 진행 허가?
3. **CNN 전환** (Track #2): 현재 70.4% MLP를 그대로 쓸지, CNN 85%+ 재학습할지. 후자 권장.
4. **관상 극단값 샘플링**: 대부님이 직접 극단 예시를 지정해줄지 (예: "이 사람이 전형적 劍眉"), 아니면 Python이 극단값 자동추출 후 대부님이 승인만 할지.

---

_Plan drafted 2026-04-17. Awaiting approval before code changes._
