# APPEAL — Guideline 4.3(b)

App Review Board 정식 appeal 문안.

**프레임 — 퍼널.** 이 앱의 제품은 **그룹 케미 매칭**이고, 관상은 그 매칭을 굴리는
**입력 재료이자 아이스브레이킹 소재**다. "관상 앱이 아닙니다"라고 부인하지 않는다.
부인은 심사관이 앱을 30초 열어보면 무너진다. 대신 **`primarily` 를 다툰다** —
조문이 묻는 건 장르 언급 여부가 아니라 주 기능이 무엇이냐다.

| | |
| --- | --- |
| Submission ID | `e699a06d-897d-4775-ae4d-d613166e3d16` |
| Apple ID | `6776864670` |
| 1차 리젝 | 2026-06-07 · build 6 |
| 2차 리젝 | 2026-08-12 · build 15 |
| 3차 제출 | 2026-08-25 · **2.0.0 (18)** — 게이트 제거 + 2단계 리뷰 노트 |
| Submission ID 주의 | ID 가 유지되는 것은 **ASC 제출 모델의 정상 동작**이다. 리젝된 제출이 열린 채 남고 거기에 항목을 갱신해 다시 넣는 구조라, 버전을 2.0.0 으로 올려도 새 ID 가 나지 않는다. 이걸 "애플이 대충 봤다"는 근거로 쓰면 안 된다 (2026-08-25 실측 확인) |
| 제출 경로 | App Review Board appeal (Resolution Center 답장 아님) |
| 출시 지역 | **대한민국 단독** — 편지의 ON DISTRIBUTION 논거 |
| 앱 이름 | `관상은 과학이다` **변경 없음** — 편지에서 정면 설명 (§0.2) |

---

## 0. 보내기 전 선행 작업

### 0.1 심사관 동선 — 이게 최우선이다

편지가 "주 기능은 그룹 매칭"이라고 주장하는데 심사관 화면이 관상 리포트만 보여주면,
**편지가 아니라 화면이 이긴다.** 세 번째 거절은 여기서 난다.

| | 상태 |
| --- | --- |
| 그룹 목록을 관상 없이 볼 수 있게 (`chemistry_screen.dart`) | ✅ 완료 |
| 관상·궁합 탭도 게이트 제거 — 등록 전후로 화면 구조가 안 바뀐다 | ✅ 완료 |
| 빈 화면이 그 탭의 역할을 직접 말한다 (케미 = "그룹에서 나와 가장 맞는 사람을 점수로") | ✅ 완료 |
| 리뷰 노트 — 로그인 전/후 2단계 동선으로 재작성 | ✅ 완료 |
| 데모 방 seed 실행 + `<PW>` 기입 | ⬜ **제출 전 필수** |

전에는 케미 탭이 관상 미등록 상태에서 어깨 으쓱 그림과 *"내 관상을 등록하면 케미
그룹에 참가할 수 있습니다"* 만 보여줬다. 앱이 심사관에게 **관상이 선행조건이라고
직접 말하고 있었다.** 지금은 목록·상세·케미 개념이 전부 열려 있고, 관상은 **참가
버튼을 눌렀을 때** 요구된다 (`team_detail_screen.dart::_join`).

관상·궁합 탭도 같은 원칙으로 정리했다. 예전엔 미등록이면 탭 바를 감추고 등록
안내 화면으로 통째로 갈아치웠는데, 지금은 **등록 여부와 무관하게 탭 구조가
그대로**다. 그리고 각 빈 탭이 자기가 무엇을 담는 자리인지 직접 말한다 — 케미 탭은
*"그룹 내에서 나와 조화가 가장 잘 맞는 사람이 누구인지 점수로 알려줍니다"* 로
열린다. **심사관이 방에 들어가지 않아도 첫 화면에서 제품 정의를 읽는다.** 편지가
아니라 화면이 이긴다면, 화면이 같은 말을 하게 만들어야 한다.

### 0.2 앱 이름 — 그대로 두고 편지에서 정면으로 설명한다

**앱 이름은 `관상은 과학이다` 를 바꾸지 않는다.** 영문 로케일도 추가하지 않는다.

한국 전용 출시라 primary language 가 한국어이고, 대표 이름은 계속 한국어다.
영문 로케일을 하나 더 만들어도 **심사관 눈에서 한국어 이름이 사라지지 않는다** —
비영어권 앱 심사에는 번역이 기본으로 들어간다. 우회가 안 되는 문제다.

