# Face Metadata 추론 서비스

얼굴 사진을 받아 **나이 / 성별 / 인종** 만 돌려주는 가벼운 추론 API. CPU 만으로 동작하며 GPU 가 필요 없다. 이미지는 본 서비스에 직접 업로드되지 않고, **모바일 앱이 Cloudflare R2 등에 먼저 올린 뒤 그 URL 만 본 API 에 전달**한다.

이 문서는 Ubuntu 서버(또는 Ubuntu 가상머신/WSL2) 에서 **Python 을 처음 다루는 사람도 그대로 따라 할 수 있도록** 작성되어 있다. 명령어는 위에서부터 한 줄씩 그대로 복사해 실행하면 된다.

---

## 1. 서버에서 무엇을 하는지

```
모바일 앱 ── (이미지 720px 로 리사이즈) ──► Cloudflare R2 (이미지 저장소)
                                              │
                                              │  업로드된 URL
                                              ▼
   POST /analyze { "image_url": "..." } ──► 본 서비스 (FastAPI)
                                              │
                                              │  URL 로부터 이미지 streaming download
                                              ▼
                                       DeepFace.analyze 실행
                                              │
                                              ▼
                               { age, gender, race } JSON 응답
```

- DeepFace 라는 오픈소스 얼굴분석 라이브러리를 사용. age/gender/race **세 가지만** 추론하도록 잘라 두었다.
- detector 는 `opencv` (가장 가볍고 CPU 친화).
- 첫 요청 때 모델 가중치(weights, ~80MB) 가 자동 다운로드된다. 본 서비스는 **시작할 때 한 번 미리 워밍업** 해서 첫 사용자 요청이 느려지지 않도록 설계되었다.

---

## 2. 우분투에서 실행 (Docker 사용 — **권장**)

Python·시스템 라이브러리 설치를 다 신경 안 써도 되고, 어디서든 똑같이 돌아간다. 처음 시작하는 사람도 이 경로를 추천.

### 2-1. Docker 설치 (이미 깔려 있으면 건너뛰기)

```bash
# Ubuntu 22.04 / 24.04 기준
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable --now docker

# (선택) sudo 없이 docker 쓰려면 — 한 번 로그아웃 후 다시 로그인 필요
sudo usermod -aG docker $USER
```

설치 확인:
```bash
docker --version
docker compose version
```

### 2-2. 소스 받기 / 폴더로 이동

```bash
cd /path/to/face/python     # 이 README 가 있는 폴더
```

### 2-3. 빌드 & 실행

```bash
# 이미지 빌드 (처음엔 5~10분 걸린다 — tensorflow-cpu 등 다운받음)
docker compose build

# 컨테이너 시작 (백그라운드)
docker compose up -d

# 로그 보기 (Ctrl+C 로 나가도 컨테이너는 계속 돈다)
docker compose logs -f
```

처음 시작하면 로그에 다음과 같이 찍힌다:
```json
{"ts":"...", "level":"INFO", "logger":"face.api", "message":"starting face metadata service"}
{"ts":"...", "level":"INFO", "logger":"app.services.inference", "message":"warming up DeepFace models (backend=opencv)"}
{"ts":"...", "level":"INFO", "logger":"app.services.inference", "message":"DeepFace warm-up complete"}
```
워밍업이 끝나면 **30 초 이내에** 트래픽 받을 준비 완료.

### 2-4. 동작 확인

```bash
# Liveness 체크
curl -s http://localhost:8000/health
# → {"status":"ok"}

# 실제 분석 요청 (image_url 은 본인 R2 / 임의 공개 이미지 URL 로 교체)
curl -s -X POST http://localhost:8000/analyze \
  -H 'Content-Type: application/json' \
  -d '{"image_url":"https://images.example.com/face.jpg"}'
# → {"age":28,"gender":"Man","race":"asian"}
```

### 2-5. 멈추기 / 재시작

```bash
docker compose stop          # 잠시 중지 (데이터 유지)
docker compose start         # 다시 시작
docker compose down          # 컨테이너 제거 (이미지·볼륨은 유지)
docker compose up -d --build # 코드 바꾼 뒤 재빌드 + 재기동
```

---

## 3. 우분투에서 Docker 없이 직접 실행 (개발용)

