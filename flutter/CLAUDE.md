# Face Reader — Claude Code 오리엔테이션

**최종 업데이트**: 2026-07-17

관상 분석 Flutter 앱. MediaPipe Face Mesh 468 landmarks → 26 frontal + 8 lateral metric → 14-node tree → 10 attribute → archetype → 8 인생 질문 본문. 궁합은 별도 엔진(五行·十二宮·五官·三停·陰陽 기반).

> **용어 규칙** — 1차 기능의 한국어 공식 명칭은 **`케미 그룹`**(2026-07-19 "케미 매칭"에서
> 재개칭, `케미` 단독 표기는 2026-07-16 폐기). 방/모임 단위는 `그룹`(공개 그룹·내 그룹·그룹 만들기·
> 그룹 제목, 방 유형 기본 제목은 `이성/전체 케미 매칭그룹`), 성사된 쌍은 계속 `매칭`(베스트 매칭·
> 매칭되었습니다). 제품 분류: 1인 관상 · 2인 궁합 · 다인 케미 그룹. 문서·UI·스토어
> 카피의 한국어 표기는 이 명칭만 사용한다. 코드 식별자는 영문 team_* 유지.

## ⛔ 절대 규칙

### UI 통일감은 절대 1순위

화면 간·요소 간 디자인 불일치는 즉시 폐기·재작업 사유. 폰트 패밀리·크기·웨이트가 화면마다 다르면 그 자체로 결함.

1. **SongMyung 은 `AppText.display` / `AppText.appBarTitle` 두 토큰 한정.** 위젯 코드에 `fontFamily: 'SongMyung'` 직접 작성 금지.
2. **inline 매직 넘버 금지.** `TextStyle(fontSize: 15, fontWeight: w600 ...)` 직접 작성 금지. `AppText.X` 토큰 또는 `AppText.X.copyWith(color: ...)` 만.
3. **컬러 매직 넘버 금지.** `Color(0xFF...)` 를 위젯 코드에 직접 박지 않는다. `AppColors.X` 또는 화면-국지 `_kFoo` 상수만.
4. **Spacing·Radius 스케일 준수.** `AppSpacing` (4/8/12/16/20/24/32), `AppRadius` (6/10/14/16) 외 값 금지.
5. **chip/pill 단일톤.** 하나의 chip/pill 안에서 색·크기 분리 금지. priority 차이는 줄 분리 또는 background tint 로만.
6. **가운데점(`·`) 남발 금지.** 한 줄에 두 의미 우겨넣지 않는다. 줄 바꿈으로 분리.
7. **같은 역할 = 같은 위젯.** 역할이 같은 두 modal/카드/리스트 아이템은 동일 base widget 공유. 새로 만들기 전에 기존 컴포넌트 재사용을 본다.
8. **하단 시스템 바 inset 필수.** edge-to-edge 라 제스처 내비가 콘텐츠를 가린다. 모든 새 화면·bottom sheet 는 `SafeArea` 로 감싸거나, 스크롤 하단 padding 에 `MediaQuery.of(context).viewPadding.bottom` 을 가산할 것 (탭 내부는 셸 BottomNavigationBar 가 흡수하므로 예외). 커스텀 bottom bar Container 는 자동 inset 이 없다.

상세 컴포넌트 레시피·토큰 표·마이그레이션 가이드는 [`docs/DESIGN.md`](docs/DESIGN.md).

### 금지어

답변·커밋·문서에 절대 쓰지 말 것:

> 레거시 / 예전 / 구 엔진 / 기존 구현 / 이전에는 / legacy / 마이그레이션 / 호환성 / 참조만 / 참고만

근거 제시는 세 가지로만:
1. **현재 엔진의 구조적 특성** (row 합 = 1.00, stage firing rate 등)
2. **Monte Carlo 측정** (20,000 샘플, seed=42, input z ~ N(0, 0.85))
3. **UX 판단** (bar chart 가독성, 사용자 해석 난이도, saturation 등)

과거 상태를 비교 기준으로 제시하는 순간 트리거. 설계 제안에 "nullable optional", "기존 호환" 같은 safety hook 금지. 데이터·Hive·스키마 전부 drop-recreate 자유.

### 코드 작성 룰

- 한자 단독 표기 금지 (上停·中停·下停 등). 현대 한국어로 ("20대" / "30~40대 정점기" / "50대 이후").
- 관상 narrative 메타포·자기계발 jargon 과잉 금지. 평범한 3 sentence 한국어로.
- DeepFace 값은 매 분석마다 사용. 이전 값 기억 안 함 (Hive prefs 의 gender/age/ethnicity 사용 안 함).
- 갈림길에선 물어보지 말고 과감·풍성한 쪽으로.
- 최종 요구사항 우선. 대화 후반 지시가 기존 제약 덮어쓴다.

---

## 📚 SSOT 3 파일

| 문서 | 역할 |
|---|---|
| [`docs/HOW-IT-WORKS.md`](docs/HOW-IT-WORKS.md) | 엔진 기술 구현 — `face_engine` 패키지 위치 · 26+8 metric · 14 node · 10 attribute · 5-stage pipeline · normalize · Hive capture-only · 궁합 5 frame · narrative · face shape classifier |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | 화면·패키지 구조 — shared/face_engine 분리 · 4-tab IndexedStack · Riverpod 패턴 · 데이터 흐름 · 코인/궁합 경제 · 외부 인프라 (R2/Supabase/DeepFace/AdMob/카카오) · 빌드 |
| [`docs/DESIGN.md`](docs/DESIGN.md) | 디자인 토큰 SSOT — AppColors · AppText · AppSpacing · AppRadius · 컴포넌트 레시피 |

추가 reference:
- [`../tools/face_shape_ml/README.md`](../tools/face_shape_ml/README.md) — face shape classifier 재학습 · TFLite 배포 procedure
- `react/docs/HOW-IT-WORKS.md` — Cloudflare Workers + share link 통합 (별도 디렉토리)

---

## 🛠️ 빌드 / 테스트

```bash
cd /Users/chuck/Code/face/flutter
flutter pub get
flutter analyze          # 0 issues 기대
flutter test             # 161 test 전부 green
flutter run              # 실기 (camera/MediaPipe simulator 불가)
```

Monte Carlo 재보정 (weight matrix/rule/reference 수정 후):
```bash
flutter test test/calibration_test.dart
# 출력 21-point map 을 attribute_normalize.dart 에 paste
flutter test test/archetype_fairness_test.dart test/score_distribution_test.dart
```

---

## 🚀 새 세션 시작 시

1. `docs/HOW-IT-WORKS.md` 또는 `docs/ARCHITECTURE.md` — 작업 영역에 따라
2. 엔진(룰·reference·quantile·궁합) 변경은 `shared/` 한 곳에서만
3. 변경 후 3 SSOT 중 영향 받는 문서 갱신
