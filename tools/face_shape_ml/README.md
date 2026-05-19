# Face Shape Classifier — 재학습 · 배포 운영 가이드

Flutter on-device 28-feature MLP 분류기의 학습 · 평가 · TFLite 배포 전체 파이프라인. East Asian deployment 정확도가 baseline 47.4% 에서 75.4% (train) / 47.6% (honest 5-fold CV) 로 정착된 현재 모델의 SSOT.

---

## 1. 모델 개요

- **architecture**: 28-feature input → Dense(64) → Dropout(0.3) → Dense(32) → Dropout(0.2) → Dense(5, softmax)
- **input**: 28 facial ratios from MediaPipe Face Mesh 468 landmarks (`face_metrics.dart::computeAll()` 의 Python parity)
- **output**: softmax over [Heart, Oblong, Oval, Round, Square]
- **학습 데이터**: niten19 4000 (Kaggle face-shape-dataset training_set) + 사용자 57 East Asian 라벨
- **size**: 18.2 KB (TFLite float32)
- **runtime**: Flutter `tflite_flutter`, on-device, ~1-3ms 추론

배포 위치:
```
flutter/assets/ml/face_shape_ratios.tflite   ← 모델 weight
flutter/assets/ml/scaler.json                 ← input z-score 통계 (mu, sd, feature_names)
```

런타임 코드: `flutter/lib/data/services/face_shape_classifier.dart`

---

## 2. 현재 성능 (2026-05-19 기준)

| metric | 값 |
|---|---|
| niten19 holdout (1000장) | ~80% |
| User 57 East Asian train accuracy | **75.4%** |
| User 57 honest 5-fold CV | **47.6%** |
| Class with weakest recall | Heart (20%, train) — only 5 user samples |

per-class confusion (final model, user 57 train):

```
true\pred     Heart  Oblong   Oval   Round  Square
Heart           1       0       4      0       0
Oblong          0      13       1      1       0
Oval            1       3      15      3       0
Round           0       0       0      7       1
Square          0       0       0      0       7
```

`_priorRatio` 는 uniform `[1,1,1,1,1]` — 모델이 학습 단에서 East Asian 보정 내장이므로 추가 prior 적용 시 이중 보정으로 정확도 하락 (실측: prior 적용 시 64.9% / uniform 75.4%).

---

## 3. 디렉토리 구조

```
tools/face_shape_ml/
├── README.md                           ← 본 문서
├── extract_landmarks.py                 # niten19 5000장 → 28-feat + landmarks NPZ
├── extract_user_features.py             # /tmp/{gender}-{type}-{n}.* → user_features.csv
├── train_28feat_eastasian.py            # niten19 + user mixed MLP 학습 (Strategy A/B/C)
├── export_tflite.py                     # Keras → TFLite + Flutter assets 배포 + parity 검증
├── eval_mlp_eastasian.py                # 새 모델로 user 57 평가 (top-1/top-2 + confusion)
├── eval_with_prior.py                   # prior 변형 4종 비교 (P0 기존 / P1 uniform 등)
├── batch_report.py                      # /tmp 의 male/female 라벨된 샘플 일괄 평가
├── probe_photo.py                       # 한 장의 사진을 Flutter parity 로 진단
└── out/                                  # 모든 중간/최종 산출물
    ├── landmarks.npz                    # niten19 5000장 28-feat + label
    ├── user_features.csv                # 사용자 57장 28-feat + label
    ├── mlp_eastasian_final.keras        # 학습된 최종 Keras 모델 (배포 source)
    ├── mlp_eastasian_scaler.json        # mu/sd (scaler.json 의 source)
    └── face_shape_ratios.tflite         # TFLite 변환 결과 (Flutter 배포 source)
```

---

## 4. 새 데이터 추가 → 재학습 → 배포 (전체 procedure)

### 4.1 준비

가상환경:
```bash
/Users/chuck/Code/face/tools/.venv/bin/python --version  # 3.11
# 필요 패키지: tensorflow, kagglehub, mediapipe, scikit-learn, opencv-python
```

niten19 dataset (이미 cache 됨):
```
~/.cache/kagglehub/datasets/niten19/face-shape-dataset/versions/2/FaceShape Dataset/
```
새로 다운로드해야 하면 `kagglehub.dataset_download("niten19/face-shape-dataset")`.

