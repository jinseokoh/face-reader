# FACEBUG — Face Shape Classification Issue

**Date**: 2026-04-15
**Status**: Open (partial revert; calibration question unresolved)
**Primary file**: `flutter/lib/data/constants/face_reference_data.dart`

---

## TL;DR

얼굴형 분류(`표준 / 세로로 긴 / 가로로 넓은`)가 특정 사용자(이수지 스타일의 동글동글한 한국 여성 얼굴)에서 "표준"으로 나오지만, 시각적으로는 "가로로 넓은 얼굴"이 자연스러운 판단인 경우가 있음. 이번 세션에서 reference mean과 임계값을 흔들어 해결을 시도했지만 false positive를 유발하여 모두 원복했고, 결과적으로 **구조적 원인(4명 연예인 기반 reference 캘리브레이션)은 남아있는 상태**.

---

## 현재 코드 상태 (이번 세션 종료 시점)

### 복구된 파일 — dc15c13 "add 3/4 shot" 커밋과 동일
1. `flutter/lib/data/constants/face_reference_data.dart` — faceAspectRatio reference
   - 여성 East Asian: `MetricReference(1.29, 0.07)`
   - 남성 East Asian: `MetricReference(1.32, 0.07)`
2. `flutter/lib/presentation/screens/physiognomy/physiognomy_screen.dart::_faceShape()`
   - `z > 1.0` → 세로로 긴 얼굴형
   - `z < -1.0` → 가로로 넓은 얼굴형
   - 그 외 → 표준 얼굴형
   - **추가된 디버그 로그** (분류 근거 출력)

### 남아있는 이번 세션 변경 (측정/분류와 무관, 다른 이슈 해결용)
- `attribute_engine.dart`: 60개 interaction rule 임계값 `>=1` → `>=2`로 상향 (단정적 문구 발동 조건 강화)
- `face_metrics.dart::nasalWidthRatio`: debugPrint 추가
- `rule_text_blocks.dart`: 내용 변경 없음
- UI 관련: 앨범 2단계 업로드 flow, top snackbar 표시/숨김, 아이콘 변경 등

---

## 증상

### 케이스: 이수지 (한국 여성 개그우먼, 동글동글 통통한 얼굴)
- 소스 사진: TV 화면 캡처 (사람이 좋다, 거의 정면, 표정 차분)
- 측정값: `faceHeight=0.5278, faceWidth=0.4468`
- corrected `faceAspectRatio` = `0.5278/0.4468 × aspectCorrection(1.0189) × landmark10Correction(1.05) = 1.2637`
- 현재 ref (여성 1.29, SD 0.07) 대비 z = `-0.38`
- **시스템 판정**: "표준 얼굴형"
- **사용자 기대**: "가로로 넓은 얼굴형"
- 시각적 관찰: 볼살/턱살 풍부, 광대 발달 → "가로로 넓음"이 직관적

### 사용자가 보고한 2차 증상 (세션 중 제가 만든 것, 모두 원복됨)
1. "가로로 넓은 얼굴형이 표준형으로 나와야 하는 얼굴에서도 나온다" — `_faceShape` 임계값을 |z|>0.5로 공격적으로 완화한 결과. 원복됨.
2. "전부 약간 가로로 넓은 얼굴로 나온다" — 5-tier (0.5~1.0에 "약간" 라벨) 도입 결과. 원복됨.

---

## 근본 원인 분석

### 1. Reference mean 캘리브레이션의 샘플 편향
`face_reference_data.dart` 코드 주석에 남은 기록:
```
// Calibrated from 4 real Flutter measurements:
//   Suji=1.211 (가로) Rose=1.228 (표준) IU=1.311 (표준) Doyeon=1.374 (세로)
// mean=1.29, sd=0.07 puts Suji at z=-1.13, Doyeon at z=+1.20.
```

- 샘플 4명 모두 **여성 연예인** = 시각적으로 매력적인/갸름한 얼굴에 편중
- 일반 한국 여성 대중은 평균이 연예인 mean보다 **낮은** 쪽(=더 가로형)일 가능성 높음
- 이수지 raw 1.2637은 연예인 기준에선 "표준에 살짝 가로", 일반인 기준에선 "평균적 가로"일 수 있음

### 2. MediaPipe 랜드마크 + 보정 계수의 구조적 한계
- `landmark 10`(foreheadTop)은 실제 헤어라인 아닌 이마 중상부 → faceHeight 과소측정
- 대응: `kLandmark10Correction = 1.05` 적용 (`face_analysis.dart`)
- `aspectCorrection = imageHeight / imageWidth`도 적용
- 그래도 해부학적 정확도는 제한적

### 3. z-score 임계값의 이산성
- |z|≤1.0은 모집단 ~68%를 포함 → "표준" 범위가 넓음
- 경계선(|z|=0.5~1.0) 케이스는 사용자 직관과 불일치 가능
- 중간 티어("약간 ___") 도입은 잠재 해법이지만 임계값 선정이 critical (이번 세션에서 0.5~1.0이 너무 넓음을 확인)

---

## 디버그 로그

이번 세션에 추가한 로그. 재현 시 이것들 모아주면 분석 가능:

