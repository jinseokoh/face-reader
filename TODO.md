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

## 운영 메모

- `face_engine.js` 와 `shared/.dart_tool` 은 gitignore 된 생성물이다. CI 는
  `dart pub get` → `pnpm build:shared` 를 거쳐 매번 새로 만든다. 로컬에는 이미
  있어서 빠뜨려도 티가 안 나므로, 빌드 관련 CI 를 손볼 때는 **해당 파일을 치우고
  재현**해서 확인할 것. 그러지 않아 CI 를 네 번 연속 실패시킨 적이 있다.
- `console.facely.kr` 의 DNS 는 wrangler 가 관리한다(`custom_domain: true`).
  손으로 A/CNAME 을 만들면 배포가 `code: 100117` 로 거부된다.
