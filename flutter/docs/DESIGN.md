# Face Reader — 디자인 시스템 SSOT

> 디자인 토큰의 단일 진실 원천. 위젯 코드에 inline `fontSize`/`color`/`padding`
> 매직 넘버 금지 — `flutter/lib/core/theme.dart` 의 `AppText`/`AppColors`/
> `AppSpacing`/`AppRadius` 토큰으로만.

## ⛔ 0.0 통일성 — 모든 결정의 최상위 원칙

> 같은 역할의 두 컨테이너가 다른 스타일·포맷으로 보이면 그 자체로 결함. 즉시 재작업.

1. **같은 역할 = 같은 token** — 같은 의미의 두 컨테이너는 동일 `AppText.X`/`AppColors.X`/
   `AppSpacing.X`. fontSize 1 step 차이도 위반.
2. **같은 정보 = 같은 포맷** — 같은 데이터(예: "30대 여성 동아시아인")는 모든 곳에서
   동일 문자열 포맷·순서·구분자.
3. **같은 위계 = 같은 사이즈** — 의도적 위계 차이는 본 문서에 명시돼야 하며, 명시 없는
   차이는 위반.

**새 위젯 추가 전 의무 체크리스트 (§0.0.3)**:
- [ ] 선행 탐색 — 같은 데이터·역할이 이미 다른 화면에 있으면 그 token·포맷을 그대로 가져온다
- [ ] token diff = 0 / 포맷 diff = 0
- [ ] 의도적 차이는 본 문서에 위계 명시

작은 step 차이(12 vs 13)는 눈보다 코드 grep 으로 잡는다. 통일성 위반은 동작이 멀쩡해도
그 자체로 reject 사유.

## 0. 운영 원칙

1. inline 매직 넘버 금지 — `AppText.X` 또는 `AppText.X.copyWith(...)` 만.
2. `fontFamily: 'SongMyung'` inline 지정 금지 — display 계열 토큰만 SongMyung 내장.
3. 색은 `AppColors.X`. 화면-국지 일회성 팔레트만 file-local `const _kFoo` 허용 —
   두 화면 이상 재사용되면 즉시 `AppColors` 승격.

## 1. 토큰

### 1.1 폰트 (SongMyung 은 display 계열만)

| 토큰 | size | weight | family | color | 용도 |
|---|---|---|---|---|---|
| `AppText.display` | 28 | w400 | **SongMyung** | textPrimary | 화면 최상위 타이틀 |
| `AppText.appBarTitle` | 20 | w400 | **SongMyung** | textPrimary | AppBar 타이틀 (theme 주입 — override 금지) |
| `AppText.displaySubtitle` | 16 | w400 | **SongMyung** | textSecondary | display 짝 보조 문구 |
| `AppText.modalTitle` | 18 | w600 | system | textPrimary | Dialog/bottomSheet 타이틀 |
| `AppText.sectionTitle` | 16 | w600 | system | textPrimary | 큰 구획 헤딩 |
| `AppText.subTitle` | 14 | w600 | system | textPrimary | 카드 헤더, 버튼 label |
| `AppText.body` | 15 | w400 | system | textSecondary | 본문 단락 (h 1.7) |
| `AppText.caption` | 13 | w400 | system | textSecondary | 보조 설명 (h 1.55) |
| `AppText.hint` | 12 | w400 | system | textHint | 메타·percent |

### 1.2 색상 (`AppColors`)

```
Surface:    background(white), surface(#F5F5F5), border(#E0E0E0)
Text:       textPrimary(#333), textSecondary(#777), textHint(#AAA)
Accent:     accent(#555)
Semantic:   success(#2E7D32), danger(#D32F2F), info(#1565C0)
Brand-warm: gold(#C9A876), goldDim(#A89678), goldSoft(#F4E4C1)
```

신규 색상 도입 금지. tint 는 기존 토큰의 alpha 로 (예: 내 관상 카드 = goldSoft 0.35).

### 1.3 Spacing / Radius

```
AppSpacing: xs 4 · sm 8 · md 12 · lg 16 · xl 20 · xxl 24 · huge 32
AppRadius:  sm 6 (chip) · md 10 (pill) · lg 14 (list card) · xl 16 (modal·hero)
```

모든 EdgeInsets/SizedBox/BorderRadius 는 이 스케일 안에서만. 리스트 좌우 padding 은
전 탭 **lg(16)** 통일.

### 1.4 Icons — 오직 FontAwesome

Material/Cupertino 아이콘 금지. `FaIcon(FontAwesomeIcons.*)` 만. FontAwesome 은
stroke 가 짙어 Material 대비 약 75~85% 크기로 (Material 24 → FA 18~20).

## 2. Theme 운영

- `AppTheme.light.textTheme` 에 토큰이 MD3 slot 으로 주입돼 있어 기본 위젯(ListTile·
  AppBar·AlertDialog·TabBar)이 자동 적용받는다.
