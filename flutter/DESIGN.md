# Face Reader — 디자인 시스템 SSOT

> 본 문서가 디자인 토큰의 **단일 진실 원천 (Single Source of Truth)**.
> 위젯 코드 안에 inline `fontSize`/`color`/`padding` 매직 넘버를 박지 말 것.
> `flutter/lib/core/theme.dart` 의 `AppText` / `AppColors` / `AppSpacing` / `AppRadius`
> 토큰 클래스를 통해서만 사용한다.

마지막 업데이트: 2026-05-16 (§0.0 통일성 절대 1순위 warning + 검증 protocol)

---

## ⛔ 0.0 통일성 — 모든 토큰·포맷 결정의 최상위 원칙

> **이 문서의 다른 모든 규칙보다 우선한다.** 같은 역할(role)을 표현하는 두 컨테이너가 다른 스타일·다른 포맷으로 보이면 그 자체로 결함이다. 발견 즉시 폐기·재작업 — debate 금지. 우리는 같은 정보를 두 가지 모습으로 보여주는 앱이 아니다.

### 0.0.1 통일성의 3 dimension

같은 화면 내·다른 화면 간에 아래 3개 차원이 모두 일치해야 한다:

1. **같은 역할 = 같은 token** — 같은 의미(예: "정체성 title", "메타 caption", "강조 eyebrow")의 두 컨테이너는 동일 `AppText.X` / `AppColors.X` / `AppSpacing.X` 를 공유한다. fontSize 가 1 step 이라도 다르면 위반.
2. **같은 정보 = 같은 포맷** — 같은 데이터(예: 연령대·성별·인종 3-tuple)는 모든 컨테이너에서 **동일 문자열 포맷·동일 순서·동일 구분자**(또는 무구분). 한 곳은 `"30대 여성 동아시아인"` 공백 구분, 다른 곳은 `"동아시아인 · 30대 여성"` 가운데점 + 역순 — 절대 금지.
3. **같은 위계 = 같은 사이즈** — 두 컨테이너가 위계상 동등하다면 (둘 다 정체성 chrome / 둘 다 list item 등), 그 둘의 title fontSize 는 동일 token. "주된 컨테이너 > 부수 컨테이너" 같은 위계 차이는 본 문서 어딘가에 명시되어야 하며, 명시 없이 사이즈를 다르게 잡지 않는다.

### 0.0.2 실제 위반 사례 (regression 차단용)

❌ **2026-05-16 발견**: SliverAppBar 헤더의 정체성 title 이 `AppText.subTitle` (14), 같은 화면 list item 의 title 이 `AppText.sectionTitle` (16). 정체성 표시라는 같은 역할인데 한 step 차이. **재작업: 둘 다 sectionTitle 로 통일.**

❌ **2026-05-16 발견**: 헤더 demographic 은 `"${ageGroup} ${gender} ${ethnicity}"` 공백 구분 + 연령순, list item 은 `"${ethnicity} · ${ageGroup} ${gender}"` 가운데점 + 인종순. 같은 데이터의 두 포맷. **재작업: 둘 다 헤더 포맷으로 통일.**

❌ **2026-05-16 발견**: 헤더 sub-caption 자리에 별칭/얼굴형 표시, list item 은 별칭/얼굴형이 title 자리에 표시. 같은 정보의 시각 위계가 두 컨테이너에서 반대. **재작업: 별칭/얼굴형은 두 곳 모두 caption 위계로 통일.**

❌ **2026-05-16 발견**: 같은 화면 안에서 동일 역할이 두 다른 token 으로 분기:
 - "isMyFace 라벨" — 헤더에서는 `AppText.caption (13) w600 gold`, list item 에서는 `AppText.hint (12) w600 gold`. 한 step 차이.
 - "별칭/얼굴형 subtitle" — 헤더에서는 `AppText.hint (12)`, list item 에서는 `AppText.caption (13)`. 한 step 차이 + 헤더만 color override 누락.

 **재작업: subtitle 두 곳 모두 `AppText.caption.copyWith(color: textHint)`, isMyFace 라벨 두 곳 모두 `AppText.caption.copyWith(w600, gold)` 로 통일.** 작은 step 차이가 가장 안 잡힌다 — fontSize 12 vs 13 은 그래픽 검증보다 코드 grep 으로 잡는다.

### 0.0.3 새 위젯·새 컨테이너 추가 시 의무 체크리스트

