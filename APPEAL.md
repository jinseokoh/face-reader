# APPEAL — Guideline 4.3(b)

App Review Board 정식 appeal 문안. 프레임은 **계측 도구(measurement instrument)** —
"관상이 맞다"가 아니라 "이 앱은 측정하고, 출력은 개인마다 계산된다".

| | |
| --- | --- |
| Submission ID | `e699a06d-897d-4775-ae4d-d613166e3d16` |
| Apple ID | `6776864670` |
| 1차 리젝 | 2026-06-07 · build 6 |
| 2차 리젝 | 2026-08-12 · build 15 (**같은 Submission ID**) |
| 제출 경로 | App Review Board appeal (Resolution Center 답장 아님) |

---

## ⚠️ 보내기 전 선행 작업

아래 라벨이 남아 있으면 **편지의 `we make no predictive claim` 이 앱 화면 한 장으로 무너진다.**
심사관은 번역할 필요도 없다 — 영문 라벨에 그대로 적혀 있다.

| 위치 | 지금 | 문제 |
| --- | --- | --- |
| `shared/lib/data/enums/attribute.dart` `Attribute.wealth` | **`Wealth Fortune` / `재물운`** | `Fortune` 이 조문의 단어 그 자체. 최우선 |
| 같은 파일 `Attribute.sensuality` | **`Sensuality` / `바람기`** | 얼굴로 외도 성향 예측. 영·한 의미도 불일치 |
| 같은 파일 `Attribute.libido` | `Sexual Energy` / `관능도` | 통과는 되나 계측 도구 프레임과 충돌 |

`Attribute.trustworthiness` 는 **유지한다.** Todorov 의 valence 축이 정확히 이 항목이라
유일하게 문헌이 받쳐준다.

라벨 교체는 enum 라벨 두 줄씩이라 코드 구조를 건드리지 않는다.

---

## 편지 전문

```text
Subject: Appeal — Guideline 4.3(b), Submission ID
         e699a06d-897d-4775-ae4d-d613166e3d16

We are appealing the 4.3(b) rejection of our app (Apple ID 6776864670).

THE REJECTION BASIS

The letter states the app "primarily features astrology, horoscopes,
palm reading, fortune telling or zodiac reports that duplicate the
content and functionality of similar apps."

We would like to address the word "primarily," and describe what the
app actually measures and computes, so that each statement below can be
verified directly in the build.

WHAT THE APP DOES

The app is an on-device facial measurement instrument. Using MediaPipe
Face Mesh it extracts 468 facial landmarks and derives 26 frontal and 8
lateral anthropometric metrics — interocular distance, facial thirds,
nasal width ratio and similar proportions. These are compared against a
reference distribution we derived from measurements of 11,800 East
Asian facial photographs (frontal, yaw < 18°; 5,361 male, 6,439
female).

Facial anthropometry is an established measurement discipline.
Normative craniofacial databases are used in reconstructive surgery;
Farkas et al. published an international study covering 14 craniofacial
measurements across 25 ethnic groups, and the CDC maintains the 3D
Facial Norms Database. Our reference set is of the same kind, built for
an East Asian population.

No landmark data or measurement leaves the device. The entire
computation runs locally.

WHY THIS IS NOT THE CATEGORY NAMED

Apps in the astrology and fortune-telling category select pre-written
content using categorical input — date of birth, zodiac sign, calendar
position. The output is drawn from a fixed corpus and is identical for
every user sharing that input.

This app has no such corpus and no such input. There is no birth date
field anywhere in the app. There is no zodiac, no calendar, and no
divination input of any kind. Every value shown is computed from the
individual user's own measured landmark geometry, and no two users
receive the same output because no two users share the same geometry.

THE GROUP FEATURE

The app's primary feature has no counterpart in the category named. A
user creates a room; participants join by QR code or invite link; when
the room reaches capacity the app computes a full pairwise comparison
matrix across all participants, announces the closest-matching pair,
and opens a 1:1 chat between them upon mutual consent. Rooms expire,
and results are purged on a schedule.

This recruit → reveal → match → chat flow is what the app is built
around. We are not aware of any app in the named category that has it.

WHAT WE ARE ASKING

We are not asking the Board to accept that facial measurement predicts
anything, and we make no such claim to users.

We are asking for a determination on the question the guideline raises:
whether an app whose every output is computed per-user from on-device
anthropometric measurement, and whose primary feature is a
multi-participant comparison and matching flow, falls within the
category the rejection names.

If it does, we would appreciate knowing which element is determinative,
so that we can act on it rather than guess.
```