### 4.2 새 라벨된 사진 추가

파일명 규칙: `/tmp/{gender}-{type}-{n}.{ext}`
- gender: `male` | `female`
- type: `heart` | `oblong` | `oval` | `round` | `square`
- n: 같은 type 안에서 1, 2, 3 ... 으로 unique
- ext: `png` | `jpg` | `jpeg`

예시:
```
/tmp/male-oval-9.jpg
/tmp/female-heart-3.png
/tmp/female-square-4.jpeg
```

권장 수량 (현 57장 기준):
- 한 type 당 **최소 40-50장** 도달 시 5-fold CV 정확도 55-65% 기대
- 한 type 당 **100-200장** 도달 시 65-75% 기대
- 영구 보존하려면 `/tmp` 가 아니라 repo 하위 (예: `tools/face_shape_ml/labeled_samples/`) 로 옮기고 path 갱신

### 4.3 재학습 (60-90분)

```bash
cd /Users/chuck/Code/face
VENV=tools/.venv/bin/python

# (1) niten19 28-feat 재추출 (~10분, 이미 out/landmarks.npz 있으면 skip 가능)
$VENV tools/face_shape_ml/extract_landmarks.py

# (2) 사용자 사진 28-feat 추출 (~10초)
$VENV tools/face_shape_ml/extract_user_features.py

# (3) MLP 3 strategy 학습 + 5-fold CV (~30분)
$VENV tools/face_shape_ml/train_28feat_eastasian.py 2>&1 | tee /tmp/train.log

# 출력 마지막 부분 확인:
#   [BEST] Strategy ?: 0.XXX
#   saved: out/mlp_eastasian_final.keras
#   saved: out/mlp_eastasian_scaler.json
```

honest 5-fold CV 결과 (`5-fold mean = X.XXX`) 가 현재 baseline (0.476) 보다 **충분히 높으면** 배포 진행. 예:
- 5-fold ≥ 0.55 → 배포 OK
- 5-fold ~ 0.48 → 배포 효과 미미, 데이터 더 모으는 게 우선

### 4.4 사용자 사진 일괄 평가 (sanity check)

```bash
$VENV tools/face_shape_ml/eval_mlp_eastasian.py
```

per-photo top-1 / top-2 table + confusion matrix 출력. 사용자 의도와 분류가 큰 격차면 라벨 quality 재검토.

### 4.5 prior 변형 비교 (선택)

```bash
$VENV tools/face_shape_ml/eval_with_prior.py
```

4가지 prior 조합 (P0 기존 / P1 uniform / P2 약한 / P3 user-dist) 비교. 새 모델에선 보통 P1 uniform 이 가장 좋음 (모델이 East Asian 분포 학습 내장).

만약 다른 prior 가 1pt 이상 우월하면 `face_shape_classifier.dart::_priorRatio` 갱신:
```dart
static const List<double> _priorRatio = [
  X.X, // heart
  X.X, // oblong
  X.X, // oval
  X.X, // round
  X.X, // square
];
```

### 4.6 TFLite 변환 + Flutter 배포 (자동)

```bash
$VENV tools/face_shape_ml/export_tflite.py
```

자동 수행:
1. `mlp_eastasian_final.keras` → TFLite float32 변환
2. Keras vs TFLite **bit-exactness** 검증 (max diff < 1e-3 요구)
3. `scaler.json` schema validation (feature_names 일치)
4. `flutter/assets/ml/face_shape_ratios.tflite` + `scaler.json` 덮어쓰기
5. user 57장 TFLite 추론 → confusion matrix 출력

검증 시 자동 출력되는 로그:
```
[3] verifying Keras vs TFLite bit-exactness
  max |keras - tflite|: 0.000000
  ✓ within tolerance
  argmax agreement: 57/57
```

### 4.7 Flutter 측 검증

```bash
cd flutter
flutter analyze lib/data/services/face_shape_classifier.dart test/face_shape_posterior_test.dart
flutter test test/face_shape_posterior_test.dart
flutter test  # 전체 회귀
```

