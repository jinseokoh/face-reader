# FACEBUG — Face Shape Classification

**Last update**: 2026-04-15 (session 2)
**Status**: 시도 3 구현 완료, **실측 검증 대기**
**앱 핵심 기능**: `가로로 넓은 / 표준 / 세로로 긴` 얼굴형 분류

---

## TL;DR

- Session 1에서 이수지(round, 볼살) 가 "표준"으로 오분류 이슈 발견 후 부분 롤백.
- Session 2에서 근본 원인 재진단: **bone 기반 랜드마크로는 연조직(볼살)로 인한 "가로 넓음" 감지 불가**.
- 해법: 피부 외곽선 기반 `lowerFaceFullness` 신규 메트릭 추가 + 4축 composite classifier.
- **구현 완료·Flutter analyze clean. 실기기 검증 단계.**

---

## 세션 진행 기록

### Session 1 (이전, 기록만)
- 연예인 4명(Suji/Rose/IU/Doyeon) 샘플로 `faceAspectRatio` mean=1.29 캘리브레이션.
- 이수지(1.2637) → z=-0.38 → 표준. 사용자 기대(가로 넓은)와 불일치.
- 임계값 완화·5-tier 도입 시도 → false positive 발생 → 모두 롤백.

### Session 2 (2026-04-15, 오늘)

#### 시도 1: mean 1.29 → 1.35 ✅ 부분 효과 유지
**파일**: `lib/data/constants/face_reference_data.dart:211`
**배경**: 표준 얼굴들(raw 1.32~1.40)이 z>1.0으로 "세로로 긴"으로 오분류되던 문제.
**결과**: 표준 band 정상 분류. 하지만 이수지 vs IU 구분은 여전히 실패.

#### 시도 2: 3축 composite (aspect + taper + gonial) ❌ 실패
**파일**: `lib/presentation/screens/physiognomy/physiognomy_screen.dart::_faceShape`
**공식**: `widthScore = -1.0·aspectZ + 1.5·taperZ + 1.0·gonialZ`, threshold ±2.5
**실측 (이수지 6프레임)**: widthScore 모두 0.02 ~ 1.75 → 전부 "표준" 오분류.
**원인**: bone 기반 `faceTaperRatio`(z≈0)·`gonialAngle`(z≈0) 이 이수지·IU 구분 못 함.

#### 시도 3: `lowerFaceFullness` 추가 ⭐ 현재 상태
**4 파일 수정. Flutter analyze 통과.**

**(a) `lib/domain/services/face_metrics.dart`**
- `LandmarkIndex`에 4개 추가 (MediaPipe face oval 하단부):
  ```dart
  static const rightJawLower = 150;
  static const leftJawLower = 379;
  static const rightChinSide = 148;
  static const leftChinSide = 377;
  ```
- 신규 메트릭:
  ```dart
  double get lowerFaceFullness {
    final jaw      = _dist(rightGonion, leftGonion);
    final jawLower = _dist(rightJawLower, leftJawLower);
    final chinSide = _dist(rightChinSide, leftChinSide);
    return (jaw + jawLower + chinSide) / (3.0 * faceWidth);
  }
  ```
- `computeAll()`에 포함

**(b) `lib/data/constants/face_reference_data.dart`**
- `metricInfoList`에 `lowerFaceFullness` 엔트리 추가
- **12개 ethnicity×gender 전부**에 `MetricReference(taper_mean - 0.13, 0.05)` 초기값
  - 여성 eastAsian: `0.66, 0.05` (taper 0.79 기반)
  - 남성 eastAsian: `0.72, 0.05`

**(c) `lib/presentation/screens/physiognomy/physiognomy_screen.dart`**
- `_faceShape()` 공식 교체:
  ```
  widthScore =
      −1.0·aspectZ     (bounding box 세로/가로)
    + 1.0·taperZ       (bone 테이퍼)
    + 2.0·fullnessZ   ★ 피부 외곽선 기반 하단 풍만도 — 결정적 축
    + 0.5·gonialZ      (보조)
  threshold ±2.5
  ```

**기대 동작 (이수지 vs IU)**:
| 인물 | aspect z | taper z | fullness z (예상) | gonial z | widthScore | 분류 |
|---|---|---|---|---|---|---|
| 이수지 (round) | −1.2 | ~0 | **+1.5~+2.0** | ~0 | +4~+5 | 가로로 넓은 ✓ |
| IU (V-line) | −1.5 | ~0 | **−1.5~−2.0** | ~0 | −1.5 ~ −2 | 표준 ✓ |

aspect 이상치 하나(IU 1.2454)가 튀어도 fullness가 반대 방향으로 상쇄.

---

## 실측 샘플 저장소

