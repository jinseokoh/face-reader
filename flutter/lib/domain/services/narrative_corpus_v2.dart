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

/// 백분위(0..1) → 한국어 구절. `@{pct:wealth}` 슬롯이 이걸 부른다.
///
/// 값의 출처는 `attributePercentile()` — 같은 성별·얼굴형 quantile 테이블에서의
/// 위치다. 외부 연구가 아니라 **자체 분포**라서 문장이 참임이 보장된다.
/// 1% 미만·99% 초과는 과장으로 읽히므로 1~50 으로 clamp 한다.
String _v2PctPhrase(double p) {
  if (p >= 0.5) return '상위 ${((1 - p) * 100).round().clamp(1, 50)}%';
  return '하위 ${(p * 100).round().clamp(1, 50)}%';
}

// ─── 재력 opening — v2 첫 샘플 풀 ────────────────────────────────────────
//
// 문장 규칙 (§D):
//   [백분위 사실]  같은 성별·얼굴형 분포에서 @{pct:wealth} 입니다.
//   [경향 서술]    이 구간에서는 ~하는 경향이 더 자주 관찰됩니다.
//
// - 미래 시제 금지 (`말년`·`평생`·`~정합니다`)
// - 은유 금지 (`돈이 머물고 싶어하는 얼굴`)
// - 뒷문장은 단정이 아니라 관찰 (`~더 자주 관찰됩니다` / `~쪽이 많습니다`)
// - 조건은 v1 `_wealthOpening` 과 1:1 대응
final List<_Frag> _v2WealthOpening = [
  _Frag(_highPair(Attribute.wealth, Attribute.stability), [
    '재력이 같은 성별·얼굴형 분포에서 @{pct:wealth}, 안정성도 함께 높은 구간입니다. 벌어들이는 항목과 유지하는 항목이 같이 높게 나오는 조합은 흔하지 않습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.mid), [
    '재력이 @{pct:wealth} 구간이고 안정성은 평균대입니다. 기회를 알아보는 항목의 값이 높고, 손실을 감당하는 항목은 평균에 가깝습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.high, Attribute.stability, _Band.low), [
    '재력은 @{pct:wealth} 구간인데 안정성이 낮은 쪽입니다. 이 조합에서는 들어오는 흐름과 나가는 흐름이 함께 커지는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.high), [
    '재력은 평균대이고 안정성이 @{pct:stability} 구간입니다. 크게 움직이는 쪽보다 유지하는 쪽에 값이 실려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.mid), [
    '재력과 안정성이 모두 평균대에 놓여 있습니다. 한쪽으로 치우친 값이 없어서, 돈에 대한 판단이 상황마다 크게 흔들리는 일이 적은 편입니다.',
    '재력이 @{pct:wealth} 구간으로 분포 가운데에 있습니다. 위험을 크게 걸지도, 지나치게 움츠러들지도 않는 쪽이 많습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.mid, Attribute.stability, _Band.low), [
    '재력은 평균대인데 안정성이 @{pct:stability} 구간입니다. 판단 자체보다 판단하는 시점이 흔들리는 경우가 더 자주 관찰됩니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.high), [
    '재력은 @{pct:wealth} 구간이고 안정성이 높은 쪽입니다. 새로 만드는 항목보다 유지하는 항목에 값이 몰려 있습니다.',
  ]),
  _Frag(_bandPair(Attribute.wealth, _Band.low, Attribute.stability, _Band.mid), [
    '재력이 @{pct:wealth} 구간이고 안정성은 평균대입니다. 두 항목 모두 큰 변동을 만드는 쪽은 아닙니다.',
  ]),
  _Frag(_lowPair(Attribute.wealth, Attribute.stability), [
    '재력과 안정성이 모두 분포 아래쪽에 있습니다. 측정값이 돈 쪽보다 다른 항목에 몰려 있다는 뜻이고, 이 구성에서는 재능·관계 항목이 상대적으로 높게 나오는 경우가 많습니다.',
  ]),
  _Frag.hard((f) => true, [
    '재력이 같은 성별·얼굴형 분포에서 @{pct:wealth} 구간입니다. 한 번의 큰 결정보다 같은 선택을 반복하는 쪽에 값이 몰려 있습니다.',
    '재력 항목이 @{pct:wealth} 구간에 놓여 있습니다. 변화를 만드는 힘보다 유지하는 힘이 더 크게 측정됩니다.',
    '재력이 @{pct:wealth} 구간으로 측정됩니다. 결과가 예측되는 선택에서 값이 높게 나오는 구성입니다.',
  ]),
];

/// 재력 v2 — opening 만 v2, 나머지 4풀은 아직 v1.
final List<_BeatPool> _v2WealthBeats = [
  _v2WealthOpening,
  _wealthVignette, // TODO v2
  _wealthStrength, // TODO v2
  _wealthShadow, // TODO v2
  _wealthAdvice, // TODO v2
];

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
    pools: (f) => _v2WealthBeats, // opening 만 v2 완료
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
