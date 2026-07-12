# face_shape_ml — 운영 가이드

서로 독립된 두 파이프라인. landmark 추출(`extract_landmarks.py::compute_ratios`)만 공유.

| | ① 얼굴형 분류기 | ② referenceData 재보정 |
|---|---|---|
| 하는 일 | 사진 → 5-class (Heart/Oblong/Oval/Round/Square) | 26 metric 인구 μ/σ 산출 |
| 소비처 | `flutter/assets/ml/face_shape_ratios.tflite` | `face_reference_data.dart::referenceData` |
| 데이터 | niten19 4000 + user 57 EA | EA: AAF 11,800 · 비-EA: niten19 5,000 |
| 스크립트 | `train_28feat_eastasian.py` → `export_tflite.py` | `extract_aaf.py` · `extract_niten_reference.py` |

②는 ①을 대체하지 않는다 — 관상 z-score 기준선 재보정일 뿐, 분류기는 그대로 동작.

## ① 얼굴형 분류기

- 28-feature MLP: Dense(64)→Dropout(0.3)→Dense(32)→Dropout(0.2)→Dense(5, softmax).
  TFLite float32 18.2 KB, on-device ~1-3ms (`face_shape_classifier.dart`).
- 입력 28 ratio = `face_metrics.dart::computeAll()` 의 Python parity.
- 현재 성능: user 57 train 75.4% / honest 5-fold CV 47.6%. `_priorRatio` = uniform
  (EA 보정이 학습 단에 내장 — prior 중복 적용 시 정확도 하락).
- 배포물: `flutter/assets/ml/face_shape_ratios.tflite` + `scaler.json`(mu/sd/feature_names).

### 재학습 → 배포 절차

새 라벨 사진: `/tmp/{gender}-{type}-{n}.{ext}` (gender=male|female,
type=heart|oblong|oval|round|square). 정면·무표정·얼굴 25%+ 만, 애매한 경계 case 는
라벨링하지 않는다.

```bash
cd /Users/chuck/Code/face
VENV=tools/.venv/bin/python    # 3.11 (tensorflow·kagglehub·mediapipe·scikit-learn·opencv)

$VENV tools/face_shape_ml/extract_landmarks.py        # (1) niten19 28-feat (out/landmarks.npz 있으면 skip)
$VENV tools/face_shape_ml/extract_user_features.py    # (2) 사용자 사진 → user_features.csv
$VENV tools/face_shape_ml/train_28feat_eastasian.py   # (3) 학습 + 5-fold CV (~30분)
# 5-fold ≥ 0.55 면 배포 진행, ~0.48 이면 데이터 보강 우선
$VENV tools/face_shape_ml/eval_mlp_eastasian.py       # (4) user 평가 sanity check
$VENV tools/face_shape_ml/eval_with_prior.py          # (5, 선택) prior 4종 비교 — 우월 시 _priorRatio 갱신
$VENV tools/face_shape_ml/export_tflite.py            # (6) TFLite 변환 + bit-exactness 검증 + Flutter assets 자동 배포
```

Flutter 검증:

```bash
cd flutter && flutter test test/face_shape_posterior_test.dart && flutter test
flutter run   # 실기: [FaceShapeClassifier] raw→posterior→label 로그 확인
```

배포 전 backup 권장: `face_shape_ratios.tflite`·`scaler.json` 을 `.backup-$(date +%Y%m%d)` 로 복사.
롤백 = backup 복원 + `_priorRatio` 이전 값.

### 디버깅

- `probe_photo.py /path/to.jpg` — 한 장 진단 (28 feat + z + softmax + posterior).
- `batch_report.py` — `/tmp` 라벨 샘플 일괄 평가.
- Flutter ↔ Python 예측 불일치 시: `computeAll()` vs `compute_ratios()` 공식,
  scaler.json mu/sd·feature 순서 일치 확인. 앨범 오분류는 square-padding
  (`album_capture_page.dart::_processAlbumPhoto`) 회귀 여부 확인.

## ② referenceData 재보정

metric 의미·z 해석은 `RECALIBRATION-metrics-spec.md`. 여기는 실행 절차만.

**EA (AAF)** — 입력 `datasets/AAF/All-Age-Faces Dataset/original images/*.jpg`
(id ≤ 7380 = female), near-frontal 필터 |yaw|,|pitch| < 18°:

```bash
$VENV tools/face_shape_ml/extract_aaf.py --limit 80   # smoke
$VENV tools/face_shape_ml/extract_aaf.py              # full (11,800장)
```

산출 `out/aaf_referenceData.dart.txt` 의 `Ethnicity.eastAsian` 블록을
`face_reference_data.dart::referenceData` 의 eastAsian cell 에만 반영 —
**gender 분리 유지** (dimorphism 큼).

**비-EA 5인종 (niten19)** — 동일 파이프라인 in-frame 재측정, gender-pooled 단일 baseline:

```bash
$VENV tools/face_shape_ml/extract_niten_reference.py --limit 80   # smoke
$VENV tools/face_shape_ml/extract_niten_reference.py              # full (~5000장)
```

산출 `out/niten_referenceData.dart.txt` 5 블록을 해당 cell 에 반영 (frontal 26 만 —
**lateral 8 은 정면 측정 불가, 임상 추정 유지**).

**공통 검증**: `cd flutter && flutter test test/calibration_test.dart` (quantile 재생성)
→ `archetype_fairness_test`·`score_distribution_test` green.