**주의**: 새 모델의 raw softmax 분포가 변하면 `face_shape_posterior_test.dart` 의 snapshot test 가 실패할 수 있다. 그 경우:
- 기존 test 가 prior 동작을 검증하는 거면 → 새 prior 에 맞는 expected value 로 갱신
- 모델이 East Asian 보정 내장이라 uniform prior 면 → snapshot test 는 raw passthrough 검증만 유지

### 4.8 hot-restart + 실기 검증

```bash
flutter run  # 또는 hot restart (Shift+R)
```

device 에서 사용자 사진 한 장 album 으로 분석 → console 에서 다음 두 라인 확인:
```
[FaceShapeClassifier] raw=...,...,...,...,... → posterior=...,...,...,...,... → Oval(0.XX)
[FACE SHAPE CNN] label=Oval conf=0.XX → oval
```

분류 결과가 expected 면 PR 가능. 어긋나면 사진 path 를 받아 `probe_photo.py` 로 raw softmax 확인 후 라벨 재검토.

### 4.9 Rollback

배포 후 사용자 보고로 회귀 발견 시:
```bash
cp flutter/assets/ml/face_shape_ratios.tflite.backup-niten19 \
   flutter/assets/ml/face_shape_ratios.tflite
cp flutter/assets/ml/scaler.json.backup-niten19 \
   flutter/assets/ml/scaler.json
```

`face_shape_classifier.dart::_priorRatio` 도 이전 값으로 복원.

매번 배포 전에 새 backup 파일 생성 권장:
```bash
DATE=$(date +%Y%m%d)
cp flutter/assets/ml/face_shape_ratios.tflite flutter/assets/ml/face_shape_ratios.tflite.backup-$DATE
cp flutter/assets/ml/scaler.json flutter/assets/ml/scaler.json.backup-$DATE
```

---

## 5. 디버깅 도구

### 5.1 한 장의 사진 진단

```bash
$VENV tools/face_shape_ml/probe_photo.py /path/to/photo.jpg
```

출력:
- 28 feature 값 + z-score (현 scaler.json 기준)
- 모델 raw softmax 5-class
- prior 적용 후 posterior
- 최종 라벨

사용자가 "이 사진이 잘못 분류된다" 보고할 때 이 script 로 raw softmax 가 어떻게 나오는지 직접 측정 후 라벨 재검토 / 데이터 보강 여부 판단.

### 5.2 일괄 평가

```bash
$VENV tools/face_shape_ml/batch_report.py
```

`/tmp/{gender}-{type}-{n}.*` 전체에 대해 3가지 prior 조합 비교 (raw / female / male).

### 5.3 Flutter parity 확인

`face_shape_classifier.dart::predict()` 의 input feature 값과 `probe_photo.py` 출력값이 일치해야 한다. 어긋나면:
- `face_metrics.dart::computeAll()` 의 ratio 공식과 `extract_landmarks.py::compute_ratios()` 의 공식이 다른지 확인
- scaler.json mu/sd 가 일치하는지 확인

---

## 6. 학습 데이터 보강 가이드

### 6.1 무엇이 부족한가

현재 user 57장 class 분포:
```
heart   5 ← 매우 부족
oblong  15
oval    22
round   8 ← 부족
square  7 ← 부족
```

heart/round/square 각 class 당 추가 30-50장 우선. oval 도 50+ 까지는 추가 권장.

### 6.2 라벨 quality 가이드

face shape 분류는 **경계가 흐릿한** 경우가 많다. 한 명을 한 type 으로 강제 분류 시 노이즈가 생기므로, 명확한 case 만 라벨링:

- **Heart**: 이마 넓음 + 턱 좁고 뾰족. V-line.
- **Oblong**: 세로 길이가 가로의 1.5배 이상. 직사각형 비율.
- **Oval**: 이상적 계란형. 이마 = 광대 = 턱 비율 균등하고 부드러운 곡선.
- **Round**: 가로 ≒ 세로. 광대 부분이 가장 넓고 둥근 곡선.
- **Square**: 가로 ≒ 세로. 턱이 각짐 (gonial angle 작음). 광대도 뚜렷.

애매한 case (oval/oblong, oval/round 경계) 는 라벨링하지 않거나 **2-3명 합의** 후 추가.

### 6.3 데이터 다양성

