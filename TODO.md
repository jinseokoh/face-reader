# TODO

face.kr share host + Flutter app + refine admin 의 prod 배포까지 남은 작업.
끝낸 항목은 `[x]` 로 마킹 후 commit. 모두 끝나면 이 파일 삭제.

마지막 갱신: 2026-04-27

---

## P0 — Supabase SQL (한 번 실행)

`react/CLAUDE.md` §환경변수 직후 + `react/DEEPLINK.md` §3 의 SQL 블록 그대로 실행.
4 개 SQL 모두 idempotent 하게 짰으니 여러 번 실행해도 안전.

- [ ] `admin_grant_coins(p_user_id, p_amount, p_description)` RPC — refine 보너스 지급용
- [ ] `unlock_compat` 의 `app_users` → `users` 교체 (현재 42P01 에러로 unlock 실패)
- [ ] `ads` + `ad_views` 테이블 + `claim_ad_reward(p_ad_id)` RPC + storage 'ads' bucket·policy
- [ ] `metrics` RLS — `revoke select on metrics from anon` + column-level grant `(id, metrics_json, expires_at)` + 만료 정책
- [ ] (옛 share_payload 마이그레이션 적용 흔적 있으면 같이 정리 — 위 SQL 의 마지막 블록)

검증:
```sql
select pg_get_function_arguments(oid) from pg_proc
  where proname in ('admin_grant_coins','unlock_compat','claim_ad_reward');
select column_name from information_schema.columns
  where table_name='metrics' and column_name='share_payload';   -- 0 rows
```

---

## P0 — Cloudflare Workers prod 배포

```bash
cd /Users/chuck/Code/face/react

# 1) secrets
openssl rand -base64 32 | wrangler secret put SHARE_TOKEN_SECRET
wrangler secret put SUPABASE_URL
wrangler secret put SUPABASE_ANON_KEY

# 2) AASA / assetlinks 실값 (내용은 react/DEEPLINK.md §5 참고)
#    public/.well-known/apple-app-site-association — TEAMID 박기
#    public/.well-known/assetlinks.json            — Play Console release SHA-256

# 3) build + deploy
pnpm build:shared && pnpm build && pnpm deploy
```

- [ ] `wrangler secret put SHARE_TOKEN_SECRET` (32 bytes random)
- [ ] `wrangler secret put SUPABASE_URL`
- [ ] `wrangler secret put SUPABASE_ANON_KEY`
- [ ] `react/public/.well-known/apple-app-site-association` — TEAMID 실값 교체
- [ ] `react/public/.well-known/assetlinks.json` — Play Console release SHA-256 교체
- [ ] `pnpm deploy` — Cloudflare Workers
- [ ] 배포 검증 — `https://face.kr/.well-known/apple-app-site-association` 200 + `application/json`
- [ ] 배포 검증 — `https://face.kr/r/{demo-token}` SSR HTML 정상

---

## P0 — iOS Xcode (수동, GUI 작업)

- [ ] Runner.xcworkspace 열기 → Runner target → Signing & Capabilities
- [ ] `+ Capability` → "Associated Domains" 추가
- [ ] entry: `applinks:face.kr` (`flutter/ios/Runner/Runner.entitlements` 가 자동으로 빌드에 들어감)
- [ ] DEVELOPMENT_TEAM 설정 (TEAMID 가 AASA 와 일치해야 함)

검증: 빌드 후 실기에서 카톡으로 `https://face.kr/r/{token}` 받기 → 메시지 탭 → 앱 직접 open

---

## P1 — share host `/api/decode` endpoint + Flutter deep link 라우팅

현재 `DeepLinkService.shareTokenStream` 만 노출되어 있고 ReportPage 진입은 TODO.

- [ ] `react/app/routes/api.decode.ts` (POST 또는 GET) — `{token}` 받아 HMAC verify + uuid 들 반환
  - share host 의 SHARE_TOKEN_SECRET 으로만 verify 가능 → 해당 endpoint 가 유일한 신뢰할 수 있는 decoder
  - 응답: `{ type: 'solo'|'compat', userA: uuid, userB?: uuid }`
- [ ] Flutter `DeepLinkService` — `shareTokenStream` 받아 `/api/decode` 호출 → uuids 추출
- [ ] 결과 uuid 들로 supabase metrics fetch 후 ReportPage (또는 CompatibilityDetailScreen) push
  - 본인 metrics 가 history 에 있으면 그걸 사용, 없으면 anon REST 로 metrics_json 받아 fromJsonString 로 rehydrate
- [ ] cold start 시점 race — DeepLinkService.initialize() 가 navigator 준비 전 trigger 될 수 있음. 첫 token 은 buffer 후 MainApp build 직후 consume

---

## P1 — 광고 시스템 보강

- [ ] Refine ads list — 시청 횟수 column (`select count(*) from ad_views where ad_id = ?` aggregate)
- [ ] Refine ads edit 페이지 — title/reward/active 수정 (현재는 list 에서 active toggle 만)
- [ ] Flutter — ad daily cap (5/24h) 도달 시 PurchaseSheet fallback 자동 노출
- [ ] Flutter — 활성 광고 0개일 때 메시지 ("새 광고가 곧 추가됩니다" 등) UX 개선

---

## P2 — 운영·개발 도구

- [ ] dart compile js 산출물 smoke test — sample metrics_json 으로 runEngine / runCompat 호출 후 expected output 비교 (CI 차원)
- [ ] Flutter unit test — `unlock(key, totalScore)` 시그니처 변경에 대한 test
- [ ] CLAUDE.md / DEEPLINK.md docs sync — ad 시스템 / refine 보너스 지급 / 검증 체크리스트 갱신
- [ ] Refine — unlocks list 의 total_score 컬럼이 옛 row 는 null. backfill 자동화 (admin 진입 시 lazy 계산해 PATCH) 또는 일회성 backfill script

---

## P2 — analytics / 비즈니스 지표

- [ ] share link click → app open → install funnel — Cloudflare Analytics Engine 또는 Plausible
- [ ] 카톡 in-app browser fallback — `react/app/components/CTA.tsx` 가 카톡 UA 감지 → `intent://` (Android) 또는 외부 브라우저 강제 open

---

## 완료 (참고)

- [x] `/shared/` Dart 패키지 추출 + dart compile js
- [x] React share host token-based (HMAC sig4)
- [x] Compat hero card 1:1 mirror (Flutter `_CompatShareCard`)
- [x] Solo hero card 1:1 mirror (`_HeroCard`)
- [x] Refine: metrics show / unlocks show / ads CRUD / users 보너스 지급
- [x] Flutter: SharePublisher + DeepLinkService skeleton + AndroidManifest intent-filter + iOS entitlements
- [x] Flutter: ad reward (video_player + claim RPC + rotation + forward-seek 차단)
- [x] Flutter: wallet 페이지 — 잔액을 AppBar 로, 충전 컨테이너 제거, 광고 진입 IconButton