위젯을 작성하기 **전에** 본 체크리스트를 통과해야 한다:

- [ ] **선행 탐색**: 이 위젯이 표현하는 데이터·역할이 다른 화면에 이미 등장하는가? Y → 그 화면의 token·포맷·순서를 **그대로** 가져와 시작한다. 토큰을 새로 만들기 전에 기존 사용처를 한 번 더 본다.
- [ ] **token diff = 0**: 비교 대상 컨테이너와 fontSize·fontWeight·color·spacing·radius 가 한 step 이라도 다른가? Y → 한쪽을 맞춰서 통일한다. "조금만 더 작게/크게" 는 위반의 시작.
- [ ] **포맷 diff = 0**: 같은 데이터를 두 곳에서 다른 순서·다른 구분자·다른 단위로 포맷팅하는가? Y → 한쪽을 맞춰서 통일한다.
- [ ] **위계 명시**: 의도적으로 사이즈/색을 다르게 잡았다면, 그 위계 차이가 본 문서에 명시되어 있는가? 명시 없는 차이는 위반.

### 0.0.4 review·QA gate

PR 리뷰에서 본 절을 만족하지 못한 변경은 즉시 reject. 코드 자체 동작이 멀쩡해도 통일성 위반은 그 자체로 reject 사유 — 변경된 라인 옆에서 다른 컨테이너를 1분만 비교하면 잡힌다.

---

## 0. 운영 원칙 — 위반 시 즉시 폐기·재작업

1. **inline 매직 넘버 금지** — `TextStyle(fontSize: 15, fontWeight: w600 …)` 를 코드에 직접 박지 않는다. `AppText.X` 또는 `Theme.of(context).textTheme.titleMedium` 등 lookup 으로만 받는다.
2. **fontFamily 자체를 inline 으로 지정 금지** — display 토큰(이미 SongMyung 내장)을 통하지 않고 `fontFamily: 'SongMyung'` 을 위젯에 쓰면 SSOT 가 깨진다.
3. **같은 역할 = 같은 토큰** — 동일 의미(예: "모달 제목")의 두 화면이 다른 fontSize/Weight 를 쓰는 순간 그 자체로 결함이다. 토큰을 분기·신설하기 전에 기존 토큰의 의미를 다시 본다.
4. **색은 `AppColors`** — `Color(0xFF...)` 매직 넘버를 위젯에 박지 않는다. 새 컬러가 필요하면 `AppColors` 에 이름을 부여한 뒤 참조한다. 예외: 화면-국지적(local) 일회성 팔레트는 그 화면의 `private const _kFoo = Color(...)` 로 격리 (예: `physiognomy_screen.dart` 의 `_kHeroBgTop` 등).

---

## 1. 토큰 — 한눈에

### 1.1 폰트 — SongMyung 은 display 만

| 토큰 | size | weight | family | color | 용도 |
|---|---|---|---|---|---|
| `AppText.display` | 28 | w700 | **SongMyung** | textPrimary | 화면 최상위 inline 타이틀 ("AI 관상가") |
| `AppText.appBarTitle` | 20 | w600 | **SongMyung** | textPrimary | Scaffold AppBar 타이틀 ("관상", "궁합" 등) |
| `AppText.displaySubtitle` | 16 | w400 | **SongMyung** | textSecondary | display 바로 아래 sub-title (홈 hero 보조 문구) |
| `AppText.modalTitle` | 18 | w600 | system | textPrimary | AlertDialog title, bottomSheet header |
| `AppText.sectionTitle` | 16 | w600 | system | textPrimary | 리포트 큰 구획 헤딩 |
| `AppText.subTitle` | 14 | w600 | system | textPrimary | 카드 헤더, InfoRow label |
| `AppText.body` | 15 | w400 | system | textSecondary | 모달·리포트 본문 단락 (h 1.7) |
| `AppText.caption` | 13 | w400 | system | textSecondary | 보조 설명·tagline (h 1.55) |
| `AppText.hint` | 12 | w400 | system | textHint | 한자·메타·percent |

**SongMyung 정책**: `display` / `appBarTitle` / `displaySubtitle` 세 토큰만 SongMyung 을 가진다. 그 외 어디에도 `fontFamily: 'SongMyung'` 을 위젯 코드에서 직접 쓰지 않는다. AppBar 타이틀은 `AppTheme.light` 의 `appBarTheme.titleTextStyle` 에 주입되어 있으므로 `AppBar(title: Text('관상'))` 만 써도 자동 적용된다. `displaySubtitle` 은 display 와 한 쌍 — display 가 있는 화면에서 바로 아래 보조 문구로만 사용 (홈 hero 영역 등).

