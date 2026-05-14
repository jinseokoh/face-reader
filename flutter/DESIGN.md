# Face Reader — 디자인 시스템 SSOT

> 본 문서가 디자인 토큰의 **단일 진실 원천 (Single Source of Truth)**.
> 위젯 코드 안에 inline `fontSize`/`color`/`padding` 매직 넘버를 박지 말 것.
> `flutter/lib/core/theme.dart` 의 `AppText` / `AppColors` / `AppSpacing` / `AppRadius`
> 토큰 클래스를 통해서만 사용한다.

마지막 업데이트: 2026-05-14 (송명체 display-only 정책 + 토큰 SSOT 분리)

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
| `AppText.modalTitle` | 18 | w600 | system | textPrimary | AlertDialog title, bottomSheet header |
| `AppText.sectionTitle` | 16 | w600 | system | textPrimary | 리포트 큰 구획 헤딩 |
| `AppText.subTitle` | 14 | w600 | system | textPrimary | 카드 헤더, InfoRow label |
| `AppText.body` | 15 | w400 | system | textSecondary | 모달·리포트 본문 단락 (h 1.7) |
| `AppText.caption` | 13 | w400 | system | textSecondary | 보조 설명·tagline (h 1.55) |
| `AppText.hint` | 12 | w400 | system | textHint | 한자·메타·percent |

**SongMyung 정책**: `display` / `appBarTitle` 두 토큰만 SongMyung 을 가진다. 그 외 어디에도 `fontFamily: 'SongMyung'` 을 위젯 코드에서 직접 쓰지 않는다. AppBar 타이틀은 `AppTheme.light` 의 `appBarTheme.titleTextStyle` 에 주입되어 있으므로 `AppBar(title: Text('관상'))` 만 써도 자동 적용된다.

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
✗  좋은 점 압도 · 얼굴로 읽으면 흔치 않게 잘 맞는 자리
✓  좋은 점 압도
   얼굴로 읽으면 흔치 않게 잘 맞는 자리.
```

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