### 이수지 (가로로 넓은, 둥근)
| # | aspect | taper | gonial | widthScore(이전 3축) |
|---|---|---|---|---|
| A1 | 1.2460 | 0.7734 | 144.30° | 1.54 |
| A2 | 1.2454 | 0.7997 | 140.77° | 1.75 |
| A3 | 1.2637 | 0.8084 | 138.81° | 1.42 |
| A4 | 1.3210 | 0.8007 | 138.64° | 0.34 |
| A5 | 1.3463 | 0.7781 | 138.81° | −0.67 |
| A6 | 1.3357 | 0.7728 | 142.97° | 0.02 |

### IU (표준, V-line)
| # | aspect | 비고 |
|---|---|---|
| I1 | 1.2454 | "올백" 사진, 이마 완전 노출인데도 가로 오분류 |
| I2 | 1.2460 | 다른 사진, 같은 raw — 재현성 있음 |
| I3 | 1.3110 (과거) | 정상 프레임은 표준 zone |

### 표준 여성
- 1.3210 (z=−0.41, old) / 1.3357 / 1.3463 / 1.3958 — 모두 표준 기대

---

## 다음 단계 (다른 PC에서)

### Step 1 — Hot restart 후 이수지·IU 로그 수집

새 로그 포맷 (4축 전부 찍힘):
```
══════════ [FACE SHAPE] ══════════
  gender=female ethnicity=eastAsian
  faceAspectRatio:   raw=X.XXXX z=X.XXXX  contrib=X.XXX
  faceTaperRatio:    raw=X.XXXX z=X.XXXX  contrib=X.XXX
  lowerFaceFullness: raw=X.XXXX z=X.XXXX  contrib=X.XXX  ★
  gonialAngle:       raw=XXX.XX z=X.XXXX  contrib=X.XXX
  widthScore = X.XXX  (+=가로 -=세로)
  decision: ...
═══════════════════════════════════
```

### Step 2 — 핵심 검증: `lowerFaceFullness` raw 값 차이

| 기대 | 이수지 raw | IU raw | 차이 |
|---|---|---|---|
| 설계 성공 | 0.72~0.80 | 0.55~0.65 | ≥ 0.10 |
| 설계 실패 | 0.68 전후 | 0.66 전후 | < 0.05 |

**실패 시 대응**: 랜드마크 148/377/150/379가 피부 외곽선이 아닌 bone 가까이 찍힘 → MediaPipe Face Mesh의 face oval contour **36개 포인트 전체**를 사용해 평균폭 추출로 변경. 주요 후보 랜드마크:
```
Right outline 하단: 234 → 93 → 132 → 58 → 172 → 136 → 150 → 149 → 176 → 148 → 152
Left outline 하단:  454 → 323 → 361 → 288 → 397 → 365 → 379 → 378 → 400 → 377 → 152
```

### Step 3 — Reference 튜닝
이수지·IU·표준 각 10+ 프레임 수집 후 `lowerFaceFullness` mean/sd 재설정. 현재 공식 `taper_mean - 0.13`는 추정값.

### Step 4 — 가중치 튜닝
fullness 축이 약하면 가중치 2.0 → 3.0, 또는 threshold 2.5 → 2.0.

---

## 문헌 근거 (참고)

- **Round face**: 낮은 aspect + 풍만한 하단 + 높은 taper + 둔각 gonial
- **Square face**: 낮은 aspect + 풍만한 하단 + 높은 taper + 예각 gonial
- **Oval face**: 중간 aspect + 갸름한 하단 + 낮은 taper
- **Long (leptoprosopic)**: 높은 aspect (facial index > 88%)
- 표준 `faceAspectRatio`: bizygomatic = 0.75 × face height → aspect ≈ 1.33 (현재 refMean 1.35와 일치)

Sources:
- https://plasticsurgerykey.com/facial-type-3/
- https://pocketdentistry.com/evaluation-of-the-face/
- https://pmc.ncbi.nlm.nih.gov/articles/PMC7605391/

---

## 관련 파일

| 역할 | 경로 |
|---|---|
| 메트릭 계산 + LandmarkIndex | `lib/domain/services/face_metrics.dart` |
| Reference 데이터 + 메트릭 메타 | `lib/data/constants/face_reference_data.dart` |
| 분류 공식 | `lib/presentation/screens/physiognomy/physiognomy_screen.dart::_faceShape` |
| 보정 (aspect × 1.0189 × 1.05) | `lib/domain/models/face_analysis.dart:39~52` |

---

## 다음 세션 시작 메시지 (복붙용)

```
FACEBUG.md 읽고 시도 3 상태 확인했어.
이수지 / IU 각 프레임 로그 붙일 테니 lowerFaceFullness raw 차이 분석하고
(a) 설계 OK면 reference 튜닝, (b) 실패면 face oval 36개 포인트 기반으로 재설계해줘.
```