### `face_analysis.dart` (기존)
```
[Analysis] faceAspectRatio raw=<v> faceH=<v> faceW=<v> aspectCorrection=<v> landmark10Correction=1.05
[Analysis] faceAspectRatio z=<v> ref mean=<v> sd=<v>
```

### `face_metrics.dart::nasalWidthRatio` (이번 세션 추가)
```
[NasalWidthDebug] alaWidth=<v> icd=<v> ratio=<v> (landmarks: rAla=98 lAla=327 rEndo=133 lEndo=362)
```

### `face_analysis.dart::[NOSE CLASSIFICATION]` (기존)
```
══════════ [NOSE CLASSIFICATION] ══════════
  frontal.nasalWidth  score=<s>  wideNose=<bool>  narrowNose=<bool>
  ...
```

### `physiognomy_screen.dart::[FACE SHAPE]` (이번 세션 추가)
```
══════════ [FACE SHAPE] ══════════
  gender=<g> ethnicity=<e>
  faceAspectRatio: raw=<v> z=<v>
  decision: <rule> → "<label>"
═══════════════════════════════════
```

---

## 이수지 케이스 실측 데이터 (세션 중 수집)

```
raw faceAspectRatio (corrected) = 1.2637
faceHeight = 0.5278
faceWidth  = 0.4468
aspectCorrection = 1.0189 (imageHeight/imageWidth)
landmark10Correction = 1.05

z (ref mean=1.29, sd=0.07) = -0.3751
→ 표준 얼굴형

raw nasalWidthRatio = 0.9772
  alaWidth = 0.10175
  icd      = 0.10412
z (ref female EA, mean=0.98, sd=0.10) = -0.028
→ 평범형 (nose classification score=1, wideNose=false)
```

---

## 해결 방향 (다음 세션에서 해야 할 일)

### 옵션 A: Reference mean 재캘리브레이션
**실측 데이터 수집이 전제**. 일반 사용자 얼굴 20~30명 raw faceAspectRatio 분포를 수집:
```
1. 앱에서 측정 실행, 로그의 [Analysis] faceAspectRatio raw=... 값 수집
2. 성별별로 그룹화 → mean, SD 계산
3. `face_reference_data.dart`의 East Asian mean/SD 업데이트
4. 4개 연예인 샘플도 여전히 합리적 z-range에 있는지 검증
5. 이수지 raw 1.2637이 z < -1.0 에 떨어지는지 확인
```

### 옵션 B: 중간 티어 재도입 (보수적 임계값)
- |z|>1.5 → 단정적 라벨 (지금의 >1.0 대신)
- 1.0<|z|≤1.5 → "약간 ___"
- |z|≤1.0 → "표준"
- 이수지 z=-0.38은 여전히 표준이므로 개별 케이스는 해결 안 됨.

### 옵션 C: 다변량 얼굴형 판정
- faceAspectRatio 단독이 아니라 `faceTaperRatio`, `gonialAngle`, `lowerFaceRatio` 가중합
- 이수지처럼 H/W는 평범하지만 볼살·둥근 턱이 두드러진 경우를 잡아냄
- 구현 비용 큼, 리포트 UX 재설계 필요

### 옵션 D: 지금 상태 유지
- 현재(dc15c13 동작)가 대다수 사용자에 대해 합리적
- 이수지급 edge case는 실측 데이터 없이 건드리지 않음

---

## 이번 세션 주요 실수

1. **개별 케이스 하나(이수지)를 고치려 reference mean을 흔들어** 다른 캘리브레이션 케이스(Rose, IU)에 부작용.
2. **`_faceShape` 임계값을 |z|>0.5로 완화**한 뒤 false positive (정상 얼굴이 "가로넓음") 발생. 되돌림.
3. **5-tier "약간" 티어를 |z|>0.5에 도입**한 뒤 ~40% 얼굴이 "약간 가로넓음"으로 쏠림. 되돌림.
4. **실측 데이터 없이 추정으로 캘리브레이션 흔듬**. 이후 수정 플랜에선 **실측 수집 → 재캘리브레이션** 순서를 엄수해야 함.

---

## 관련 파일 빠른 참조

| 역할 | 경로 |
|------|------|
| faceAspectRatio 계산 | `flutter/lib/domain/services/face_metrics.dart:92` |
| faceAspectRatio 보정 | `flutter/lib/domain/models/face_analysis.dart:39-52` |
| Reference 데이터 | `flutter/lib/data/constants/face_reference_data.dart:183,206` (East Asian male/female) |
| _faceShape 분류 | `flutter/lib/presentation/screens/physiognomy/physiognomy_screen.dart::_faceShape` |
| 얼굴형 라벨 표시 | `physiognomy_screen.dart:build` (`report.alias ?? _faceShape()`) |

---

## 다음 세션 시작 트리거

이 파일 경로를 다른 PC에서 `cat /Users/chuck/Code/face/FACEBUG.md`로 확인 후,
Claude에 다음 메시지 전달:

> "FACEBUG.md 읽고 현재 상태 확인. 다음 단계는 [옵션 A/B/C/D 중 선택] 진행."

또는 먼저 실측 데이터 수집할 경우:

> "FACEBUG.md 확인했고, 이제 사용자 얼굴 N명 raw faceAspectRatio 값을 수집해서 붙일 테니 재캘리브레이션 계산해줘."
