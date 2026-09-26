# TODO

의도적으로 미뤄둔 작업. 각 항목은 **왜 지금 안 하는지**와 **언제 해야 하는지**를
함께 적는다. 그게 없으면 목록이 그냥 쌓이기만 한다.

---

## console 의 service_role 키 제거 (RLS 전환)

**현재 상태.** `refine/src/providers/supabase-client.ts` 가 데이터 조회용
클라이언트를 `SUPABASE_SERVICE_KEY` 로 만든다. Vite 는 `VITE_` 접두사 변수를
빌드 시점에 번들로 인라인하므로, 이 키는 `console.facely.kr` 이 내려주는
JavaScript 안에 평문으로 들어 있다. service_role 은 RLS 를 전부 우회한다 —
모든 테이블의 모든 행을 읽고 쓰고 지울 수 있다.

코드 주석에 전제가 적혀 있다: *"브라우저에 노출되므로 admin 본인만 띄우는
로컬 도구 전제"*. 공개 배포로 그 전제가 깨졌다.

**지금 무엇이 막고 있나.** Cloudflare Access 를 `console.facely.kr` 앞에 걸어
두었다. 인증되지 않은 요청은 302 로 Access 로그인으로 돌아가고 **번들 자체를
받지 못한다** (검증함: `<script type="module">` 0개, `eyJhbG` 0개).

**그래서 왜 아직 위험한가.** Access 는 *번들을 받을 수 있는 사람*을 좁힐 뿐
키를 없애지 않는다. 통과한 사람은 개발자도구로 키를 꺼낼 수 있고, 한 번
꺼낸 키는 회수되지 않는다. 즉 **"콘솔 접근 권한 = DB 전권"** 이라는 등식이
그대로 남아 있다. 접근자가 한 명인 동안에는 감수할 만하다.

**언제 해야 하나.** 아래 중 하나라도 발생하면 그 전에.

- 콘솔 접근을 **다른 사람에게 주는 순간** — 그 사람에게 DB 전권을 주는 것과 같다
- Access 정책을 Email domain 등으로 넓히는 경우
- 키가 유출됐다고 의심되는 경우 (이때는 회전이 먼저)

**작업 범위.**

1. `supabaseAdminClient` 를 없애고 로그인한 사용자 세션(anon key + JWT)으로
   조회하도록 data provider 를 바꾼다.
2. Supabase 에 admin 역할을 정의하고 콘솔이 건드리는 테이블마다 RLS 정책을
   작성한다. **테이블별로 검증해야 한다** — 정책이 빠진 테이블은 조용히 빈
   결과를 돌려주지 에러를 내지 않는다.
3. `VITE_SUPABASE_SERVICE_KEY` 를 `.env`·GitHub 시크릿(`CONSOLE_SUPABASE_SERVICE_KEY`)·
   워크플로우에서 제거한다.
4. **Supabase 에서 service_role 키를 회전시킨다.** 이미 번들로 배포된 이력이
   있으므로 코드에서 지우는 것만으로는 부족하다.

**주의.** 3번까지만 하고 4번을 빼먹으면 아무것도 해결되지 않는다. 옛 번들을
가진 사람은 여전히 유효한 키를 들고 있다.

---

## 나이 추정 옛 경로 제거 (MiVOLO 직접 업로드 전환 뒤처리)

**진행 (2026-09-26).** Android 19 가 Play 프로덕션 전체 배포됨(9/24). `app_config.android_min_build = 19` 적용(9/26, 형이 SQL Editor 실행). 옛 경로 로그 관찰 시작일 = 2026-09-26 → 10/3 이후 0 이면 아래 실행.

**현재 상태 (2026-09-21).** 앱·웹은 384px 얼굴 크롭을 워커 `/api/analyze` 에 multipart 로
올린다 (왕복 1번). 그런데 스토어에 나간 Android 앱은 옛 경로를 쓴다 —
presign(`prefix: temp`) → R2 `temp/{uuid}.jpg` PUT → python `/analyze {image_url}` →
python 이 R2 에서 재다운로드 후 DELETE. python 은 두 계약을 모두 받는다.