어차피 보이고 번역된다면 **설명 없이 두는 게 최악**이다. 심사관이
`Physiognomy Is Science` 를 혼자 해석하게 된다.

그래서 편지에 `ON THE APP NAME` 문단을 넣는다. 논거는 **영어에도 같은 어법이
있다**는 것 — *sales is a science*, *parenting is a science*. 한국어 `야구는
과학이다`·`다이어트는 과학이다` 와 뜻이 같다. 둘 다 "운이 아니라 반복 가능한
방법이 있다"는 뜻이지 동료심사 논문이 있다는 주장이 아니다.

그리고 **이름이 결정적이면 그렇다고 말해달라**고 편지에서 명시적으로 요구한다.
두 번 다 같은 템플릿만 받아서 추론이 안 되는 유일한 항목이다.

앱 로케일과 **별개로** 이 둘은 무조건 영어다 — App Review Information 의 리뷰
노트(§2), 그리고 어필 편지 본문.

### 0.3 라벨 정리 — 완료

| 위치 | 변경 |
| --- | --- |
| `Attribute.wealth` | `Wealth Fortune` → **`Financial Strength`** (`재물운` → `재력`) |
| `Attribute.sensuality` | `Sensuality` → **`Magnetism`** (`바람기` → `흡인력`) |
| `Attribute.libido` | `Sexual Energy` → **`Vitality`** (`관능도` → `활력`) |

`Fortune` 은 조문의 단어 그 자체라 최우선이었다. `Attribute.trustworthiness` 는
**유지한다** — Todorov 의 valence 축이 정확히 이 항목이라 유일하게 문헌이 받쳐준다.

---

## 1. 편지 전문

