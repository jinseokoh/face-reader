# 리포 히스토리 재작성 기록 (2026-04-17)

## 무슨 일이 있었나

커밋 `12161bb add face analysis`에서 다음 두 묶음을 실수로 git에 커밋했음:

1. **Kaggle 원본 데이터** — `tools/datasets/kaggle_cache/datasets/niten19/face-shape-dataset/` (수천 장의 JPG, 수백 MB)
2. **ML 학습 산출물** — `tools/face_shape_ml/out/` (학습된 모델 `.keras` / `.tflite`, 랜드마크 `.npz` 등, 수십 MB)

다음 커밋 `1e32fe2 update docs`에서 일부만 지웠지만 **git 히스토리에는 blob이 그대로 남아** `.git` 폴더가 **783MB**까지 불어났음 (clone/push가 느려짐).

## 이번에 한 작업 (PC1)

1. 안전용 bundle 백업: `~/face-backup-20260417-133346.bundle` (768MB)
2. `git filter-repo --path tools/datasets/kaggle_cache/ --path tools/face_shape_ml/out/ --invert-paths` 로 두 경로를 **전체 히스토리에서 제거**
3. `git gc --prune=now --aggressive` 로 미참조 blob 정리 → **`.git` 47MB**로 축소
4. `.gitignore`에 두 경로 추가 (다시는 커밋 안 되도록)
5. `tools/datasets/download_kaggle.sh` 작성 — Kaggle 데이터 재다운로드 스크립트
6. `origin` remote 재등록 후 `git push --force origin main`

> ⚠️ **히스토리가 재작성되었기 때문에 모든 커밋의 SHA가 바뀜.** `main` 브랜치 강제 푸시됨.

## PC2에서 해야 할 일

**중요: 시작하기 전에 PC2의 워킹트리에 uncommitted 변경사항이 있으면 먼저 커밋/백업해두세요.** 아래 명령은 로컬 `main`을 리모트와 일치시키기 위해 기존 로컬 작업을 날립니다.

### 방법 A (권장): 새로 clone

가장 깨끗함. 기존 폴더는 통째로 지우고 다시 받음.

```bash
# 기존 폴더에서 필요한 uncommit 작업/설정 파일 (.env 등)을 먼저 빼두고
cd /path/to/parent
rm -rf face
git clone git@github.com:jinseokoh/face-reader.git face
cd face
```

### 방법 B: 기존 clone을 재작성된 히스토리로 맞추기

```bash
cd /path/to/face
# 1) 혹시 모를 로컬 작업 먼저 확인
git status
git stash  # 필요하면

# 2) 리모트 재작성된 히스토리 가져오기
git fetch origin

# 3) 로컬 main을 리모트에 완전히 맞춤 (※ 로컬 커밋 있으면 날아감)
git checkout main
git reset --hard origin/main

# 4) 구 blob을 로컬 pack에서 정리
git reflog expire --expire=now --all
git gc --prune=now --aggressive
```

이 시점에 `.git` 폴더가 ~47MB 수준으로 작아지면 정상.

### Kaggle 데이터 다시 받기 (학습/재학습할 때만)

CNN 재학습(`tools/face_shape_ml/train_cnn.py` 등)이 필요하면 그때 받으면 됨. 앱 실행만 할 거면 필요 없음.

```bash
# 1) Kaggle API 토큰 준비: https://www.kaggle.com/settings → Create New API Token
#    받은 kaggle.json을 ~/.kaggle/kaggle.json 에 저장, chmod 600
# 2) kagglehub 설치
pip install kagglehub
# 3) 다운로드
bash tools/datasets/download_kaggle.sh
```

다운로드 완료 후 `tools/face_shape_ml/extract_landmarks.py` → `train_cnn.py` 순서로 돌리면 `tools/face_shape_ml/out/` 에 학습 산출물이 다시 생성됨.

## 앞으로의 원칙

- **Kaggle 원본 데이터는 절대 git에 커밋하지 말 것.** `tools/datasets/kaggle_cache/`는 `.gitignore` 걸어뒀음.
- **학습 산출물(`tools/face_shape_ml/out/`)도 커밋 금지.** 재생성 가능함. 앱에서 실제로 쓰는 모델 파일은 `flutter/assets/ml/` 경로에 명시적으로 커밋 (현재 `face_shape_ratios.tflite`, `scaler.json`).
- 큰 바이너리를 꼭 추적해야 하면 Git LFS 고려.