- 기본은 `AppText.X` 직접 참조 (const 유지). 변형은 `copyWith` 만 — inline TextStyle 신설 금지.
- **§2.5 공용 승격**: 같은 모양이 두 화면 이상 등장하면 `presentation/widgets/` 공용
  위젯으로 승격 (이름·토큰 함께 이동). 현재 공용: PrimaryButton/SecondaryButton ·
  DetailAvatar · SortSelector · EmotionEmptyState · CoinChip · FaceScanPill ·
  CompactSnackBar · SourceBadge · MyFaceHeader 등.

## 3. 컴포넌트 표준

### 3.1 모달 / Dialog

white bg · `AppRadius.xl` · title `AppText.modalTitle` · body `AppText.body` ·
actions = `TextButton` (취소 textHint / 확정 textPrimary).

### 3.2 카드 (리스트 아이템)

`AppColors.surface` + **1px `AppColors.border`** (관상·궁합·케미 카드 공통 chrome) ·
`AppRadius.lg` · title `AppText.subTitle`(또는 16/w700 variant) · meta
`AppText.caption.copyWith(color: textHint)`. 내 관상 카드만 goldSoft 0.35 tint +
gold border (gold = "나" 시각 언어).

### 3.3 pill / chip

- outlined stadium pill (AppBar 액션): 흰 bg + 1px textPrimary border +
  radius 999 + padding(md, 6) + `AppText.caption` w700. CoinChip 도 동일 레시피.
  FaceScanPill 은 dual-state — 내 관상 미등록 = [내 관상 등록](내 관상 촬영),
  등록 후 = [상대방 관상 추가]. 케미 탭은 등록 후 [케미 그룹 시작]이 이 자리.
- chip: `AppRadius.sm`, 단일 색·단일 크기 — chip 안 multi-segment 색·사이즈 분리 금지.
- 가운데점(`·`) 남발 금지 — 한 줄에 두 의미를 잇지 않고 줄 바꿈으로 분리.

### 3.4 hero 카드 (다크) vs §3.7 sliver header (옅은 톤)

- 다크 hero = promo·일회성 강조 (리포트 archetype hero 등). file-local gradient +
  `AppRadius.xl` + gold eyebrow + white title.
- 옅은 sliver header = persistent identity (화면 chrome). white bg · radius 0 ·
  bottom 0.5px border · avatar 42px gold ring · title `subTitle` w700.
- 같은 정체성 정보를 두 톤으로 동시에 쓰지 않는다.

### 3.5 아바타

- **리스트 아바타**: 42px 원형 (`ClipOval`) — 전 탭 공통, rounded square 금지.
- **상세 페이지 아바타**: 공용 `DetailAvatar` — **56px 원형 + 1.5px ring**
  (다크 카드 = white 30% 기본값, 흰 배경 = `borderColor: AppColors.border`).
  이미지는 ClipOval 로 ring 안쪽, 배경 fill 금지(안티앨리어스 헤일로 원인).
- **이미지 3단 fallback (전 화면 공통)**: 로컬 파일 → CDN(`thumbnailKey`) → fallback
  (user 아이콘/성별 png). 새 아바타 렌더러는 반드시 3단을 지킨다.

### 3.6 정렬 selector

공용 `SortSelector<T>` ("라벨 ▾" PopupMenu, 우측 정렬) — 궁합·케미 리스트 상단.
상하 리듬 전 탭 통일: 위 lg(16) / 아래 md(12).

### 3.7 Empty state

- **EmotionEmptyState** (asset + message): 탭 본문 빈 상태 표준 —
  `Center > Column[Image 84×84 contain, gap sm, caption+textHint center]`.
  **emotion 패밀리는 항상 84px.** 배치: 관상 카메라 anger / 앨범·미등록 frown /
  북마크 smile / 궁합 미확인 love(상대0)·happy(전부확인) / 확인 surprise /
  케미 내가만든 laugh / 초대받은·미등록 shrug.
- **EmptyStatePlaceholder** (icon + title + detail): 아이콘형 — icon FaIcon 56px
  `AppColors.border`, title `sectionTitle` w400 textHint. 화면별 자체 empty 헬퍼 금지.

### 3.8 Full-width 버튼 — PrimaryButton / SecondaryButton

`lib/presentation/widgets/primary_button.dart`. 잠긴 토큰:

| slot | 값 |
|---|---|
| 높이 | 48 고정 · width infinity |
| 배경/전경 | **흰 배경 + 1px textPrimary border + textPrimary label** (Primary = busy·icon 지원) |
| 비활성 | 흰 bg + border 톤 테두리 + textHint |
| busy | 테두리 유지 + textPrimary 22px spinner |
| radius | 12 · label `AppText.subTitle` · icon FaIcon 16 |

**검정 invert CTA 전면 폐기 (2026-07-10)**: 위치 불문 모든 CTA 는 흰 배경 + 1px
textPrimary border. 유일한 예외 = 서드파티 브랜드 버튼(카카오 yellow).

## 4. 변경 시 검증

```bash
cd flutter && flutter analyze     # 기준선 7건 (경미) 외 신규 0
grep -rn "fontFamily" lib/        # theme.dart 외 결과 없어야 함
```

토큰 추가·변경 시 본 문서 §1 과 `theme.dart` 동시 갱신. SongMyung 정책 변경은
`flutter/CLAUDE.md` §0 도 동시 갱신.