---

## 근거 문헌

논문은 **주장이 아니라 각주**로 쓴다. 예측 정확도를 주장하면 같은 문헌으로 되받힌다.

### 쓸 수 있는 것

| 문헌 | 무엇을 받쳐주나 |
| --- | --- |
| [Farkas et al. — International Anthropometric Study of Facial Morphology](https://www.researchgate.net/publication/7682966_International_Anthropometric_Study_of_Facial_Morphology_in_Various_Ethnic_GroupsRaces) | 얼굴 계측이 확립된 분야. 25개 민족 1,470명, 14개 두개안면 계측 |
| [CDC 3D Facial Norms Database](https://stacks.cdc.gov/view/cdc/39061) | 공공기관이 유지하는 계측 규범 DB |
| [Oosterhof & Todorov (2008), PNAS](https://www.pnas.org/doi/10.1073/pnas.0805664105) | 얼굴에서 특성을 읽는 지각이 일관되게 측정된다는 것 (**정확성은 아님**) |

### 쓰면 안 되는 것 — 반대편의 무기

| 문헌 | 상대가 인용할 내용 |
| --- | --- |
| [Kachur et al. (2020), Sci Rep](https://www.nature.com/articles/s41598-020-65358-6) | 얼굴→성격 평균 효과크기 **0.243**. 우연보다 낫지만 약하다 |
| [Megastudy (2023), Sci Rep](https://www.nature.com/articles/s41598-023-42054-9) | 349개 속성 중 **23%만** 무작위보다 나음 |
| [Current Opinion in Behavioral Sciences (2024)](https://www.sciencedirect.com/science/article/abs/pii/S2352250X24000289) | *"these inferences are not very accurate"* |

**"관상은 과학적으로 검증됐다"를 주장하는 순간 위 셋이 그대로 반박이 된다.**
그리고 4.3(b) 는 애초에 정확성을 묻지 않았다 — 편지가 먼저
*"may include features or characteristics that distinguish it"* 이라고 인정해뒀다.

### 한국 학계 (문화·사상 층위)

| 논문 | 성격 |
| --- | --- |
| [관상학의 경험적 진화: 학문적 변용과 현재적 유효성](https://scienceon.kisti.re.kr/srch/selectPORSrchArticle.do?cn=DIKO0014783781) | 전통적 범주화의 한계 지적 + 경험적 재구성 가능성 |
| [관상의 성립과 심상(心相)에 관한 연구](https://www.kci.go.kr/kciportal/ci/sereArticleSearch/ciSereArtiView.kci?sereArticleSearchBean.artiId=ART002564501) | 사상사 |
| [동양 관상학을 적용한 성격별 얼굴 설계 시스템](https://www.kci.go.kr/kciportal/ci/sereArticleSearch/ciSereArtiView.kci?sereArticleSearchBean.artiId=ART001273446) | 얼굴형·눈·코·입·이마·눈썹 코드화 |

학술적 대상이라는 건 증명하지만 **예측력을 검증한 게 아니다.** 편지 본문에 인용하지 않는다.

---

## 검증된 사실 (편지의 각 주장 근거)

| 편지의 주장 | 확인 |
| --- | --- |
| 468 landmarks · 26 frontal + 8 lateral metric | `flutter/CLAUDE.md` |
| 11,800장 East Asian reference (male 5,361 / female 6,439, yaw < 18°) | `shared/lib/data/constants/face_reference_data.dart:254` |
| 온디바이스 계산, 업로드 없음 | `0001_baseline.sql:200` — landmarks 는 키 존재 자체로 차단 |
| **생년월일 필드 없음** | `flutter/lib`·`shared/lib` 전체 grep 결과 0건 |
| 방 생성 · QR/링크 조인 · 정원 충족 자동 공개 · N×N · 상호동의 채팅 | `team_service.dart` · `team_*` 테이블 |
| 방 만료 · 결과 purge | `web/workers/cron.ts` |

---

## 톤 원칙

포럼 글에도 같이 적용한다.

| 쓰지 않는다 | 대신 |
| --- | --- |
| `undemocratic` | `protectionist` — 사기업이라는 반론이 안 통한다 |
| 비유 (특히 집단을 소재로 한 것) | 조문 인용 + 사실 |
| "지치게 만드는 전략" | 같은 Submission ID 사실 (검증 가능) |
| "관상은 과학이다" | "출력이 개인마다 계산된다" |
