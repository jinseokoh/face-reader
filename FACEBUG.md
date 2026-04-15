# FACEBUG — Face Shape Classification

**Last update**: 2026-04-15 (session 2 종료)
**Status**: 시도 3 구현 완료·실기 테스트 결과 **실패**
**다음 세션 방향**: **추측으로 값 조정 금지. 데이터 수집 → 통계 분석 → 피팅** 순으로 전환

---

## TL;DR

- Session 1: 이수지(round) 표준 오분류 발견 후 부분 롤백.
- Session 2 오늘: 여러 번의 추측 기반 수정 (mean 이동, 3축 composite, 4축 composite).
- **마지막 시도(`lowerFaceFullness`) 실측에서 반대 방향으로 날아감**.
  - 이수지 실기 측정 `lowerFaceFullness = 0.5223`
  - 설정해둔 ref mean = 0.66 → z = -2.75 → 가중치 2.0 → contribution **-5.5**
  - widthScore = -4.09 → **"세로로 긴 얼굴형"** 으로 오분류
- **근본 원인**: 매 단계 데이터 없이 추측으로 수치 결정. 방법론 자체가 틀림.

---

## 세션 진행 기록 (요약)

### 시도 1: mean 1.29 → 1.35 ✅ (표준 band 오분류만 해결)
### 시도 2: 3축 composite (aspect+taper+gonial) ❌ (이수지 구분 실패)
### 시도 3: 4축 composite + `lowerFaceFullness` ❌ (완전 반대 방향)

자세한 이전 내용은 git log 참조.

---

## 실기 측정된 이수지 값 (핵심 증거)

```
══════════ [FACE SHAPE] ══════════
  gender=female ethnicity=eastAsian
  faceAspectRatio:   raw=1.2637 z=-1.2323  contrib= 1.232
  faceTaperRatio:    raw=0.8084 z= 0.3673  contrib= 0.367
  lowerFaceFullness: raw=0.5223 z=-2.7542  contrib=-5.508  ★
  gonialAngle:       raw=138.81 z=-0.3646  contrib=-0.182
  widthScore = -4.091  → "세로로 긴 얼굴형" (완전 오분류)
═══════════════════════════════════
```

**결정적 사실**: 이수지의 `lowerFaceFullness = 0.5223`.
→ 제가 설정한 ref mean 0.66은 관측치와 0.14나 차이. 완전 빗나감.

### 직전 땜빵 (세션 말기 적용)
`face_reference_data.dart` 12개 ethnicity×gender 모두 `lowerFaceFullness: MetricReference(0.50, 0.05)` 로 강제 통일.
이 상태도 IU 데이터 없이는 검증 불가.

---

## 현재 코드 상태 (오늘 세션 종료 시점)

### 수정된 4 파일
| 파일 | 변경 |
|---|---|
| `lib/domain/services/face_metrics.dart` | `LandmarkIndex`에 4개 추가(`rightJawLower=150, leftJawLower=379, rightChinSide=148, leftChinSide=377`). `lowerFaceFullness` getter 추가. `computeAll()`에 포함. |
| `lib/data/constants/face_reference_data.dart` | `metricInfoList`에 `lowerFaceFullness` 엔트리. 12개 ethnicity×gender 모두에 `MetricReference(0.50, 0.05)` 추가. faceAspectRatio female eastAsian mean 1.29→1.35 유지. |
| `lib/presentation/screens/physiognomy/physiognomy_screen.dart` | `_faceShape()` 4축 composite. null-safe. |
| (추가 없음) | |

### 현재 `_faceShape` 공식 (문제 있음)
```
widthScore =
    −1.0·aspectZ
  + 1.0·taperZ
  + 2.0·fullnessZ   ★ 이 축이 이수지에서 완전히 반대로 나오고 있음
  + 0.5·gonialZ
threshold ±2.5
```

---

## 왜 추측 기반 접근이 실패했나

이번 세션 내내 아래 사이클을 반복:
1. 추측으로 값 설정 → 2. 사용자가 기기로 테스트 → 3. 사용자 실망 → 4. 다른 추측

**문제**: 실측 분포를 모르는 상태에서 reference mean/sd, 가중치, 임계값을 모두 추측. 한 번의 변경이 다른 축과 상호작용하여 예측 불가.

---

## ⭐ 다음 세션 방향: data-first 방법론

**더 이상 추측하지 말 것. 데이터 수집이 선행되어야 함.**