**왜 지금 안 하나.** 옛 앱이 살아 있다. 지우면 그 앱의 촬영이 추정 실패(수동 선택
fallback)로 떨어진다. 죽지는 않지만 연령대·성별 prefill 이 사라진다.

**언제 하나.** 새 앱(커밋 b7764daa 이후 빌드)이 스토어에 올라가고, 콘솔 시스템 메뉴의
`android_min_build` 를 그 빌드 번호로 올려 옛 앱을 강제 업그레이드시킨 뒤. 그 후
python 로그에서 `"analyze request"` (image_url 경로) 줄이 일주일간 0 이면 실행.

**지울 것.** 한 PR 로.

| 위치 | 대상 |
|---|---|
| `python/app/main.py` | `_analyze_url`, JSON 분기, `AnalyzeRequest` 파싱 |
| `python/app/schemas.py` | `AnalyzeRequest` |
| `python/app/services/downloader.py` · `deleter.py` | 파일째 (URL 다운로드·R2 DELETE) |
| `python/app/utils/config.py` | `download_timeout_sec`, `max_download_mb`, `allowed_content_types`, `r2_*` 4개 |
| `python/docker-compose.yml` · `.env` | `MAX_DOWNLOAD_MB`, `DOWNLOAD_TIMEOUT_SEC`, `R2_*` 4개 (DELETE 전용 R2 토큰은 Cloudflare 에서 폐기) |
| `python/README.md` | ② `image_url` 계약, 400/502 `download_failed` 행 |
| `web/app/routes/api.r2.presign.ts` | `prefix: "temp"` 분기와 응답의 `token` (issueFaceToken 호출 — `/api/analyze` 쪽은 유지) |
| `web/app/lib/join.ts` | 없음 (이미 새 경로). `ageToGroup` 은 유지 |
| `web/docs/HOW-IT-WORKS.md` | `temp/{uuid}.jpg` 언급 전부, §6.1 의 presign 토큰 줄, R2 lifecycle 표의 `temp-expire-1d` 행 |
| Cloudflare R2 대시보드 | lifecycle rule `temp-expire-1d` (수동) |
| `flutter/lib/data/services/r2_uploader.dart` | `PresignedUpload.token` 필드와 temp 주석 |
| `flutter/lib/domain/models/face_metadata.dart` | 주석의 `temp/{uuid}.jpg` 줄 |
| `flutter/.env` | `FACE_META_API_BASE` (이미 미사용) |
| `flutter/docs/ARCHITECTURE.md` | `POST /analyze {image_url}` (옛 앱) 줄, R2 `temp/` 언급 |

**같이 하면 좋은 것 (선택).** python 의 DeepFace `race` 헤드를 FairFace 계열 작은
분류기로 바꾸면 tensorflow 두 벌(약 800MB)이 이미지에서 빠진다. 별도 측정 필요 —
tools/face_shape_ml/README.md ③ 하네스에 인종 라벨을 붙여 재면 된다.

---

## 운영 메모

- `face_engine.js` 와 `shared/.dart_tool` 은 gitignore 된 생성물이다. CI 는
  `dart pub get` → `pnpm build:shared` 를 거쳐 매번 새로 만든다. 로컬에는 이미
  있어서 빠뜨려도 티가 안 나므로, 빌드 관련 CI 를 손볼 때는 **해당 파일을 치우고
  재현**해서 확인할 것. 그러지 않아 CI 를 네 번 연속 실패시킨 적이 있다.
- `console.facely.kr` 의 DNS 는 wrangler 가 관리한다(`custom_domain: true`).
  손으로 A/CNAME 을 만들면 배포가 `code: 100117` 로 거부된다.