Docker 가 부담스럽거나 코드를 자주 고치면서 확인하고 싶을 때.

### 3-1. 시스템 패키지 설치

OpenCV 가 런타임에 필요로 하는 시스템 라이브러리들과 Python 3.10:

```bash
sudo apt-get update
sudo apt-get install -y \
    python3.10 python3.10-venv python3.10-dev \
    libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 libgl1 \
    build-essential
```

> Python 3.10 이 패키지 매니저에 없는 우분투(예: 24.04 는 기본이 3.12) 의 경우 deadsnakes PPA 추가:
> ```bash
> sudo add-apt-repository ppa:deadsnakes/ppa -y
> sudo apt-get update
> sudo apt-get install -y python3.10 python3.10-venv python3.10-dev
> ```

### 3-2. 가상환경 만들기

가상환경(venv)은 이 프로젝트의 파이썬 라이브러리들을 **시스템 파이썬과 격리해서** 깔아두는 폴더라고 생각하면 된다.

```bash
cd /path/to/face/python
python3.10 -m venv .venv      # .venv 폴더 생성
source .venv/bin/activate     # 활성화 — 프롬프트 앞에 (.venv) 가 붙는다
```

이후 모든 `pip install` / `uvicorn` 명령은 이 가상환경 안에서 동작한다. 새 터미널을 열 때마다 `source .venv/bin/activate` 한 번씩 해야 한다.

비활성화 하려면:
```bash
deactivate
```

### 3-3. 의존 라이브러리 설치

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

`tensorflow-cpu` 가 가장 무거워서 (~500MB) 시간이 좀 걸린다. 끝까지 기다리자.

### 3-4. 서버 실행

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

다른 터미널에서 `curl` 로 확인 (2-4 절과 동일):
```bash
curl -s http://localhost:8000/health
```

종료하려면 실행 중인 터미널에서 `Ctrl+C`.

---

## 4. API 사양

### `POST /analyze`

요청 본문:
```json
{ "image_url": "https://r2.example.com/u/abc.jpg" }
```

성공 (200):
```json
{ "age": 28, "gender": "Man", "race": "asian" }
```

- `age`: 정수 (DeepFace 의 float 추정치를 반올림)
- `gender`: `"Man"` 또는 `"Woman"`
- `race`: `"asian"` / `"indian"` / `"black"` / `"white"` / `"middle eastern"` / `"latino hispanic"` 중 하나

실패 응답은 모두 동일한 구조:
```json
{ "error": "no_face_detected", "detail": "사람이 못 알아볼 이미지에요..." }
```

| HTTP | `error` 값 | 의미 |
| --- | --- | --- |
| 400 | `download_failed` | URL 이 잘못됐거나, 이미지 타입이 아니거나, 파일이 너무 큼 |
| 422 | `no_face_detected` | 이미지 받았지만 얼굴이 안 보임 |
| 502 | `download_failed` | 원격 서버(R2 등) 가 200 외 응답 / 네트워크 실패 |
| 500 | `internal_error` | 예상치 못한 서버 오류 |

### `GET /health`

생존 확인. 모델은 안 건드린다.
```json
{ "status": "ok" }
```

---

## 5. 환경 변수로 동작 조정

값을 따로 안 줘도 기본값으로 잘 돈다. 바꾸고 싶을 때만 손대면 됨.

| 환경변수 | 기본값 | 설명 |
| --- | --- | --- |
| `HOST` | `0.0.0.0` | 바인딩 호스트 |
| `PORT` | `8000` | 바인딩 포트 |
| `DOWNLOAD_TIMEOUT_SEC` | `15` | URL 로부터 받는 HTTP 타임아웃(초) |
| `MAX_DOWNLOAD_MB` | `10` | 다운로드할 수 있는 이미지 최대 크기 |
| `DETECTOR_BACKEND` | `opencv` | `opencv` / `ssd` / `mtcnn` / `retinaface` 중 선택 |
| `LOG_LEVEL` | `INFO` | `DEBUG` / `INFO` / `WARNING` / `ERROR` |

Docker 에서 바꾸려면 `docker-compose.yml` 의 `environment:` 블록을 수정.
호스트에서 바꾸려면 셸에서 `export MAX_DOWNLOAD_MB=20` 후 `uvicorn` 재기동.