```text
Subject: Appeal — Guideline 4.3(b), Submission ID
         e699a06d-897d-4775-ae4d-d613166e3d16

We are appealing the 4.3(b) rejection of our app (Apple ID 6776864670).

We would like to be direct about what the app is, because we think the
rejection rests on a factual question we can answer rather than on a
judgment we should argue with.

WHAT THE APP IS

The app is a group social product. Its purpose is to let a group of
people — a club, a class, a company team, a set of strangers who joined
the same open room — see how they pair with one another, and use that as
an opening to talk.

The unit of the product is the room, not the individual. A room holds up
to N participants. When participants join, the app computes a pairwise
compatibility matrix across everyone present and surfaces the strongest
pairs. Chat, blocking, and reporting are built on top of that. A single
user alone cannot complete the product's core loop; there is nothing to
compare against.

WHERE PHYSIOGNOMY COMES IN

The input to that matrix is facial measurement, interpreted through East
Asian physiognomy — a folk classification tradition with several
centuries of written record in Korea, China, and Japan.

We use it for two reasons, and we want to state both plainly:

1. It is a familiar, culturally resonant vocabulary in our market. It
   makes the pairing result legible and fun to talk about, which is
   exactly what an icebreaker needs to be.

2. It is a classification scheme that produces stable, well-distributed
   categories from a face, which is what a matching engine needs.

We are not neutral about this and we are not hiding it. The Korean app
name references physiognomy directly.

ON WHAT PHYSIOGNOMY IS

We think this is worth a paragraph, because the English word carries
associations that the Korean subject does not.

East Asian physiognomy is a written compilation of folk observation
about faces, accumulated and systematized over several centuries. Its
content is of the form "people with this feature were often found to be
like this" — inference from appearance to disposition, recorded, argued
over, and organized into a scheme. It is a body of claims about
correlation, assembled before anyone had the tools to test correlation.

Traditions of this kind exist because the underlying behavior is
universal. People read faces and form judgments from them everywhere,
and every language we know of carries the vocabulary for it — an honest
face, a hard face, a kind face. This is one of the better-established
findings in face perception research: such inferences are made rapidly,
and different observers agree with one another to a striking degree
(Oosterhof & Todorov, PNAS, 2008). That work establishes that the
judgments are consistent. It does not establish that they are correct,
and we are not claiming that it does.

What separates these traditions is not whether the inference happens but
how a culture wrote it down. East Asian physiognomy wrote it down in
unusual detail, mapping specific facial regions to specific domains of
life. That map is what our engine encodes.

We should be straightforward about one thing. The tradition is not
uniform. Alongside its descriptive material it also contains
fortune-telling — claims about a person's future, their fate, the year
their luck turns. We do not carry that layer. The app's text is written
entirely in the present tense and describes only how the tradition read
a given feature. This was an editorial decision on our part, and it is
verifiable in the product rather than only asserted here.

ON THE APP NAME

The Korean name translates literally as "Physiognomy Is Science." We
want to be clear about how that phrase reads to the audience it is
written for, because the literal translation is misleading.

"X is a science" is an idiomatic construction in Korean — 야구는
과학이다 ("baseball is a science"), 다이어트는 과학이다 ("dieting is a
science") — used the same way the English phrases "sales is a science"
or "parenting is a science" are used. It asserts that something has a
repeatable method rather than being luck. It is a hook, and native
speakers read it as one.

It is not a claim of scientific validation, and the app does not make
that claim to users. Where the app conveys a traditional reading, the
tradition is the stated subject.

We are keeping the name because it is how our market recognizes the
product. If the Board considers the name itself determinative under
4.3(b), we would ask to be told that specifically. It is the one
element we cannot infer from the template we have now received twice.

ON DISTRIBUTION

The app is released in South Korea only. It is written in Korean, for a
Korean cultural reference that does not translate cleanly, and we have
no plan to distribute it elsewhere.

We mention this because we understand 4.3(b) to be aimed at a pattern:
large numbers of interchangeable applications pushed into every
territory at once. This app is the opposite shape — a single-market
product built around a local cultural vocabulary, with a group social
mechanic that only works if the people in a room already know each
other or want to.

WHAT THE APP DOES NOT DO

It does not ask for a birth date, birth time, or birth place. There is
no such field anywhere in the application; this is verifiable by
inspection.

It does not produce horoscopes, daily fortunes, lucky numbers, lucky
colors, auspicious dates, or any periodic reading.

It does not tell a user what will happen to them. The report describes
what was measured and how the tradition reads that measurement, in the
present tense. It makes no claim about future events.

It does not deliver a fixed set of pre-written results. Every value in
every report is computed on the device from that person's own facial
landmarks. Two users do not receive the same text.

HOW THE MEASUREMENT WORKS

We detect 468 facial landmarks, compute 26 dimensionless ratios and
angles, and express each as a position within a measured reference
distribution built from 11,800 East Asian frontal photographs
(male 5,361 / female 6,439, yaw < 18 degrees). The reference is
empirical, not modeled — it comes from running those photographs through
the same pipeline the app runs on the user.

We recently corrected two defects in this pipeline: measurements were
distorted by image aspect ratio, and the reference distribution had been
generated synthetically rather than from the photographs. Both are
fixed and covered by tests. We mention this because it reflects how we
treat the measurement layer — as engineering that has to be correct,
independent of what the tradition then says about it.

ON THE TRADITION'S VALIDITY

We make no claim that East Asian physiognomy is predictive, and the app
does not tell users that it is. Where the app conveys a traditional
reading, the tradition is the stated subject — "this is how this face
has been read" — not our own assertion about the person.

We raise this only to be clear about scope. We do not believe 4.3(b)
turns on it, since the guideline addresses category saturation rather
than accuracy.

WHY WE BELIEVE THIS IS NOT THE NAMED CATEGORY

The rejection states the app "primarily features fortune telling."

We would ask the Board to weigh what the app's primary feature actually
is. The room, the multi-participant matrix, the ranked pairs, and the
chat that follows are the product. The facial reading is the input that
feeds them and the conversational material they hand back to users.

The category the guideline targets is, as we understand it, saturated
with applications that are complete as a single-user daily reading. This
app is not complete as a single-user experience at all.

We recognize the reviewer may not have reached the group flow. Until
this build, a reviewer who had not registered a face was shown a
registration prompt in place of the app's own screens, which meant
testing alone surfaced only the individual reading.

That is changed in this submission. The app no longer replaces its
screens with a prompt. Every tab keeps its structure whether or not a
face is registered, and each one states in plain language what it holds
and what it is for. The chemistry tab opens by saying that it scores
who, within a group, fits best with you — a reviewer reads the product's
purpose on the first screen without registering anything or joining
anything. The open-room list itself is fully browsable, with real rooms
in it; a face is requested only at the moment one taps to join.

We have also included review notes with a demo account and a populated
room so the group flow can be exercised directly.

WHAT WE ARE ASKING

If the Board's determination is that this app falls within 4.3(b)
regardless of the above, we would appreciate knowing which element is
determinative — the physiognomy vocabulary itself, the app name, or
something else. We would rather act on a specific criterion than
resubmit on a guess. We have now submitted three times and received the
same template each time, most recently after removing the registration
gate that we believe had kept the group flow out of the reviewer's
reach.
```