### 1.2 색상

`AppColors` 가 SSOT. `AppTheme.textPrimary` 같은 alias 는 backward-compat 용으로 남겨두지만 신규 코드는 `AppColors.X` 를 직접 쓴다.

```
Surface:    background(white), surface(#F5F5F5), border(#E0E0E0)
Text:       textPrimary(#333), textSecondary(#777), textHint(#AAA)
Accent:     accent(#555)
Semantic:   success(#2E7D32), danger(#D32F2F), info(#1565C0)
Brand-warm: gold(#C9A876), goldDim(#A89678), goldSoft(#F4E4C1)
```

### 1.3 Spacing — 4 스텝

```
AppSpacing.xs   4
AppSpacing.sm   8
AppSpacing.md   12
AppSpacing.lg   16
AppSpacing.xl   20
AppSpacing.xxl  24
AppSpacing.huge 32
```

EdgeInsets / SizedBox 의 모든 값은 위 스케일 안에서만 골라 쓴다. 7·11·18 같은 일회성 값 금지.

### 1.4 Border Radius

```
AppRadius.sm   6   — chip, small pill
AppRadius.md   10  — alert button, tappable label
AppRadius.lg   14  — list item card
AppRadius.xl   16  — modal, hero card
```

---

## 2. 핫한 theme 유지 기법 — 우리 프로젝트 적용판

### 2.1 Material 3 + `ThemeData.textTheme` 슬롯에 토큰 주입

`AppTheme.light` 의 `textTheme:` 에 우리 토큰을 MD3 slot 으로 매핑했다:

```dart
textTheme: const TextTheme(
  displayLarge: AppText.display,
  headlineMedium: AppText.appBarTitle,
  titleLarge: AppText.modalTitle,
  titleMedium: AppText.sectionTitle,
  titleSmall: AppText.subTitle,
  bodyLarge: AppText.body,
  bodyMedium: AppText.caption,
  bodySmall: AppText.hint,
),
```

→ MD3 의 기본 위젯(예: `ListTile`, `AppBar`, `AlertDialog`, `TabBar`)이 우리 토큰을 자동으로 가져간다. 위젯에서 `style:` 을 굳이 지정 안 해도 일관된 폰트가 적용됨.

### 2.2 토큰 직접 참조 vs `Theme.of(context)` lookup

두 가지 모두 OK. 트레이드오프:

- `AppText.body` 직접 참조 → `const` 유지 가능 (re-build 비용 0). 추천. **본 프로젝트의 디폴트.**
- `Theme.of(context).textTheme.bodyLarge` → 자식 위젯에서 `Theme` 으로 override 가능. 진짜로 theme override 가 필요한 컴포넌트 (예: 다크 시안 hero 카드 안의 텍스트) 에서만 사용.

**스타일을 살짝 바꿔야 할 때**: `AppText.body.copyWith(color: AppColors.gold)` — `const` 는 깨지지만 const 가 강제가 아닐 때 충분히 가볍다. inline TextStyle 새로 만들지 말 것.

### 2.3 `ThemeExtension<T>` — 브랜드 토큰을 ThemeData 에 끼우기

지금은 토큰을 `AppColors` 정적 클래스로 노출. 다크 모드를 도입할 시점에 `ThemeExtension<AppPalette>` 로 전환하면 `Theme.of(context).extension<AppPalette>()!.gold` 처럼 light/dark 동시 지원 가능. **현재는 light only 이므로 정적 클래스로 충분.** 다크 도입 시 본 절을 활성화한다.

### 2.4 위젯-국지 팔레트는 그 파일 안에 격리

여러 화면이 공유하지 않는 일회성 컬러(예: physiognomy 의 hero 카드 골드 톤)는 그 파일 상단의 `private const _kFoo` 로 격리한다. `AppColors` 를 한 번만 쓰이는 색으로 부풀리지 않는다.

```dart
// physiognomy_screen.dart 상단
const _kHeroBgTop = Color(0xFF2A2418);
const _kHeroBgBottom = Color(0xFF1F1812);
```

