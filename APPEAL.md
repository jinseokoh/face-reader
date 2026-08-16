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
| 2차 리젝 | 2026-08-12 · build 15 (**같은 Submission ID** → 새 심사가 아니라 템플릿 재확인) |
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
| 리뷰 노트에 데모 계정 + 사람이 들어있는 방 + 단계 | ⬜ **제출 전 필수** |

전에는 케미 탭이 관상 미등록 상태에서 어깨 으쓱 그림과 *"내 관상을 등록하면 케미
그룹에 참가할 수 있습니다"* 만 보여줬다. 앱이 심사관에게 **관상이 선행조건이라고
직접 말하고 있었다.** 지금은 목록·상세·케미 개념이 전부 열려 있고, 관상은 **참가
버튼을 눌렀을 때** 요구된다 (`team_detail_screen.dart::_join`).

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
this build, the room list was gated behind registering one's own face,
which meant a reviewer testing alone would have seen only the individual
reading. That gate is removed in this submission, and we have included
review notes with a demo account and a populated room so the group flow
can be exercised directly.

WHAT WE ARE ASKING

If the Board's determination is that this app falls within 4.3(b)
regardless of the above, we would appreciate knowing which element is
determinative — the physiognomy vocabulary itself, the app name, or
something else. We would rather act on a specific criterion than
resubmit on a guess. We have now submitted twice and received the same
template both times, with the second review carrying the same Submission
ID as the first.
```

---

## 2. 리뷰 노트 문안 (App Store Connect → App Review Information)

```text
IMPORTANT — testing the core feature requires the group flow.

Testing alone will only show the individual face reading, which is the
INPUT to this app, not its purpose. The product is group compatibility
matching. Please use the demo account below to reach it.

Demo account:  <ID>
Password:      <PW>

Steps:
1. Sign in with the demo account.
2. Open the "케미" (Chemistry) tab — the second tab in the bottom bar.
3. The "모집중" (Open rooms) list is browsable without registering a
   face. Room "<ROOM NAME>" is pre-populated with N participants.
4. Open that room. Scroll to the compatibility matrix — every pair of
   participants is scored, and the top pairs are ranked.
5. Tap any pair to see why they scored as they did.
6. Reporting and blocking are available from the chat screen inside the
   room (long-press a message / tap a participant).

There is no birth date, birth time, or horoscope anywhere in the app.
Every number shown is computed on-device from the participant's own
facial landmarks.

Face processing runs on-device. Landmarks are converted to
dimensionless ratios immediately; the app does not perform facial
recognition and does not use the face to identify a person against any
database.

The app is distributed in South Korea only and its interface is Korean.
```

⬜ `<ID>` · `<PW>` · `<ROOM NAME>` · 참가자 N명 채우기 — **제출 전 필수**

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
| ⬜ | 새 **버전 번호**로 제출 (2.0.0) — 같은 버전에 빌드만 올리면 Submission ID 가 유지돼 템플릿 재확인만 돌아온다 |
| ⬜ | 리뷰 노트에 데모 계정·방·단계 기입 (§2) |
| ⬜ | 데모 방에 참가자 N명 미리 채워두기 |
| ⬜ | 출시 지역이 **대한민국 단독**으로 설정돼 있는지 확인 (편지 논거의 전제) |
| ✅ | 앱 이름 유지 + 편지에 ON THE APP NAME 문단 |
| ✅ | 그룹 목록 게이트 제거 |
| ✅ | 속성 라벨 정리 |
| ✅ | 계측·레퍼런스 결함 수정 |