---

## 2. 리뷰 노트 문안 (App Store Connect → App Review Information)

```text
IMPORTANT — the core feature of this app is group compatibility, not
the individual face reading. Please follow both stages below. Stage 1
requires no account and takes about thirty seconds.


STAGE 1 — nothing is gated (no sign-in required)

1. Launch the app. Do not sign in.

2. Tap the "케미" (Chemistry) tab — the THIRD tab in the bottom bar.

3. The "모집중" (Open rooms) list loads immediately. Two public rooms
   are open:
     "퇴근 후 러닝 크루"      — 4 of 8 joined
     "홍대 보드게임 소모임"   — 2 of 6 joined
   Tap either to see its roster and room detail.

   No face registration and no account is required to reach any of
   this. The tab states in plain language what the product does: it
   scores who, within a group, fits best with you.


STAGE 2 — the compatibility matrix (sign-in required)

Demo account:  chuckau@naver.com
Password:      <PW>

4. Sign in with the demo account (설정 tab → 로그인).

5. Return to the "케미" tab and switch to the "내 그룹" (My groups)
   sub-tab.

6. Open the room "금요일 저녁 미술관 동행" ("Friday Evening Museum
   Outing"). It holds 6 participants and is full.

7. The room shows the pairwise compatibility matrix across all six
   participants, with the pairs ranked. The demo account is in the
   top-ranked pair, at 88 points.

8. Tap any pair to see the per-attribute breakdown behind its score.

9. Accepting the top pair opens a 1:1 chat. Reporting and blocking are
   available there — long-press a message, or tap a participant.


WHAT THE NUMBERS ARE

Every score is computed on-device from each participant's own facial
landmarks. Two rooms with different people produce different matrices;
nothing is pre-written.

There is no birth date, birth time, or birth place field anywhere in
the app. There are no horoscopes, no daily fortunes, no lucky numbers,
and no prediction of future events.

Face processing runs on-device. Landmarks are converted to
dimensionless ratios immediately; the app does not perform facial
recognition and does not match a face against any database.

The app is distributed in South Korea only and its interface is Korean.
```

⬜ `<PW>` 채우기 · 데모 방 seed 실행(`web/db/tests/demo_teams.sql`) — **제출 전 필수**

데모 계정은 `chuckau@naver.com`(홍청). 방·참가자는 seed 가 만든다 — 참가자 9명은
실제 my-face 계측을 갖고 있어 매트릭스가 진짜 숫자로 나온다. 심사관이 여는 방
④ `금요일 저녁 미술관 동행` 에 홍청이 베스트 쌍 당사자로 들어 있다.

⚠️ seed 는 `delete from public.teams` 로 시작한다 — 실행 시점의 모든 방이
FK cascade 로 사라진다 (team_members·team_matches·team_messages·team_reports).

---

## 3. 검증된 사실 (편지의 각 주장 근거)

| 편지의 주장 | 근거 |
| --- | --- |
| 생년월일 필드 없음 | `flutter/lib` + `shared/lib` grep 0건 |
| 출력이 사용자마다 계산됨 | `face_analysis.dart::analyzeFaceReading` — 템플릿 없음 |
| 468 랜드마크 · 26 metric | `face_metrics.dart::computeAll()` |
| 11,800장 실측 레퍼런스 | `face_reference_data.dart` · `tools/face_shape_ml/extract_aaf.py` |
| 종횡비 결함 수정 | `46cb40e6` · `test/face_metrics_isotropy_test.dart` |
| 합성 분포 → 실측 교체 | `d0f4c8f2` · `test/calibration_empirical_test.dart` |
| 신고·차단 구현됨 | `team_reports` 테이블 · `blockUser`/`unblockUser` |
| 그룹 목록 게이트 제거 | `chemistry_screen.dart` — 참가 시점 게이트만 유지 |
| 미래 시제 없음 | `narrative_corpus_v2.dart` 문장 규칙 |

