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

두 입력 형태. 인증은 둘 다 `X-Face-Token` + `X-Face-Key` (Cloudflare Worker 가 발급, §HMAC).

```
① multipart/form-data (앱·웹, Worker /api/analyze 가 중계)
   image=<JPEG/PNG/WebP bytes>  face_crop=1        ← 384px 정사각 얼굴 크롭이면 1 (검출 생략)
② application/json (옛 앱 계약 — 스토어 앱이 전부 갱신되면 제거)
   { "image_url": "https://.../temp/{uuid}.jpg" }  ← 720px 전체 사진, 분석 뒤 R2 temp 즉시 DELETE

성공: { "age": 28, "gender": "male", "ethnicity": "eastAsian", "ageModel": "mivolo_v2" }
```

- `age`·`gender` 는 **MiVOLO v2** (tools/face_shape_ml/README.md ③ — AAF 성인 MAE 6.1세, 성별 99%).
  `ethnicity` 는 DeepFace race 헤드. 두 모델은 스레드 둘로 동시에 돈다.
- 전체 사진(②·`face_crop=0`)은 DeepFace opencv 검출 박스를 `CROP_MARGIN` 만큼 넓힌
  정사각 크롭을 MiVOLO 에 넣는다. 앱·웹이 보내는 크롭도 같은 규격이어야 한다.
- `ageModel` 은 카드에 남긴다 — 어느 식이 낸 나이인지 추적 (APPLE.md §58 원칙).
- `gender`/`ethnicity` 는 Flutter SSOT enum name 으로 정규화.

| DeepFace race 원본 | 응답 |
|---|---|
| `asian` | `eastAsian` |
| `white` | `caucasian` |
| `black` | `african` |
| `indian` | `southeastAsian` |
| `middle eastern` | `middleEastern` |
| `latino hispanic` | `hispanic` |

실패는 공통 구조 `{ "error": ..., "detail": ... }`:

| HTTP | error | 의미 |
|---|---|---|
| 400 | `download_failed` / `bad_request` | URL 오류·비이미지 타입·파일 과대 (upload 측 Content-Type 은 image/* 필수) / multipart `image` 누락·JSON 오류 |
| 413 | `upload_too_large` | multipart 본문이 `MAX_UPLOAD_MB` 초과 |
| 422 | `no_face_detected` | 얼굴 미검출 |
| 502 | `download_failed` | 원격(R2) 비정상 응답/네트워크 실패 |
| 503 | `busy` | 동시 처리 상한 초과 — 대기 없이 즉시 거절. `Retry-After` 초 동봉 |
| 500 | `internal_error` | 서버 오류 |

### `GET /health` → `{"status":"ok"}` (모델 미접촉 liveness)

## 환경 변수 (기본값으로 동작)

| 환경변수 | 기본값 | 설명 |
|---|---|---|
| `HOST` / `PORT` | `0.0.0.0` / `8000` | 바인딩 |
| `DOWNLOAD_TIMEOUT_SEC` | `15` | 이미지 다운로드 타임아웃 |
| `MAX_DOWNLOAD_MB` | `10` | 최대 이미지 크기 |
| `MAX_UPLOAD_MB` | `1` | multipart 업로드 상한 (384px 크롭은 20~35KB) |
| `DETECTOR_BACKEND` | `opencv` | opencv/ssd/mtcnn/retinaface — 인종 + 전체 사진 검출 |
| `MIVOLO_MODEL_ID` / `MIVOLO_REVISION` | `iitolstykh/mivolo_v2` / 고정 커밋 | HF hub 모델·리비전 (원격 코드 포함, `HF_HOME` 캐시) |
| `CROP_MARGIN` | `0.2` | 검출 박스를 사방 넓히는 비율 (앱·웹 크롭 규격과 동일) |
| `MAX_CONCURRENT_ANALYSES` | `4` | 동시 처리 상한. 초과 요청은 503 `busy` |
| `BUSY_RETRY_AFTER_SEC` | `5` | 503 응답의 `Retry-After` 값 |
| `LOG_LEVEL` | `INFO` | 로깅 레벨 |

### 처리량 (2026-08-07 실측, macmini i7-3720QM 8코어)

추론 1건이 **8코어 중 약 6.3개**를 점유한다(~630% CPU). 그래서 동시 실행은 총
처리량을 못 올리고 대기시간만 선형으로 늘린다:

| 동시성 | 처리량 | p50 | p95 |
|---|---|---|---|
| 1 | 0.83 req/s | 1.2s | 1.2s |
| 4 | 0.73 req/s | 5.5s | 5.9s |
| 16 | 0.71 req/s | 18.8s | 34.5s |

**천장은 ~0.75 req/s (분당 45건)** 이고 CPU 바운드다. 컨테이너를 늘려도 같은
CPU 를 쪼갤 뿐이라 처리량은 그대로 — 더 필요하면 모델 경량화나 별도 하드웨어.
`MAX_CONCURRENT_ANALYSES` 는 이 사실 위에서 "느린 성공보다 빠른 실패"를 택한 값.

MiVOLO 는 `vendor/mivolo` (Apache 2.0, `vendor/mivolo/NOTICE.md`) + torch CPU 휠. 처리량 표는 DeepFace 단독
시절 값이라 MiVOLO 교체 후 다시 잰다 (`ab`/`hey` 로 동시성 1·4).

주의: TF 2.16+ Keras 3 비호환 → `tf-keras==2.16.0` pin + `TF_USE_LEGACY_KERAS=1`
(requirements.txt·Dockerfile 에 반영됨). 메모리 ~3GB 점유 (2026-08-07 `docker stats` 실측) — 4GB+ 인스턴스 권장.

## 파일 구조

```
python/app/
├── main.py                 # FastAPI 진입점 (/health · /analyze)
├── schemas.py              # Pydantic 모델
├── services/downloader.py  # httpx streaming 다운로드 + 검증
├── services/inference.py   # DeepFace 호출 + 워밍업
└── utils/config.py         # 환경변수 → Settings (다운로드 정책 포함)
```
