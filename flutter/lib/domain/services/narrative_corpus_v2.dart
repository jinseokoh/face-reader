part of 'life_question_narrative.dart';

// ═══════════════════════════════════════════════════════════════════════
// 인생 질문 서술 코퍼스 v2 — 현재 시제
//
// v1 과의 차이는 두 층이다.
//
//   1. 섹션 제목 — 운명 어휘 제거. `재물운`→`재력`, `관능도`→`활력`,
//      `연애운`→`연애`, `건강과 수명`→`건강`.
//   2. 문장 — 미래·운명 시제(`말년`·`노년`·`평생`) 를 현재 서술로.
//
// **이행 전략** — 2번은 문장 544개라 한 번에 못 바꾼다. 그래서 각 섹션의
// 풀은 v1 을 가리킨 채로 시작하고, 코퍼스가 준비된 섹션부터 `_v2*Beats` 로
// 교체한다. 그동안에도 v2 는 항상 온전한 리포트를 만든다 — 제목만 먼저
// 정리된 상태로.
//
// 교체 순서 제안 (운명 어휘 밀도 높은 순):
//   재력 → 건강 → 연애 → 활력 → 대인관계 → 타고난 재능 → 종합 조언
// ═══════════════════════════════════════════════════════════════════════

/// v2 섹션 정의. `pools` 가 `_v1` 풀을 가리키는 항목은 아직 문장 미작성.
final List<_SectionDef> _v2Sections = [
  (
    title: '타고난 재능',
    salt: 10,
    pools: (f) => _talentBeats, // TODO v2 코퍼스
    when: null,
  ),
  (
    title: '건강',
    salt: 70,
    pools: (f) => _healthBeats, // TODO v2 코퍼스
    when: null,
  ),
  (
    title: '재력',
    salt: 20,
    pools: (f) => _wealthBeats, // TODO v2 코퍼스 — 최우선
    when: null,
  ),
  (
    title: '대인관계',
    salt: 30,
    pools: (f) => _socialBeats, // TODO v2 코퍼스
    when: null,
  ),
  (
    title: '연애',
    salt: 40,
    pools: (f) => f.isMale ? _romanceBeatsMale : _romanceBeatsFemale,
    when: null, // TODO v2 코퍼스
  ),
  (
    title: '활력',
    salt: 60,
    pools: (f) => f.isMale ? _sensualBeatsMale : _sensualBeatsFemale,
    when: (f) => f.age.isOver30, // TODO v2 코퍼스
  ),
  (
    title: '종합 조언',
    salt: 80,
    pools: (f) => _conclusionBeats, // TODO v2 코퍼스
    when: null,
  ),
];
