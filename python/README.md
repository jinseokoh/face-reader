# Face Metadata 추론 서비스

얼굴 사진 URL 을 받아 **나이/성별/인종**만 돌려주는 FastAPI + DeepFace 추론 API (CPU only).
이미지는 직접 업로드받지 않는다 — 앱이 R2 `temp/` 에 올린 뒤 URL 만 전달.

```
앱 ─(720px 리사이즈)─▶ R2 temp/ ─URL─▶ POST /analyze ─▶ DeepFace.analyze
                                          → { age, gender, ethnicity }
```

- detector 기본 `opencv`. 시작 시 1회 워밍업 (기동 후 ~30초 뒤 트래픽 수용).
- 첫 실행 시 모델 가중치(~80MB) 자동 다운로드.

## 실행 (Docker)

```bash
cd python
docker compose build
docker compose up -d
docker compose logs -f
curl -s http://localhost:8000/health   # {"status":"ok"}
docker compose up -d --build           # 코드 변경 후 재빌드+재기동
```

## API

### `POST /analyze`

```json
요청: { "image_url": "https://.../face.jpg" }
성공: { "age": 28, "gender": "male", "ethnicity": "eastAsian" }
```

- `age` 정수(반올림) · `gender`/`ethnicity` 는 Flutter SSOT enum name 으로 정규화.

| DeepFace 원본 | 응답 |
|---|---|
| `Man` / `Woman` | `male` / `female` |
| `asian` | `eastAsian` |
| `white` | `caucasian` |
| `black` | `african` |
| `indian` | `southeastAsian` |
| `middle eastern` | `middleEastern` |
| `latino hispanic` | `hispanic` |

실패는 공통 구조 `{ "error": ..., "detail": ... }`:

| HTTP | error | 의미 |
|---|---|---|
| 400 | `download_failed` | URL 오류·비이미지 타입·파일 과대 (upload 측 Content-Type 은 image/* 필수) |
| 422 | `no_face_detected` | 얼굴 미검출 |
| 502 | `download_failed` | 원격(R2) 비정상 응답/네트워크 실패 |
| 500 | `internal_error` | 서버 오류 |

### `GET /health` → `{"status":"ok"}` (모델 미접촉 liveness)

## 환경 변수 (기본값으로 동작)

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `HOST` / `PORT` | `0.0.0.0` / `8000` | 바인딩 |
| `DOWNLOAD_TIMEOUT_SEC` | `15` | 이미지 다운로드 타임아웃 |
| `MAX_DOWNLOAD_MB` | `10` | 최대 이미지 크기 |
| `DETECTOR_BACKEND` | `opencv` | opencv/ssd/mtcnn/retinaface |
| `LOG_LEVEL` | `INFO` | 로깅 레벨 |

주의: TF 2.16+ Keras 3 비호환 → `tf-keras==2.16.0` pin + `TF_USE_LEGACY_KERAS=1`
(requirements.txt·Dockerfile 에 반영됨). 메모리 ~600MB 점유 — 2GB+ 인스턴스 권장.

## 파일 구조

```
python/app/
├── main.py                 # FastAPI 진입점 (/health · /analyze)
├── schemas.py              # Pydantic 모델
├── services/downloader.py  # httpx streaming 다운로드 + 검증
├── services/inference.py   # DeepFace 호출 + 워밍업
└── utils/config.py         # 환경변수 → Settings (다운로드 정책 포함)
```