### Step A — CSV 로깅 모드 추가
한 번의 얼굴 분석에서 모든 메트릭 raw 값을 한 줄의 CSV로 콘솔에 출력.
```
CSV,<label>,<gender>,<ethnicity>,<faceAspectRatio>,<faceTaperRatio>,<lowerFaceFullness>,<gonialAngle>,...
```
사용자가 복붙할 수 있는 형식.

### Step B — 라벨 확실한 샘플 20+ 수집
- **가로로 넓은** (5~7명): 이수지, 박나래, 홍윤화, 김민경, 이국주 등
- **세로로 긴** (5~7명): 수영, 제니, 유인나 등
- **표준** (5~7명): IU, 태연, 김태희, 한예슬 등

각 인물당 2~3 프레임 수집해 측정 노이즈 파악.

### Step C — 통계 분석 (다음 세션 Claude가 수행)
CSV 받아서:
1. 클래스 간 각 메트릭 mean/std 비교
2. 어느 축이 실제로 3그룹 구분하는지 (ANOVA 유사)
3. 분산 최대인 축 조합 도출 (LDA 유사)
4. **데이터 기반** 가중치·임계값 제시

### Step D — 검증
미수집 얼굴에 다시 돌려 정확도 확인. 틀리면 샘플 추가 → 재피팅.

---

## 당장 할 수 있는 안전 조치 (선택)

만약 **일단 앱을 안정적 동작 상태로** 되돌려놓고 싶다면:
- `physiognomy_screen.dart::_faceShape` 의 `contribFullness` 가중치 **2.0 → 0.0** 으로 내림
- 결과적으로 3축(aspect, taper, gonial) 분류로 회귀
- 이수지는 여전히 "표준"으로 오분류되지만 세로로 긴 오분류는 피함

이 안전 조치는 본인 판단. 데이터 수집 단계 진행 시 굳이 할 필요 없음.

---

## 실측 샘플 (지금까지 모인 것)

### 이수지 (가로로 넓은, 둥근) — 확정 레이블
| # | aspect | taper | fullness | gonial |
|---|---|---|---|---|
| A1 | 1.2460 | 0.7734 | — | 144.30° |
| A2 | 1.2454 | 0.7997 | — | 140.77° |
| A3 | 1.2637 | 0.8084 | **0.5223** | 138.81° |
| A4 | 1.3210 | 0.8007 | — | 138.64° |
| A5 | 1.3463 | 0.7781 | — | 138.81° |
| A6 | 1.3357 | 0.7728 | — | 142.97° |

(A3만 시도 3 적용 후 측정이라 fullness 있음. 나머지는 이전 로그라 fullness 없음.)

### IU (표준, V-line) — **fullness 실측 없음**, 다음 세션 1순위 수집
| # | aspect | 비고 |
|---|---|---|
| I1 | 1.2454 | "올백" 사진, 이마 완전 노출 |
| I2 | 1.2460 | 다른 사진, 같은 raw |
| I3 | 1.3110 (과거) | 정상 프레임 |

### 표준 일반
- 1.3210, 1.3357, 1.3463, 1.3958 — 모두 표준 기대

---

## 문헌 근거 (참고용)

- `faceAspectRatio` 표준: bizygomatic = 0.75 × face height → aspect ≈ 1.33
- `faceTaperRatio` 표준: bigonial/bizygomatic ≈ 0.85~0.88
- Round: 낮은 aspect + 풍만한 하단 + 높은 taper + 둔각 gonial
- Oval: 중간 aspect + 갸름한 하단 + 낮은 taper
- Long: 높은 aspect (facial index > 88%)

Sources:
- https://plasticsurgerykey.com/facial-type-3/
- https://pocketdentistry.com/evaluation-of-the-face/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC7605391/

---

## 관련 파일

| 역할 | 경로 |
|---|---|
| 메트릭 계산 + LandmarkIndex | `lib/domain/services/face_metrics.dart` |
| Reference 데이터 | `lib/data/constants/face_reference_data.dart` |
| 분류 공식 | `lib/presentation/screens/physiognomy/physiognomy_screen.dart::_faceShape` |
| 보정 | `lib/domain/models/face_analysis.dart:39~52` |

---

## 다음 세션 시작 메시지 (복붙용)

```
FACEBUG.md 읽었고 현재 상태 확인. 이제 data-first 로 전환.
Step A(CSV 로깅 모드) 부터 붙이자. 추측 금지, 데이터부터.
```

또는 데이터 이미 모았다면:
```
FACEBUG.md 읽었고 20명 CSV 모았어. 통계 분석하고 가중치·임계값 도출해줘.
[CSV 붙임]
```