---

## 6. 자주 만나는 문제 해결

### "libGL.so.1: cannot open shared object file"
OpenCV 가 의존하는 시스템 라이브러리가 없는 경우. Docker 를 안 쓸 때 발생한다:
```bash
sudo apt-get install -y libgl1 libglib2.0-0 libsm6 libxext6 libxrender1
```

### "ModuleNotFoundError: No module named 'fastapi'" 등
가상환경을 활성화 안 한 채로 `uvicorn` 을 실행했을 가능성이 크다:
```bash
source .venv/bin/activate
which python   # → /path/to/face/python/.venv/bin/python 가 나와야 정상
```

### 첫 요청이 30 초 이상 걸린다
모델 가중치를 처음 받아오는 중. 본 서비스는 시작할 때 한 번 워밍업 호출을 자동으로 돌리므로, 컨테이너 기동 후 **30 초 정도 기다린 뒤** 트래픽을 보내야 한다.

### "You have tensorflow ... and this requires tf-keras package"
TF 2.16+ 부터 내장 `tf.keras` 가 Keras 3 로 바뀌면서 DeepFace/retinaface 가 동작 안 함. 본 프로젝트는 이미 `tf-keras==2.16.0` 을 `requirements.txt` 에 넣고 `TF_USE_LEGACY_KERAS=1` env 를 Dockerfile 에 설정해 둠. 직접 설치 시 빠뜨렸다면:
```bash
pip install tf-keras==2.16.0
export TF_USE_LEGACY_KERAS=1
```

### "Face could not be detected" 가 계속 뜬다
- 기본 detector `opencv` 는 빠르지만 측면/저조도에 약하다. 환경변수로 바꿔 보기:
  ```bash
  DETECTOR_BACKEND=retinaface docker compose up -d
  ```
  retinaface 는 정확도는 더 좋지만 메모리·CPU 더 먹는다.
- 이미지가 정말 너무 작거나 흐릿할 수 있음. 720px 가로 폭은 모바일 앱에서 보낸다는 전제.

### "unsupported content-type" 400 응답
R2 에 이미지를 업로드할 때 `Content-Type` 헤더를 설정 안 했을 가능성이 큼. 업로드 측에서 `image/jpeg` / `image/png` / `image/webp` 중 하나로 명시해야 한다. (기본 `application/octet-stream` 은 거부.)

### 메모리가 부족하다 (1GB 미만 서버)
DeepFace + TensorFlow 가 가중치 로드 후 약 600MB 를 점유한다. 1GB VPS 라면 swap 으로 빠지면서 매우 느려진다. **2GB 이상** 인스턴스 추천. 어쩔 수 없으면 swap 늘리기:
```bash
sudo fallocate -l 2G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

### 어디까지 실행됐는지 보고 싶을 때
JSON 로그라서 사람이 읽기 어려우면 `jq` 로 예쁘게:
```bash
docker compose logs -f --tail=100 | jq -R 'fromjson? // .'
```

---

## 7. 파일 구조

```
python/
├── app/
│   ├── main.py                  # FastAPI 진입점, /health · /analyze
│   ├── schemas.py               # 요청/응답 Pydantic 모델
│   ├── services/
│   │   ├── downloader.py        # httpx 로 이미지 streaming 다운로드 + 검증 + temp 파일
│   │   └── inference.py         # DeepFace 호출, 워밍업 함수
│   └── utils/
│       ├── config.py            # 환경변수 → Settings 객체
│       └── logging_config.py    # JSON 표준출력 로깅 설정
├── requirements.txt              # 의존 라이브러리 핀
├── Dockerfile                    # Python 3.10-slim + OpenCV 시스템 의존
├── docker-compose.yml            # 서비스 정의 + healthcheck
├── .dockerignore
└── README.md                     # 이 문서
```

수정해도 되는 곳:
- 환경변수만 바꾸려면 `app/utils/config.py` 또는 `docker-compose.yml` 의 `environment:`.
- API 동작을 바꾸려면 `app/main.py`.
- 다운로드 정책(허용 타입 / 최대 크기) 은 `app/utils/config.py`.
