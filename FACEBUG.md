# FACEBUG — Face Shape Classification

**Last update**: 2026-04-16 (session 3)
**Status**: ✅ **RESOLVED** via data-first approach. Flutter 이식 완료. device 검증 남음.

---

## TL;DR

- Session 1~2 의 추측 기반 수정은 모두 실패 (이수지 round → long 오분류).
- Session 3: data-first 전환 → Python + MediaPipe + scikit-learn LDA로 재학습.
- 22장 라벨링 사진(5 wide / 8 standard / 9 long) + LOOCV 86.4% (19/22).
- 2단 hierarchical classifier 도출 → Flutter `_faceShape()` 이식 완료.

---

## 최종 분류 공식 (Flutter 이식됨)

```
Stage 1 — wide 탐지 (단순 임계값)
  isWide = faceTaperRatio > 0.7985
  (학습 gap: wide min 0.801 vs non-wide max 0.796)

Stage 2 — long vs standard (LDA, raw-value 언표준화)
  stage2 = 150.8780 × faceAspectRatio
         +  -0.4313 × gonialAngle
         + 309.9574 × upperFaceRatio
         + (-222.5233)
  isLong = stage2 > 0

else → standard
```

학습셋 stage2 분포 (clean gap):
- long: `[+1.28, +11.55]`
- standard: `[-11.37, -1.19]`

---

## 왜 이번엔 성공했나 (방법론 전환)

| 전 | 후 |
|---|---|
| 추측으로 weight/threshold 결정 | Python LDA가 데이터에서 도출 |
| reference z-score 의존 (ref mean/SD 틀리면 다 붕괴) | raw-value 공식 (ref 무관) |
| 단일 composite (4축 합산) | 2단 hierarchical (wide 판별 → long/std 판별) |
| 메트릭 노이즈 1개 = 분류 뒤집힘 | 학습셋 margin 검증 후 threshold 확정 |

### Stage 1이 LDA가 아니라 단순 임계값인 이유
3개 taper(`faceTaperRatio`/`taperJawLower`/`taperChinSide`)는 서로 높은 상관 → LDA 계수 부호 불안정. 사나(여배우5) 케이스에서 LDA가 `taperChinSide` 계수 −4.97을 뽑아 직관 반대로 갔음. 단순 `faceTaperRatio` 임계값이 학습 데이터에 clean gap 0.005 존재 → 가장 robust.

---

## 데이터 수집 프로세스 (기록)

```
/Users/chuck/Desktop/test/data/
  ├── wide/       (5장: 이수지, 김민경, 박나래, 이국주, 홍윤화)
  ├── standard/   (8장: 개발1, 여자1, 여자3, 여배우2, 배우1/2/3, 여배우3)
  └── long/       (9장: 태연, 긴얼굴남자1, 긴얼굴여자1/2/3, 얼굴긴여자4,
                         사나(여배우5), 여배우1, 여배우4)
```

수집 중 라벨 재검토 1회 (태연: standard → long, 아이유 정면 사진 1장 삭제),
분류기 예측 후 사용자 검증 2회 (사나 long 확정, 여배우2 standard 확정).

---

## 검증 상태

### LOOCV (학습셋 내부)
- Stage 1 (wide 탐지): **5/5 완벽**. 이수지 포함 전부 wide로 분류.
- Stage 2 (long vs standard): 14/17 = 82%. 남은 3장(여배우1·배우1·여자3) 모두 aspect 1.24~1.27 경계구역.
- 총합: **19/22 = 86.4%**.

### Device 검증 (남음 — 필수)
MediaPipe Flutter(TFLite) vs Python(Tasks API) 랜드마크 미세 차이 가능.
Stage 1 margin이 0.005로 얇아 실기에서 뒤집힐 수 있음.

**테스트 순서**:
1. 이수지 사진 → **wide** 나와야 함 (핵심 회귀 검증).
2. 사나(여배우5) → **long** 나와야 함 (경계 wide 오판정 방지 검증).
3. 여배우2 → **standard** 나와야 함 (경계 케이스 안정성).

각 raw 메트릭(faceTaperRatio, faceAspectRatio, gonialAngle, upperFaceRatio)의 **Python vs Flutter 값 차이가 ±0.005 이내**면 배포 OK. 큰 차이 있으면 threshold 재조정 필요.

---

## 관련 파일

| 역할 | 경로 |
|---|---|
| 분류 공식 (이식 완료) | `flutter/lib/presentation/screens/physiognomy/physiognomy_screen.dart::_faceShape` |
| 메트릭 계산 | `flutter/lib/domain/services/face_metrics.dart` |
| Python 학습 도구 | `tools/calibrate_face_shape.py` |
| Python 분류 도구 | `tools/classify_unlabeled.py` |
| MediaPipe 모델 | `tools/face_landmarker.task` |
| 학습 CSV 덤프 | `tools/out/face_calib.csv` |

---

## 재학습 방법 (필요시)

```bash
cd /Users/chuck/Code/face/tools
# 1. 라벨 폴더에 사진 추가 (wide/, long/, standard/)
# 2. 측면 사진은 파일명에 "측면" 포함 → 자동 필터
.venv/bin/python calibrate_face_shape.py
# → stage 1 threshold + stage 2 raw-value coefficients 출력
# 3. 출력된 계수를 physiognomy_screen.dart::_faceShape 상수에 반영
```

미분류 사진 검증:

```bash
.venv/bin/python classify_unlabeled.py          # dry-run
.venv/bin/python classify_unlabeled.py --move   # 자동 이동
```

---

## 과거 세션 기록 (archived)

Session 1: mean 1.29→1.35 조정 (표준 오분류만 해결, 이수지 미해결)
Session 2: 3축 → 4축 composite (lowerFaceFullness weight 2.0), 이수지에서 반대 방향 오분류
Session 3 (오늘): 데이터 기반 재학습 → 문제 종결.

자세한 세션 1~2 내용은 git log 참조.