---

## 4. 근거 문헌

논문은 **주장이 아니라 각주**로 쓴다. 편지는 예측 정확도를 주장하지 않으므로
문헌으로 반박당할 표면이 없다. 아래는 질문받았을 때의 대비다.

### 쓸 수 있는 것

| 문헌 | 무엇을 받쳐주나 |
| --- | --- |
| [Farkas et al. — International Anthropometric Study of Facial Morphology](https://www.researchgate.net/publication/7682966_International_Anthropometric_Study_of_Facial_Morphology_in_Various_Ethnic_GroupsRaces) | 얼굴 계측이 확립된 분야. 25개 민족 1,470명 |
| [CDC 3D Facial Norms Database](https://stacks.cdc.gov/view/cdc/39061) | 공공기관이 유지하는 계측 규범 DB |
| [Oosterhof & Todorov (2008), PNAS](https://www.pnas.org/doi/10.1073/pnas.0805664105) | 얼굴에서 특성을 읽는 지각이 일관되게 측정됨 (**정확성은 아님**) |

### 절대 인용하지 않는 것 — 상대의 무기

| 문헌 | 상대가 인용할 내용 |
| --- | --- |
| [Kachur et al. (2020), Sci Rep](https://www.nature.com/articles/s41598-020-65358-6) | 얼굴→성격 평균 효과크기 **0.243** |
| [Megastudy (2023), Sci Rep](https://www.nature.com/articles/s41598-023-42054-9) | 349개 속성 중 **23%만** 무작위보다 나음 |
| [Current Opinion in Behavioral Sciences (2024)](https://www.sciencedirect.com/science/article/abs/pii/S2352250X24000289) | *"these inferences are not very accurate"* |

**"관상은 과학적으로 검증됐다"를 주장하는 순간 위 셋이 그대로 반박이 된다.**
편지가 앱 이름을 관용 어법으로 설명하고 타당성 주장을 명시적으로 부인하는 이유가
이것이다 (§0.2).

### 한국 학계 (문화·사상 층위)

| 논문 | 성격 |
| --- | --- |
| [관상학의 경험적 진화: 학문적 변용과 현재적 유효성](https://scienceon.kisti.re.kr/srch/selectPORSrchArticle.do?cn=DIKO0014783781) | 전통적 범주화의 한계 + 경험적 재구성 |
| [관상의 성립과 심상(心相)에 관한 연구](https://www.kci.go.kr/kciportal/ci/sereArticleSearch/ciSereArtiView.kci?sereArticleSearchBean.artiId=ART002564501) | 사상사 |
| [동양 관상학을 적용한 성격별 얼굴 설계 시스템](https://www.kci.go.kr/kciportal/ci/sereArticleSearch/ciSereArtiView.kci?sereArticleSearchBean.artiId=ART001273446) | 얼굴형·눈·코·입·이마·눈썹 코드화 |

관상이 **학술적 대상**이라는 건 증명하지만 예측력을 검증한 게 아니다. 편지 본문에
인용하지 않는다. 문화 전통이라는 §"WHERE PHYSIOGNOMY COMES IN" 서술의 뒷받침으로만
쓴다.

---

## 5. 제출 전 체크리스트

| | |
| --- | --- |
| ✅ | 새 **버전 번호**로 빌드·업로드 (2.0.0+18). Submission ID 는 그대로 유지된다 — 정상 동작이다 (§0 표 참조) |
| ✅ | App Store Connect `2.0.0` + 빌드 18 첨부 · 2026-08-25 제출 완료 |
| ✅ | 스크린샷 교체 (6.9" 1320×2868, 알파 제거) |
| ✅ | 리뷰 노트 + 로그인 정보 (`chuckau@naver.com`) 기입 |
| ✅ | 데모 데이터 — 운영 DB 에 이미 존재 (완료 방 3 + 모집중 1). 복구는 `web/db/tests/demo_teams.sql` |
| ✅ | 대한민국 단독 배포 · 카테고리 소셜 네트워킹 · 한국 등급 15+ |
| ✅ | 앱 이름 유지 + 편지에 ON THE APP NAME 문단 |
| ✅ | 그룹 목록 게이트 제거 |
| ✅ | 속성 라벨 정리 |
| ✅ | 계측·레퍼런스 결함 수정 |