- **각도**: 정면 사진만 (90° frontal). 측면/45° 는 제외.
- **표정**: 무표정 또는 약한 미소. 큰 표정 (입 벌림, 눈썹 들림) 은 제외.
- **조명**: 균일하면 무엇이든 OK. 측면 광원으로 그림자 강하면 제외.
- **여백**: 사진 안에 얼굴이 충분히 크게 차지 (전체 면적 25% 이상).
- **occlusion**: 머리카락이 이마/턱을 가리면 제외. 안경 OK, 마스크 제외.

### 6.4 데이터 source 후보

- **개인 사진**: 가장 정확. 라벨 quality 가장 높음.
- **공개 dataset**: AFAD-Lite (60K East Asian) — 라벨 face shape 없음, 본인이 추가 라벨.
- **scrape**: 구글/네이버 "동아시아 oval 얼굴" 검색. 라이센스 주의 (research only).
- **AI 생성**: Stable Diffusion 등으로 type 별 합성. 일부 학계는 distribution shift 우려, 보조 데이터로만 사용.

---

## 7. 트러블슈팅

### 모델 학습 시 stuck (val accuracy 정체)

- `train_28feat_eastasian.py` 의 `epochs`, `lr`, `class_weight` 확인.
- niten19 28-feat NPZ 가 정상인지 (`out/landmarks.npz` 크기 ~28 MB, 5000 sample) 확인.
- niten19 추출 실패 시 path 확인 (`~/.cache/kagglehub/...`).

### TFLite 변환 후 정확도 하락

- `export_tflite.py` 의 max diff > 1e-3 면 변환 자체 문제. Quantization 끄고 float32 유지 확인.
- argmax agreement 가 57/57 미만이면 deploy 금지.

### Flutter 앱에서 prediction 결과 ↔ Python eval 결과 불일치

- scaler.json mu/sd 가 양쪽 동일한지 확인.
- `face_metrics.dart::computeAll()` 의 feature 순서 (28개) 가 `scaler.json::feature_names` 와 일치하는지 확인.
- MediaPipe Flutter native (`mediapipe_face_mesh`) 와 Python `mediapipe.tasks.vision.FaceLandmarker` 의 landmark 차이는 일반적으로 ±1% 이내. 그 이상이면 face detection alignment 차이일 수 있음.

### 사용자 사진이 album 에서 oblong 으로 잘못 분류

이전에 9:20 phone screenshot 의 non-square aspect 이슈가 있었음. Fix 적용된 코드는 `album_capture_page.dart::_processAlbumPhoto` 에서 square-padding 처리. 회귀하면 그 부분 확인.

### Heart class 가 한 번도 정답 안 나옴

데이터 부족 (5장). Heart 라벨 30+ 추가 후 재학습 필수. 학습 단의 class_weight 가 자동 적용되지만 sample size 가 너무 적으면 학습 자체 불가.

---

## 8. 향후 로드맵

### 단기 (East Asian 200+ 모이면)

1. 데이터 추가 → `extract_user_features.py` → `train_28feat_eastasian.py`
2. 5-fold CV 가 55% 도달하면 배포
3. honest 5-fold 기준 새 baseline 정착

### 중기 (East Asian 1000+ 모이면)

1. 28 feature 보강 후보:
   - temple-to-cheekbone 비율 (heart vs oval)
   - jaw-line gradient (square vs round)
   - chin width / forehead width (heart 특화)
2. 추가 feature 검증: 5-fold CV 증가 여부
3. MLP 깊이/너비 조정 (현 64-32 → 128-64-32 등) 실험

### 장기 (East Asian 2000+ 모이면)

1. CNN-based 시도 — MobileNetV2 등을 niten19 + East Asian 합쳐 학습
2. server-side 추론으로 전환 (DeepFace endpoint 에 face_shape action 추가)
3. on-device TFLite 는 fallback 으로 유지 (오프라인 동작 보장)

---

## 9. 변경 이력

| 날짜 | 변경 | accuracy 영향 |
|---|---|---|
| 2026-05-18 | niten19 only 학습 (초기) | East Asian 47.4% |
| 2026-05-18 | East Asian prior [0.4,0.6,2.5,1.0,0.5] 도입 | 47.4% (oblong 남발 해소) |
| 2026-05-19 | niten19 + user 57 mixed 학습, uniform prior | 75.4% (train) / 47.6% (CV) |