같은 화면에서 두 번 이상 재사용되면 file-local, 두 화면 이상에서 재사용되면 즉시 `AppColors` 로 승격.

### 2.5 컴포넌트 레시피는 위젯 클래스로 굳히기

같은 모양 (예: 알약 버튼 "내 프로필로 설정") 이 두 화면 이상에서 등장한다면, `physiognomy_screen.dart` 의 `_ProfileSetButton` 같은 화면-국지 위젯을 `presentation/widgets/` 의 공용 위젯으로 승격. 이름·시그너처·토큰 사용을 함께 옮긴다.

---

## 3. 컴포넌트 표준

### 3.1 모달 / Dialog

- background: `Colors.white`
- shape: `RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl))`
- title: `AppText.modalTitle`
- content body: `AppText.body`
- actions: `TextButton` (Material 의 기본 textStyle 을 그대로 — `AppText` 적용 X. system default font 유지)

```dart
AlertDialog(
  backgroundColor: Colors.white,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
  title: const Text('이름 변경', style: AppText.modalTitle),
  content: const Text('…', style: AppText.body),
  actions: [
    TextButton(onPressed: …, child: Text('취소', style: TextStyle(color: AppColors.textHint))),
    TextButton(onPressed: …, child: Text('저장', style: TextStyle(color: AppColors.textPrimary))),
  ],
);
```

### 3.2 카드 (리스트 아이템)

- color: `AppColors.surface`
- borderRadius: `AppRadius.lg` (14)
- padding: `EdgeInsets.fromLTRB(14, 14, 12, 14)`
- title text: `AppText.subTitle` 또는 16/w700 variant (`AppText.subTitle.copyWith(fontSize: 16, fontWeight: FontWeight.w700)`)
- meta sub-line: `AppText.caption.copyWith(color: AppColors.textHint)`

### 3.3 pill / chip / tappable label

- shape: `BorderRadius.circular(AppRadius.sm)` (6) — chip
- shape: `BorderRadius.circular(AppRadius.md)` (10) — pill button
- padding: `EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs)` 또는 `(10, 8)`
- text: 단일 색·단일 크기. **chip 안 multi-segment 의 색·사이즈 분리 금지.**

### 3.4 hero / promo 카드 (다크 액센트)

- background: 화면-국지 gradient (file-local `_kHeroBgTop` → `_kHeroBgBottom`)
- borderRadius: `AppRadius.xl` (16)
- accent text color: `AppColors.gold` (eyebrow), `AppColors.goldDim` (caption)
- main title color: `Colors.white`
- 자세한 예: `physiognomy_screen.dart::_MyProfileHeroCard`.

### 3.5 hint / info row

- background: `AppColors.surface`
- borderRadius: `AppRadius.lg`
- icon: `Icons.lightbulb_outline` 22 / `AppColors.gold`
- text: `AppText.caption` 또는 `AppText.subTitle.copyWith(fontSize: 13, fontWeight: FontWeight.w500)`

### 3.6 가운데점 (`·`) 남발 금지

한 줄에 두 의미를 우겨넣을 때 `·` 로 잇지 않는다. 줄 바꿈으로 분리한다.

```
✗  천생연분의 기운이 우세 · 얼굴상이 흔치않게 잘 맞는 자리
✓  천생연분의 기운이 우세
   얼굴상이 흔치않게 잘 맞는 자리.
```

### 3.7 Integrated sliver header — 옅은 톤 profile/identity slot

§3.4 의 다크 hero 카드와 짝을 이루는 **반대편 패턴**. 동일한 "프로필/정체성" 정보라도 그것이 화면 chrome (AppBar 의 연장선) 안에 상시 노출되는 sliver header 라면 다크 카드 대신 본 톤을 쓴다.

**언제 §3.4 다크 hero vs §3.7 옅은 sliver header**:
- §3.4 다크 hero — **promo · 일회성 강조**. 한 화면 안에서 한 번 등장하고 그 자체로 시선을 끌어야 하는 카드 (예: 분석 결과 리포트 상단의 archetype hero, 결제 유도 promo).
- §3.7 옅은 sliver header — **persistent identity · 화면 chrome**. AppBar 바로 아래에서 상시 노출되어 그 화면의 "당신은 누구" 를 알려주는 정체성 슬롯. 다크 반전이 화면 위계를 깨뜨리고 도드라지는 인상을 준다.

**같은 정체성 정보를 두 톤으로 동시에 쓰지 않는다.** 같은 화면에서 §3.4 와 §3.7 이 둘 다 등장하면 위계 충돌. 어느 한 쪽으로 통일.

규칙:

- background: `AppColors.background` (white) — **카드 chrome 제거**. AppBar 와 시각적으로 연속.
- bottom separator: `Border(bottom: BorderSide(color: AppColors.border, width: 0.5))` — list 와의 경계만 가는 1px 선으로.
- borderRadius: **0** (모서리 둥글기 없음 — sliver 폭 전체에 spread). 카드처럼 떠 있는 게 아니라 chrome 의 일부.
- padding: `EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md)` — 다크 hero (`AppSpacing.xl`) 보다 한 단 압축.
- avatar: §3.4 의 84px 절반 수준인 **42px**. 동일한 gold 1.5px border 유지.
- eyebrow text: `AppText.caption.copyWith(fontWeight: w600, color: AppColors.gold)` — 다크 hero 와 동일한 gold 강조 유지.
- title text: `AppText.subTitle.copyWith(fontWeight: w700)` — **textPrimary 다크 글자** (white 가 아님).
- sub-caption text: `AppText.hint` — textHint 회색.

예: `physiognomy_screen.dart::_MyProfileHeader`.

**SliverAppBar 임베딩 (expand/collapse 동작)**: 본 헤더를 `SliverAppBar.flexibleSpace`(FlexibleSpaceBar.background) 안에 넣으면, fully expanded 일 때 avatar + personal 내용이 모두 보이고 스크롤하면 background 가 자동 fade 되어 condensed 상태에서는 SliverAppBar.title (예: "관상") 만 남는다. `expandedHeight` = kToolbarHeight + 헤더 내용 높이 (대략 132~140), `pinned: true` 로 title·TabBar 유지, `TabBar` 는 `SliverAppBar.bottom` 슬롯. TabBarView 와 결합 시 `NestedScrollView` 의 `headerSliverBuilder` 에 두고 각 탭의 `CustomScrollView` 첫 sliver 는 `SliverOverlapInjector` — 인너 스크롤이 헤더 collapse 를 정상 트리거.

---

## 4. 마이그레이션 가이드

기존 inline `TextStyle(fontFamily: 'SongMyung', fontSize: 15, fontWeight: FontWeight.w400, color: AppTheme.textSecondary, height: 1.7)` 을 발견하면:

1. **fontFamily 줄 즉시 삭제** (display 토큰을 통하지 않는 SongMyung 직접 지정은 금지).
2. 남은 inline TextStyle 이 `AppText.X` 와 매칭되는지 확인. 매칭되면 `style: AppText.X` 로 교체.
3. 매칭이 안 되면: 정말 별개 의미인지 한 번 더 본다. 같은 의미인데 fontSize 만 1 다른 경우 → 토큰에 맞춘다 (디자인 일관성 > 1px 자유도).

새 코드 작성 시 체크리스트:

- [ ] `fontFamily:` 를 inline 으로 쓰고 있지 않다.
- [ ] 모든 TextStyle 이 `AppText.X` 또는 `AppText.X.copyWith(...)` 로 만들어진다.
- [ ] 색상이 `AppColors.X` 또는 file-local `_kFoo` 상수에서만 온다.
- [ ] SizedBox/padding 의 모든 값이 `AppSpacing` 스케일에 있다.
- [ ] BorderRadius 가 `AppRadius` 스케일에 있다.

---

## 5. AppBar 기본 동작

`AppBar(title: const Text('관상'))` 만 써도:
- 배경 흰색
- 타이틀 텍스트가 SongMyung 20 / w600 / textPrimary
- 아래 그림자 0 (스크롤 시 0.5)

위 동작은 `AppTheme.light::appBarTheme` 에 일괄 정의되어 있다. `AppBar` 안에 `title: Text(..., style: ...)` 로 override 하지 말 것.

---

## 6. 변경 시 검증

코드 수정 후:

```bash
cd flutter
flutter analyze          # 0 issue 유지
grep -rn "fontFamily" lib/  # 결과는 lib/core/theme.dart + (display 사용처) 만 나와야 함
```

본 문서 변경 시:
- 토큰 추가/이름 변경 → 본 문서 §1 와 `theme.dart` 둘 다 업데이트.
- SongMyung 정책 변경 → §0·§1·§2 + `flutter/CLAUDE.md` §0 동시 업데이트.
