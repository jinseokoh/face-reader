/// 궁합 engine 의 각 rule/pattern evidence 를 narrative 용 구조로 변환.
///
/// `CompatFinding` 하나 = 핵심 궁합 · 갈등 시나리오 · 운영 전략 세 섹션이
/// 공유하는 원자 단위. rule-id 기반 catalog 를 최대한 구체적으로 채우고,
/// catalog 에 없는 rule 은 generic fallback 으로 형태만 맞춘다.
///
/// 설계 원칙 (사용자 지침 준수):
///   - 모든 text 는 한국어. 한자는 코드 주석에만.
///   - 추상적 표현 최소화. 실제 행동·갈등 상황으로 기술.
///   - 분석가 톤, 감성팔이 금지.
library;

import 'five_element.dart';
import 'organ_pair_rules.dart';
import 'palace.dart';
import 'yinyang_matcher.dart';
import 'zone_harmony.dart';

class CompatFinding {
  final String id; // rule id / pattern id / 'ELEMENT' / 'YINYANG'.
  final String title; // 보통 명사 제목, 한 줄.
  final String domain; // "결혼·가족", "돈", "대화", "자녀·친밀" 같은 도메인 한 단어.
  final double delta; // 엔진 delta (부호와 크기).
  final String meaning; // 이 자리가 실생활 어떤 영역을 보는지.
  final String observation; // 이 관상 조합에서 실제로 나타나는 모습.
  final String strength; // 장점 한 줄.
  final String caution; // 주의할 점 한 줄.
  final String? scenario; // 구체적 갈등 시나리오 (delta < 0 일 때만 채움).
  final String? action; // 실제 행동 지침 (운영 전략 섹션에 쓰임).

  const CompatFinding({
    required this.id,
    required this.title,
    required this.domain,
    required this.delta,
    required this.meaning,
    required this.observation,
    required this.strength,
    required this.caution,
    this.scenario,
    this.action,
  });

  /// 우선순위 = |delta| × 도메인 가중치. "핵심 궁합 3가지" 뽑을 때 쓴다.
  double get priority {
    final w = _domainWeight[domain] ?? 1.0;
    return delta.abs() * w;
  }

  // ─────────────── palace evidence → finding ───────────────
  factory CompatFinding.fromPalace(PalacePairEvidence e) {
    final tpl = _palaceTemplate[e.ruleId];
    if (tpl != null) {
      return CompatFinding(
        id: e.ruleId,
        title: tpl.title,
        domain: tpl.domain,
        delta: e.delta,
        meaning: tpl.meaning,
        observation: e.verdict,
        strength: tpl.strength,
        caution: tpl.caution,
        scenario: e.delta < 0 ? tpl.scenario : null,
        action: tpl.action,
      );
    }
    // fallback.
    final dom = _palaceDomain[e.palace] ?? '생활 전반';
    final title = '${e.palace.korean} 궁합 (${e.palace.domainKo})';
    final positive = e.delta >= 0;
    return CompatFinding(
      id: e.ruleId,
      title: title,
      domain: dom,
      delta: e.delta,
      meaning: '${e.palace.korean}은 ${e.palace.domainKo}을 보는 자리입니다.',
      observation: e.verdict,
      strength: positive
          ? '두 분의 ${e.palace.domainKo}에 관련된 운이 함께 올라가 주는 모양입니다.'
          : '같은 약점끼리 만났지만, 서로 이해하는 속도가 빠르다는 의미도 됩니다.',
      caution: positive
          ? '비슷한 강점끼리 만나 자만하기 쉬우니 기본기를 놓치지 마세요.'
          : '${e.palace.domainKo} 문제가 터지면 두 분 모두 힘들어지니 미리 대비가 필요합니다.',
      scenario: positive
          ? null
          : '${e.palace.domainKo} 쪽에서 문제가 생기면 한쪽이 다른 쪽을 받쳐 주기 어려워 이슈가 길게 끌릴 수 있습니다.',
      action: positive
          ? '${e.palace.domainKo}에서 오는 이점을 당연하게 여기지 말고, 서로에게 말로 자주 인정해 주세요.'
          : '${e.palace.domainKo} 영역에 미리 룰을 정해 두고, 한쪽이 흔들릴 때 다른 쪽이 지원하는 구조를 짜 두세요.',
    );
  }

  // ─────────────── organ evidence → finding ───────────────
  factory CompatFinding.fromOrgan(OrganPairEvidence e) {
    final tpl = _organTemplate[e.ruleId];
    if (tpl != null) {
      return CompatFinding(
        id: e.ruleId,
        title: tpl.title,
        domain: tpl.domain,
        delta: e.delta,
        meaning: tpl.meaning,
        observation: e.verdict,
        strength: tpl.strength,
        caution: tpl.caution,
        scenario: e.delta < 0 ? tpl.scenario : null,
        action: tpl.action,
      );
    }
    final partKo = e.organ.korean;
    final positive = e.delta >= 0;
    return CompatFinding(
      id: e.ruleId,
      title: '$partKo 모양의 궁합',
      domain: '성향·대화',
      delta: e.delta,
      meaning: '$partKo 모양은 두 분의 성격과 표현 방식이 잘 맞는지를 보는 자리입니다.',
      observation: e.verdict,
      strength: positive
          ? '평소 대화와 표현의 결이 잘 맞아 편안한 조합입니다.'
          : '같은 약점이라 서로를 빠르게 이해할 수는 있습니다.',
      caution: positive
          ? '편안함에 안주해 새로운 자극을 만들지 않으면 지루해질 수 있습니다.'
          : '표현 방식이 부딪히는 날이 잦아질 수 있으니 감정의 온도 조절이 필요합니다.',
      scenario: positive
          ? null
          : '$partKo 결이 엇갈려 사소한 말투 하나가 큰 오해로 번지는 날이 생길 수 있습니다.',
      action: positive
          ? '$partKo 결이 잘 맞는다는 점을 서로 자주 확인해 주면 관계가 더 탄탄해집니다.'
          : '감정이 상하는 상황에서는 바로 반응하지 말고 10분 뒤에 다시 이야기하는 규칙을 두세요.',
    );
  }

  // ─────────────── zone evidence → finding ───────────────
  factory CompatFinding.fromZone(ZonePatternEvidence e) {
    final tpl = _zoneTemplate[e.patternId];
    if (tpl != null) {
      return CompatFinding(
        id: e.patternId,
        title: tpl.title,
        domain: tpl.domain,
        delta: e.delta,
        meaning: tpl.meaning,
        observation: e.verdict,
        strength: tpl.strength,
        caution: tpl.caution,
        scenario: e.delta < 0 ? tpl.scenario : null,
        action: tpl.action,
      );
    }
    final positive = e.delta >= 0;
    return CompatFinding(
      id: e.patternId,
      title: '얼굴 상·중·하 구획의 어울림',
      domain: '성향·생활방식',
      delta: e.delta,
      meaning: '이마·중안·턱의 세 구획은 사고·의지·애정 영역이 얼마나 비슷하게 발달했는지를 보여 줍니다.',
      observation: e.verdict,
      strength: positive
          ? '두 분이 삶의 어느 영역에 힘을 쏟는지 방향이 비슷하게 맞춰집니다.'
          : '같은 부분이 약하다는 건 서로의 약점을 빠르게 이해할 수 있다는 뜻이기도 합니다.',
      caution: positive
          ? '강점이 겹쳐 결정권 다툼이 생길 수 있으니 영역을 미리 나누는 편이 좋습니다.'
          : '약점이 겹치면 외부에서 위기가 왔을 때 의지할 곳이 줄어드니 미리 보완책을 세워야 합니다.',
      scenario: positive
          ? null
          : '두 분 다 약한 영역에서 문제가 터지면 해결이 오래 걸리고 스트레스가 겹쳐 서로에게 날이 서기 쉽습니다.',
      action: positive
          ? '잘 맞는 영역은 당연한 일로 여기지 말고 서로 자주 칭찬해 주면 동기가 유지됩니다.'
          : '약한 영역은 외부 전문가나 가족의 도움을 받아 보완해 두는 편이 관계에 안전판이 됩니다.',
    );
  }

  // ─────────────── yinyang → finding ───────────────
  factory CompatFinding.fromYinYang(YinYangMatch m) {
    final tpl = _yinyangTemplate[m.kind]!;
    return CompatFinding(
      id: 'YY-${m.kind.name}',
      title: tpl.title,
      domain: tpl.domain,
      delta: m.delta,
      meaning: tpl.meaning,
      observation: tpl.observation!,
      strength: tpl.strength,
      caution: tpl.caution,
      scenario: m.delta < 0 ? tpl.scenario : null,
      action: tpl.action,
    );
  }

  // ─────────────── element relation → finding ───────────────
  factory CompatFinding.fromElement(
      FiveElements my, FiveElements album, ElementRelation rel) {
    final kind = rel.kind;
    final tpl = _elementTemplate[kind]!;
    final myK = my.primary.korean;
    final alK = album.primary.korean;
    String fill(String s) => s.replaceAll('{my}', myK).replaceAll('{album}', alK);

    // delta 근사: score - 50. 50 이면 중립.
    final delta = rel.score - 50.0;

    return CompatFinding(
      id: 'ELEMENT-${kind.name}',
      title: tpl.title,
      domain: tpl.domain,
      delta: delta,
      meaning: fill(tpl.meaning),
      observation: fill(tpl.observation!),
      strength: fill(tpl.strength),
      caution: fill(tpl.caution),
      scenario: (delta < 0 && tpl.scenario != null) ? fill(tpl.scenario!) : null,
      action: tpl.action == null ? null : fill(tpl.action!),
    );
  }
}

// ─────────────── 도메인 가중치 (결혼 맥락 기준) ───────────────

const Map<String, double> _domainWeight = {
  '결혼·부부생활': 1.8,
  '자녀·친밀': 1.5,
  '돈·경제': 1.3,
  '삶의 방향·결단': 1.3,
  '성향·대화': 1.1,
  '생활 기반': 1.1,
  '복·여유': 1.0,
  '건강': 0.8,
  '사회적 위치': 0.8,
  '인간관계': 0.8,
  '가족 관계': 0.8,
  '이동·변화': 0.6,
  '성향·생활방식': 1.0,
};

const Map<Palace, String> _palaceDomain = {
  Palace.life: '삶의 방향·결단',
  Palace.wealth: '돈·경제',
  Palace.sibling: '인간관계',
  Palace.property: '생활 기반',
  Palace.children: '자녀·친밀',
  Palace.slave: '인간관계',
  Palace.spouse: '결혼·부부생활',
  Palace.illness: '건강',
  Palace.migration: '이동·변화',
  Palace.career: '사회적 위치',
  Palace.fortune: '복·여유',
  Palace.parents: '가족 관계',
};

// ─────────────── 템플릿 구조 ───────────────

class _FindingTemplate {
  final String title;
  final String domain;
  final String meaning;
  final String? observation; // element/yinyang 쪽만 씀.
  final String strength;
  final String caution;
  final String? scenario;
  final String? action;
  const _FindingTemplate({
    required this.title,
    required this.domain,
    required this.meaning,
    this.observation,
    required this.strength,
    required this.caution,
    this.scenario,
    this.action,
  });
}

// ─────────────── palace rule 템플릿 ───────────────
//
// 자주 발동하고 비중 큰 rule 위주로 구체 채움. 미정의는 fallback 이 커버.

const Map<String, _FindingTemplate> _palaceTemplate = {
  'PP-SP-STRONG-SMOOTH': _FindingTemplate(
    title: '부부로서의 결속력',
    domain: '결혼·부부생활',
    meaning: '눈꼬리 옆쪽은 결혼 생활에서 상대를 얼마나 존중하고 금슬을 오래 유지할 수 있는지를 보는 자리입니다.',
    strength: '서로를 귀하게 여기는 태도가 몸에 배어 있어, 결혼하면 안정적인 반려 관계를 오래 유지합니다.',
    caution: '궁합이 좋은 구간일수록 방심하기 쉬우니, 기념일·연락·스킨십 같은 기본 관리는 꾸준히 해야 합니다.',
    action: '좋은 부부운을 당연시하지 말고, 매달 "이번 달에 고마웠던 일 세 가지" 정도는 말로 꺼내 두세요.',
  ),
  'PP-SP-STRONG-NOFLAG': _FindingTemplate(
    title: '결혼 중심의 삶',
    domain: '결혼·부부생활',
    meaning: '오래 가는 짝의 자리가 두 분 모두 단단하다는 건, 결혼 자체가 인생에서 큰 비중을 차지하게 된다는 뜻입니다.',
    strength: '연애보다 결혼 쪽에 더 잘 맞는 두 사람이라, 정식 관계로 들어갔을 때 안정성이 높습니다.',
    caution: '결혼을 인생의 중심에 두는 성향이 겹쳐, 한쪽이 일이나 취미 쪽에 치우치면 실망이 큽니다.',
    action: '서로의 연간 계획을 공유하고, 결혼 생활 외 영역에 쏟는 시간을 미리 합의해 두세요.',
  ),
  'PP-SP-CROSS': _FindingTemplate(
    title: '부부로서의 결속력',
    domain: '결혼·부부생활',
    meaning: '오래 가는 짝의 자리 강도가 한쪽이 강하고 한쪽이 약하면, 관계에 대한 기대치 차이가 큽니다.',
    strength: '강한 쪽이 약한 쪽을 품어 주면 오히려 균형이 잡혀 차분히 안착하는 모양입니다.',
    caution: '강한 쪽이 상대의 소극성을 불만으로 쌓아 두면, 어느 순간 결혼 유지 여부 자체를 문제 삼게 됩니다.',
    action: '관계 온도 차이를 숫자(예: 1~10점)로 주기적으로 공유하고, 크게 벌어지면 바로 대화로 풀어 주세요.',
  ),
  'PP-SP-WEAK-WRINKLE': _FindingTemplate(
    title: '부부로서의 결속력',
    domain: '결혼·부부생활',
    meaning: '두 분 모두 눈꼬리 옆이 약한 데다 눈꼬리 주름이 겹친 건, 부부로서의 감정 기복이 크다는 신호입니다.',
    strength: '약점을 공유하기 때문에 서로 공감은 빠른 편입니다.',
    caution: '잔주름처럼 쌓인 서운함이 폭발하면 이혼이나 별거 같은 극단 선택으로 가기 쉽습니다.',
    scenario: '한쪽이 연락을 며칠 소홀히 하거나 기념일을 놓치면, 다른 쪽이 "우리 끝인가"라는 극단적 해석으로 바로 넘어갑니다.',
    action: '격주 단위로 "서운했던 작은 일" 을 대놓고 꺼내 정리하는 시간을 마련해야, 감정 부채가 위험한 크기로 커지지 않습니다.',
  ),
  'PP-SP-WEAK-NOFLAG': _FindingTemplate(
    title: '부부로서의 결속력',
    domain: '결혼·부부생활',
    meaning: '오래 가는 짝의 자리가 양쪽 다 약한 건, 결혼이나 장기 관계에서 에너지가 쉽게 식는다는 뜻입니다.',
    strength: '서로에게 큰 기대가 없어, 기대와 현실의 격차로 상처받는 일은 적은 편입니다.',
    caution: '감정 표현이 부족해 "함께 사는 룸메이트"처럼 식어 버릴 위험이 있습니다.',
    scenario: '일이나 육아에 치여 하루 대화가 10분도 안 되는 날이 이어지면서, 어느 순간 서로의 근황조차 모르는 상태가 됩니다.',
    action: '정해진 시간에 무조건 하루 20분 얼굴 보고 대화하는 루틴을 만들어 두세요.',
  ),
  'PP-CH-STRONG-PLUMP': _FindingTemplate(
    title: '자녀운과 가까운 관계의 온기',
    domain: '자녀·친밀',
    meaning: '눈 아래 볼록한 부분(와잠)은 자녀, 연인, 가까운 사람을 향한 애정을 보는 자리입니다.',
    strength: '자녀를 향한 정성과 가까운 이를 돌보는 태도가 자연스럽게 두 분 모두에서 나옵니다.',
    caution: '애정이 풍부한 만큼, 한쪽이 다른 쪽의 애정 대상(자녀·부모)에 질투심을 느낄 수 있습니다.',
    action: '둘만의 시간과 가족 돌보는 시간을 달력에 구분해 기록해 두고, 어느 한쪽이 지나치게 쏠리지 않도록 관리하세요.',
  ),
  'PP-CH-WEAK-HOLLOW': _FindingTemplate(
    title: '자녀운과 친밀감의 깊이',
    domain: '자녀·친밀',
    meaning: '눈 아래가 얇거나 꺼진 건, 가까운 사람에게 정을 표현하는 일이 저절로 일어나지 않는다는 뜻입니다.',
    strength: '감정을 남발하지 않기 때문에, 한 번 한 말은 무겁게 받아들여지는 장점이 있습니다.',
    caution: '자녀나 가족에게 애정 표현이 부족해 오해가 누적되기 쉽습니다.',
    scenario: '자녀나 가까운 가족이 "내가 사랑받지 못했다"고 뒤늦게 털어놓는 순간, 두 분 모두 당황스러워하고 원인을 서로 탓하게 됩니다.',
    action: '하루 한 번 "고마워", "사랑해" 같은 직설적 표현을 억지로라도 하는 습관을 들이세요.',
  ),
  'PP-LF-BRIGHT-BOTH': _FindingTemplate(
    title: '삶의 방향과 결단력',
    domain: '삶의 방향·결단',
    meaning: '미간이 밝고 넓다는 건, 인생의 큰 결정을 스스로 밀고 나갈 기개가 있다는 의미입니다.',
    strength: '이사·이직·투자 같은 큰 결정을 두고 서로의 판단을 신뢰하고 빠르게 합의합니다.',
    caution: '둘 다 추진력이 강해, 급한 결정으로 들어가 주변 조언을 듣지 않을 위험이 있습니다.',
    action: '큰 결정 전에 "24시간 멈춤 규칙"을 두고, 가까운 제3자 한 명의 의견을 반드시 확인하세요.',
  ),
  'PP-LF-TIGHT-BOTH': _FindingTemplate(
    title: '속을 터놓는 대화',
    domain: '삶의 방향·결단',
    meaning: '미간이 좁고 어두운 건, 속에 쌓인 감정을 바깥으로 꺼내는 습관이 없다는 뜻입니다.',
    strength: '성급한 결정을 하지 않고 신중한 편입니다.',
    caution: '두 사람 모두 속을 잘 안 터놓아, 오해가 몇 달씩 묵히다 한꺼번에 폭발하기 쉽습니다.',
    scenario: '작은 서운함이 3~6개월간 쌓이다가 어느 날 사소한 말다툼을 계기로 "사실 그때부터…" 라며 묵은 감정이 한꺼번에 쏟아져 나오는 패턴이 반복됩니다.',
    action: '매주 정해진 요일에 20분 "이번 주에 마음에 걸린 일" 만 꺼내는 시간을 고정해 두세요.',
  ),
  'PP-LF-CROSS': _FindingTemplate(
    title: '결단 속도의 차이',
    domain: '삶의 방향·결단',
    meaning: '한 분은 결단이 빠르고 다른 분은 느린 구도는, 중요한 선택 앞에서 속도 차이가 갈등이 됩니다.',
    strength: '빠른 쪽이 방향을 제시하고 느린 쪽이 리스크를 점검해 주면 합리적인 결정이 나옵니다.',
    caution: '급한 쪽이 상대를 답답해하고, 신중한 쪽은 상대를 경솔하다고 느끼는 패턴이 반복됩니다.',
    scenario: '이사·이직·투자 같은 결정에서 한쪽은 "지금 하자", 다른 쪽은 "좀 더 보자"를 반복하다가 시간만 보내고 상대방에게 답답함이 쌓입니다.',
    action: '큰 결정 앞에서는 "검토 기간 X주" 를 숫자로 먼저 합의한 뒤 그 안에서 움직이는 규칙을 두세요.',
  ),
  'PP-WE-BULB-BOTH': _FindingTemplate(
    title: '재물 운영 궁합',
    domain: '돈·경제',
    meaning: '코끝이 복스럽게 솟아 있다는 건, 돈을 모으고 관리하는 감각이 살아 있다는 뜻입니다.',
    strength: '경제적 목표를 공유하기 쉽고, 돈 문제로 다투는 일이 적어 자산이 안정적으로 쌓입니다.',
    caution: '돈 모으는 데만 집중하다가 여가·관계에 쓸 돈을 아껴 삶이 건조해질 수 있습니다.',
    action: '연간 저축 목표와 함께 "즐기기 위한 예산"도 반드시 숫자로 합의해 두세요.',
  ),
  'PP-WE-HOOK-CLASH': _FindingTemplate(
    title: '돈 문제에서의 주도권 다툼',
    domain: '돈·경제',
    meaning: '두 분 모두 매부리 기운 있는 코라는 건, 이익 계산이 날카롭고 양보를 잘 안 한다는 신호입니다.',
    strength: '돈에 대한 감각이 모두 예민해, 큰 손실이 발생할 위험은 적습니다.',
    caution: '지출·투자·상속 같은 돈 결정 때마다 감정 싸움으로 번지기 쉽습니다.',
    scenario: '집 구매나 부모 지원 같은 큰 지출 앞에서, 서로의 손익을 따지다가 "넌 왜 네 쪽만 생각하느냐"는 말이 나와 며칠간 냉전이 이어집니다.',
    action: '공동 계좌와 개인 계좌 비율을 명확히 나누고, 일정 금액 이상의 지출은 사전 승인하는 규칙을 문서로 남기세요.',
  ),
  'PP-WE-THIN-BOTH': _FindingTemplate(
    title: '돈 문제에서의 예민함',
    domain: '돈·경제',
    meaning: '두 분 모두 콧대가 가늘다는 건, 돈 앞에서 예민하고 따지는 성향이 강하다는 뜻입니다.',
    strength: '작은 돈도 허투루 쓰지 않아 낭비는 적습니다.',
    caution: '사소한 지출을 두고도 감정이 상하기 쉽고, "돈을 누가 더 썼냐" 시비가 자주 납니다.',
    scenario: '외식 한 번, 배달 한 번을 두고도 "저번엔 내가 냈지" 식 계산이 시작되며, 작은 금액에서 정 떨어지는 경험이 반복됩니다.',
    action: '공동 지출 항목을 앱 한 개로 통합해 영수증 단위로 자동 정산하고, 1만원 이하 지출은 서로 따지지 않기로 규칙을 정하세요.',
  ),
  'PP-TH-STRONG': _FindingTemplate(
    title: '생활 기반 만들기',
    domain: '생활 기반',
    meaning: '눈과 눈썹 사이가 두텁다는 건, 집·부동산·가정의 안정에 대한 감각이 살아 있다는 뜻입니다.',
    strength: '집 마련·정착 시점을 비슷하게 설정하기 쉬워, 주거 문제로 다툴 일이 적습니다.',
    caution: '정착 성향이 강해, 새로운 기회를 놓치고 과하게 보수적으로 운영될 가능성이 있습니다.',
    action: '5년·10년 주기로 이사·리모델링 같은 변화 계획을 의식적으로 세워 두세요.',
  ),
  'PP-TH-WEAK': _FindingTemplate(
    title: '생활 기반의 취약성',
    domain: '생활 기반',
    meaning: '눈과 눈썹 사이가 얇다는 건, 주거·가정 기반이 불안정할 때 관계까지 흔들리기 쉽다는 신호입니다.',
    strength: '한 곳에 얽매이지 않아 환경 변화에 유연하게 대응할 수 있습니다.',
    caution: '주거·직장 이슈가 반복되면 관계의 긴장이 급격히 올라갑니다.',
    scenario: '월세 인상, 갑작스러운 이사, 직장 이동 같은 외부 충격이 있을 때 두 분 모두 안정감이 흔들려, 서로에게 짜증이 튀는 시기가 이어집니다.',
    action: '비상자금(최소 3개월 생활비)과 주거 계획(1~3년짜리)을 문서로 만들어 두세요.',
  ),
  'PP-FT-CLOUDLESS': _FindingTemplate(
    title: '일상의 여유',
    domain: '복·여유',
    meaning: '이마 위 좌우가 밝다는 건, 일상에서 여유를 느끼는 감각이 두 분 다 살아 있다는 뜻입니다.',
    strength: '여행·취미·친구 만남 같은 여유 영역이 관계를 건강하게 받쳐 줍니다.',
    caution: '여유를 당연시해 저축·자기계발 같은 노력을 소홀히 할 수 있습니다.',
    action: '"여유의 돈"과 "미래 투자의 돈"을 비율로 나눠 지출 계획을 세워 두세요.',
  ),
  'PP-FT-DENTED': _FindingTemplate(
    title: '일상의 여유 부족',
    domain: '복·여유',
    meaning: '이마 위가 꺼졌다는 건, 작은 일에도 여유가 빨리 닳는 성향이 겹쳤다는 뜻입니다.',
    strength: '절박함이 공유되면 목표 달성 속도가 빠른 편입니다.',
    caution: '여유가 없으니 짜증과 예민함이 관계에 자주 번집니다.',
    scenario: '야근이 이어지거나 양가 행사가 몰린 시기에, 두 분 다 지친 상태로 귀가해 사소한 것에도 폭발하는 날이 늘어납니다.',
    action: '일주일에 하루는 반드시 아무것도 하지 않는 "회복일"을 정해 두세요.',
  ),
  'PP-IL-SANGEN-LOW': _FindingTemplate(
    title: '건강 관리',
    domain: '건강',
    meaning: '콧대 뿌리(산근)가 꺼졌다는 건, 중년 이후 체력 저하가 관계에 영향을 주기 쉽다는 뜻입니다.',
    strength: '약점을 공유하므로 건강 관리에 공감대가 생기기 쉽습니다.',
    caution: '한쪽이 아프면 다른 쪽도 쉽게 지쳐, 간병 스트레스가 관계를 흔듭니다.',
    scenario: '40대 후반 이후 한쪽이 큰 병을 앓게 되면 돌봄 부담이 한 사람에게 쏠리면서 관계에 균열이 생기기 쉽습니다.',
    action: '40대부터는 매년 종합검진을 같이 받고, 보험·의료비 계획을 공동 자산처럼 관리하세요.',
  ),
  'PP-IL-SANGEN-HIGH': _FindingTemplate(
    title: '체력 기반의 안정성',
    domain: '건강',
    meaning: '콧대 뿌리가 높다는 건, 체력과 회복력이 좋아 노년기 활동성이 유지된다는 뜻입니다.',
    strength: '나이 들어도 함께 활동할 수 있어 관계의 활력이 오래 유지됩니다.',
    caution: '건강에 자신이 있다고 검진·생활습관 관리를 미루기 쉽습니다.',
    action: '기본 건강검진과 운동 루틴은 자신감 여부와 상관없이 일정에 고정해 두세요.',
  ),
};

// ─────────────── organ rule 템플릿 ───────────────

const Map<String, _FindingTemplate> _organTemplate = {
  'OP-BR-BOTH-THICK': _FindingTemplate(
    title: '주도권 다툼',
    domain: '성향·대화',
    meaning: '눈썹이 짙고 굵다는 건 자기 의지가 강하다는 신호인데, 이게 겹치면 주도권 다툼이 잦아집니다.',
    strength: '두 분 다 책임감이 강해, 일을 미루지 않고 밀어붙이는 힘이 있습니다.',
    caution: '의견이 엇갈리면 누가 먼저 양보할지 정해 두지 않아, 감정 싸움으로 번지기 쉽습니다.',
    scenario: '여행 코스·가구 선택·아이 교육 같은 일상 결정 앞에서 서로 자기 의견을 굽히지 않고, 결국 제3자가 끼어야 결정되는 일이 반복됩니다.',
    action: '영역별로 "결정권 가진 사람" 을 미리 정해 두세요 (예: 인테리어는 A, 재정은 B).',
  ),
  'OP-BR-THICK-THIN': _FindingTemplate(
    title: '리드와 서포트의 역할 분담',
    domain: '성향·대화',
    meaning: '한 쪽 눈썹이 짙고 다른 쪽이 가늘면, 이끄는 사람과 받쳐 주는 사람의 역할이 자연스럽게 나뉩니다.',
    strength: '결정권이 한쪽으로 모여 있어 의사결정 속도가 빠르고 갈등이 적습니다.',
    caution: '오랜 시간이 지나면 받쳐 주는 쪽이 "내 의견은 무시된다"고 느낄 수 있습니다.',
    action: '주요 결정 후에는 "너는 어떻게 생각해?" 한마디를 의식적으로 먼저 물으세요.',
  ),
  'OP-EY-FENG-TAOHUA': _FindingTemplate(
    title: '첫인상과 매력의 맞물림',
    domain: '성향·대화',
    meaning: '한 쪽은 단단한 눈, 다른 쪽은 매력적인 입술이라는 건, 이성적 판단과 감성적 끌림이 서로를 채우는 구도입니다.',
    strength: '서로의 약점을 정확히 메워 줘, 외부에서 봐도 잘 어울리는 커플로 보입니다.',
    caution: '한쪽이 판단, 한쪽이 매력으로 역할을 고정하면 지루해질 수 있습니다.',
    action: '가끔씩 역할을 바꿔 보세요 — 감성 쪽이 결정하고, 이성 쪽이 감정 표현을 주도하는 식으로.',
  ),
  'OP-EY-DROOPING-BOTH': _FindingTemplate(
    title: '일상의 활력',
    domain: '성향·대화',
    meaning: '두 분 모두 눈꼬리가 처져 있다는 건, 평소 에너지 레벨이 낮고 무기력에 쉽게 빠진다는 신호입니다.',
    strength: '서로에게 무리한 요구를 하지 않아 부담이 적습니다.',
    caution: '활력을 만드는 역할이 아무에게도 없어, 관계가 지루해지고 매너리즘에 빠지기 쉽습니다.',
    scenario: '주말마다 "뭐 할까?" 물어봐도 둘 다 "글쎄" 로 끝나면서, 각자 핸드폰만 보다가 하루가 끝나는 패턴이 굳어집니다.',
    action: '둘 중 한 명이 "이번 달 담당" 으로 돌아가며 외부 활동을 기획하는 규칙을 만들어 두세요.',
  ),
  'OP-EY-SHARP-SOFT': _FindingTemplate(
    title: '날카로움과 부드러움의 조합',
    domain: '성향·대화',
    meaning: '한 쪽은 날카로운 눈, 다른 쪽은 부드러운 눈이라는 건, 결정과 위로 역할이 자연스럽게 나뉜다는 뜻입니다.',
    strength: '외부 문제는 날카로운 쪽이, 감정 문제는 부드러운 쪽이 해결해 역할 분담이 깔끔합니다.',
    caution: '날카로운 쪽이 부드러운 쪽을 "너무 물렁하다"고 평가절하하면 관계가 금이 갑니다.',
    action: '서로의 역할을 약점이 아니라 강점으로 명확히 언어화해 두세요.',
  ),
  'OP-NS-BOTH-AQUILINE': _FindingTemplate(
    title: '자존심과 이익 계산',
    domain: '돈·경제',
    meaning: '두 분 모두 매부리 기운 있는 코라는 건, 자존심이 세고 손해 보기 싫어하는 성향이 겹친다는 뜻입니다.',
    strength: '각자 경제적 자립성이 강해 돈 때문에 의지하는 일은 적습니다.',
    caution: '이익이 걸린 결정 앞에서 서로 양보를 안 해 감정싸움이 오래갑니다.',
    scenario: '상속·자녀 교육비 분담·공동 투자 같은 사안에서, 서로의 몫을 따지다가 "너는 이기적이야" 라는 말이 오가고 며칠간 냉전이 이어집니다.',
    action: '큰 금액 결정은 제3자(회계사·가족 어른)에게 기준 의견을 받아와 객관적 숫자로 합의하세요.',
  ),
  'OP-NS-AQUI-SNUB': _FindingTemplate(
    title: '야심과 애교의 조합',
    domain: '성향·대화',
    meaning: '한 분은 매부리, 다른 분은 들창 느낌의 코라는 건, 야망 있는 쪽과 애교 있는 쪽이 짝이 된 구도입니다.',
    strength: '긴장과 이완이 번갈아 오며 관계에 리듬이 생깁니다.',
    caution: '야심 있는 쪽이 일에 빠지면 상대는 방치된 느낌을 받기 쉽습니다.',
    action: '바쁜 시기에도 "짧지만 자주" 원칙으로 연락과 스킨십을 유지하세요.',
  ),
  'OP-NS-GARLIC-BOTH': _FindingTemplate(
    title: '알뜰한 재물 운영',
    domain: '돈·경제',
    meaning: '콧방울이 풍성하다는 건 돈을 쌓는 끈기가 있다는 뜻이고, 이게 겹치면 저축·투자 감각이 같이 좋습니다.',
    strength: '경제적 목표를 비슷하게 설정해, 자산 형성 속도가 빠릅니다.',
    caution: '아끼는 데 집중해 삶의 재미를 놓치기 쉽습니다.',
    action: '월 수입의 일정 비율(예: 10%)은 반드시 즐기는 데 쓰도록 "즐거움 예산" 을 고정해 두세요.',
  ),
  'OP-NS-THIN-BOTH': _FindingTemplate(
    title: '돈 문제에서의 예민함',
    domain: '돈·경제',
    meaning: '두 분 모두 콧대가 칼처럼 가늘다는 건, 돈 계산이 정확하고 예민하다는 뜻입니다.',
    strength: '낭비가 거의 없고 계획성 있는 소비 패턴이 자리잡습니다.',
    caution: '"1만원도 따지는" 성향이 겹쳐, 사소한 금액으로 다툼이 반복됩니다.',
    scenario: '생활비 분담이나 각자 사용한 배달앱 금액을 두고도 서로 장부 대듯 따지다가, "이렇게까지 따져야 하냐"는 말이 나옵니다.',
    action: '소액 지출은 모두 공동 카드 하나로 몰아 자동 정산하고, 1만원 이하는 따지지 않는 규칙을 합의하세요.',
  ),
  'OP-MO-BOTH-FULL': _FindingTemplate(
    title: '대화와 감각의 맞물림',
    domain: '성향·대화',
    meaning: '입술이 도톰하다는 건 감각과 표현이 풍부하다는 뜻이고, 이게 겹치면 대화가 메마르지 않습니다.',
    strength: '평소 말·스킨십·애정 표현이 자연스러워 관계의 온도가 높게 유지됩니다.',
    caution: '말의 온도에 의존하다 보면 행동의 일관성을 놓치기 쉽습니다.',
    action: '말로 한 약속은 반드시 행동으로 확인하는 루틴을 만들어 두세요.',
  ),
  'OP-MO-BIG-SMALL': _FindingTemplate(
    title: '말하는 쪽과 듣는 쪽',
    domain: '성향·대화',
    meaning: '입 크기가 다르다는 건, 말의 양이 자연스럽게 나뉜다는 뜻입니다.',
    strength: '말하는 쪽과 듣는 쪽의 역할이 맞물려 대화가 일방적으로 끊기지 않습니다.',
    caution: '듣는 쪽이 오래 쌓이면 "내 얘기는 안 궁금하냐"고 터지기 쉽습니다.',
    action: '말이 많은 쪽이 의식적으로 "네 생각은?" 으로 질문의 턴을 넘기세요.',
  ),
  'OP-MO-WIDE-SMILE': _FindingTemplate(
    title: '일상의 행복 지수',
    domain: '성향·대화',
    meaning: '입꼬리가 올라가 웃음기가 잘 맺힌다는 건, 평소 기본 정서가 밝다는 신호입니다.',
    strength: '사소한 일상에서 웃을 일을 잘 찾아, 관계의 체감 행복도가 높습니다.',
    caution: '밝은 표정에 익숙해져, 힘든 감정을 내색하지 못하고 혼자 삭이는 경향이 있습니다.',
    action: '"오늘 힘들었던 일" 을 일부러 꺼내는 시간을 주 1회 만들어 두세요.',
  ),
  'OP-MO-CORNER-DOWN': _FindingTemplate(
    title: '침묵으로 굳어지는 관계',
    domain: '성향·대화',
    meaning: '입꼬리가 내려갔다는 건, 감정을 말로 표현하는 일이 자연스럽지 않다는 뜻입니다.',
    strength: '감정 표현을 아껴 불필요한 말다툼이 적습니다.',
    caution: '침묵이 벽이 되어 오해가 누적되기 쉽습니다.',
    scenario: '한쪽이 기분 나쁜 일이 있어도 말하지 않으면, 다른 쪽은 이유를 모른 채 같이 말을 안 하게 되고, 며칠간 집안이 무겁게 흐르는 패턴이 반복됩니다.',
    action: '말로 꺼내기 어려우면 메모나 문자로라도 매일 "오늘 기분 상태" 한 줄을 공유하는 규칙을 만드세요.',
  ),
  'OP-MO-CHERRY-SMALL': _FindingTemplate(
    title: '표현의 위축',
    domain: '성향·대화',
    meaning: '입이 작고 얇다는 건 감정과 의견 표현에 소극적이라는 뜻이고, 이게 겹치면 서로의 속을 알기 어렵습니다.',
    strength: '조용하고 차분한 분위기의 집안 분위기가 자리잡기 쉽습니다.',
    caution: '표현이 부족해 상대가 원하는 걸 계속 놓치고, "눈치껏 해 주길" 바라다 지쳐 버립니다.',
    scenario: '기념일·생일 같은 이벤트에서 원하는 걸 말하지 않은 채 상대가 해 주기만 기다리다가, 기대가 어긋나 실망이 쌓이는 패턴이 반복됩니다.',
    action: '원하는 것과 싫은 것을 말할 때는 "나는 ~를 원해/싫어" 식의 직설 표현을 쓰기로 규칙을 정하세요.',
  ),
};

// ─────────────── zone pattern 템플릿 ───────────────

const Map<String, _FindingTemplate> _zoneTemplate = {
  'ZP-UP-BOTH-STRONG': _FindingTemplate(
    title: '사상과 가치관의 공명',
    domain: '성향·생활방식',
    meaning: '이마가 두 분 다 발달했다는 건, 생각·배움·가치관을 중시하는 성향이 겹친다는 뜻입니다.',
    strength: '책·뉴스·관심 분야에 대한 대화가 끊이지 않고, 서로에게 지적 자극이 됩니다.',
    caution: '머리로만 관계를 이해하려 해 감정·일상 돌봄이 소홀해질 수 있습니다.',
    action: '지적 대화만큼 "같이 밥 짓기·청소하기" 같은 일상 돌봄 루틴도 의식적으로 만들어 두세요.',
  ),
  'ZP-UP-BOTH-WEAK': _FindingTemplate(
    title: '큰 그림 그리기의 부담',
    domain: '성향·생활방식',
    meaning: '이마가 두 분 다 얇다는 건, 장기 계획·비전 수립이 자연스럽지 않다는 뜻입니다.',
    strength: '현재에 충실해, 일상의 만족도는 높은 편입니다.',
    caution: '5년·10년 단위 계획이 없어, 외부 변화에 휘둘리기 쉽습니다.',
    scenario: '자녀 교육비, 노후 자금, 이사 계획 같은 중장기 이슈가 닥쳤을 때 준비가 안 돼 있어 관계 전체가 흔들립니다.',
    action: '연초마다 "3년 계획 문서" 한 장을 같이 작성해 두세요.',
  ),
  'ZP-MID-BOTH-STRONG': _FindingTemplate(
    title: '추진력의 충돌',
    domain: '성향·생활방식',
    meaning: '얼굴 중간(광대·코)이 두 분 다 강하다는 건, 둘 다 추진력이 강해 주도권 다툼이 일어난다는 뜻입니다.',
    strength: '둘 다 일을 잘 밀어붙여, 경제적 성취가 빠릅니다.',
    caution: '결정권을 놓고 부딪히면서, 집안·일에서 감정 마찰이 반복됩니다.',
    scenario: '집안 리모델링·투자·이직처럼 큰 결정 때마다 서로 "내가 더 맞다" 를 주장하다가, 결국 양쪽 다 기분만 상하고 결정은 미뤄지는 패턴이 반복됩니다.',
    action: '영역별 결정권을 미리 나누어 문서화하세요 — "주거는 A, 투자는 B" 식으로.',
  ),
  'ZP-MID-ONE-STRONG': _FindingTemplate(
    title: '실행의 축',
    domain: '성향·생활방식',
    meaning: '한 쪽이 중간 얼굴이 강하다는 건, 그 쪽이 실행의 축을 맡는다는 뜻입니다.',
    strength: '일 추진 속도가 빠르고, 누가 뭘 해야 할지 역할이 헷갈리지 않습니다.',
    caution: '실행 축을 맡은 쪽에 부담이 몰리면 번아웃이 올 수 있습니다.',
    action: '분기마다 "부담이 쏠린 쪽" 이 누구인지 서로 체크하고, 작업을 재분배하세요.',
  ),
  'ZP-LO-BOTH-STRONG': _FindingTemplate(
    title: '정과 애정의 깊이',
    domain: '자녀·친밀',
    meaning: '턱이 두 분 다 두텁다는 건, 가족·자녀·가까운 이에 대한 정이 깊다는 뜻입니다.',
    strength: '가정의 온기가 저절로 만들어져, 아이나 가까운 가족이 안정감을 크게 느낍니다.',
    caution: '가족에게 쏟는 에너지가 많아, 부부 둘만의 시간은 점점 줄어들 수 있습니다.',
    action: '가족 시간과 부부 시간을 달력에서 분리해 기록해 두세요.',
  ),
  'ZP-LO-BOTH-WEAK': _FindingTemplate(
    title: '애정 표현의 취약성',
    domain: '자녀·친밀',
    meaning: '턱이 두 분 다 얇다는 건, 애정을 표현하고 받는 일에 둘 다 서투르다는 뜻입니다.',
    strength: '감정 과잉이 없어 관계가 차분한 편입니다.',
    caution: '가족이나 자녀에게 "정이 없다" 는 오해를 주기 쉽습니다.',
    scenario: '자녀가 커서 "부모님이 나를 사랑하긴 했냐" 고 묻는 순간, 두 분이 당황스럽게 서로를 바라보는 상황이 생깁니다.',
    action: '하루 한 번 직설적 애정 표현 ("사랑해", "고마워") 을 루틴으로 고정하세요.',
  ),
  'ZP-XC-UP-DOWN': _FindingTemplate(
    title: '이상과 현실의 맞물림',
    domain: '성향·생활방식',
    meaning: '한 쪽은 이마, 다른 쪽은 턱이 강하다는 건, 한 사람은 이상을 그리고 다른 사람은 현실을 챙기는 구도입니다.',
    strength: '큰 그림과 살림 감각이 맞물려, 계획과 실행이 모두 살아납니다.',
    caution: '이상 쪽이 현실 쪽을 무시하거나, 현실 쪽이 이상 쪽을 "공상가" 로 치부하면 관계가 깨집니다.',
    action: '서로의 강점을 명확히 언어화하고, 상대 역할을 비웃지 않기로 합의해 두세요.',
  ),
  'ZP-MIRROR-ALL': _FindingTemplate(
    title: '닮은 결끼리의 관계',
    domain: '성향·생활방식',
    meaning: '얼굴의 세 구획이 모두 닮았다는 건, 사고·의지·애정의 결이 거의 동일하다는 뜻입니다.',
    strength: '의사소통 속도가 빠르고, "말 안 해도 통한다" 는 느낌을 자주 받습니다.',
    caution: '비슷한 만큼 자극이 줄어, 시간이 지나면 권태가 빠르게 찾아옵니다.',
    action: '둘 다 안 해 본 활동(새로운 운동·취미·여행지)을 분기마다 하나씩 시도해 보세요.',
  ),
  'ZP-COMPLEMENT-ALL': _FindingTemplate(
    title: '정반대 결의 상호보완',
    domain: '성향·생활방식',
    meaning: '세 구획이 모두 반대라는 건, 서로의 강점·약점이 정확히 뒤바뀐 구도라는 뜻입니다.',
    strength: '한 사람이 약한 영역을 다른 사람이 완벽히 커버해, 팀으로서의 완성도가 높습니다.',
    caution: '차이가 커서 초반에는 충돌이 잦고, 서로를 이해하는 데 시간이 많이 듭니다.',
    scenario: '성격·습관 차이가 초반에 "이 사람과는 안 맞는 것 같다"는 의심으로 번져, 관계 정착까지 1~2년이 걸릴 수 있습니다.',
    action: '초반 갈등 기간을 "적응 단계" 로 명시적으로 받아들이고, 결혼이나 동거 결정은 서두르지 마세요.',
  ),
};

// ─────────────── yinyang 템플릿 ───────────────

const Map<YinYangPatternKind, _FindingTemplate> _yinyangTemplate = {
  YinYangPatternKind.yangYinIdeal: _FindingTemplate(
    title: '음양의 이상적 조합',
    domain: '성향·대화',
    meaning: '한 분은 추진하는 양의 성향, 다른 분은 받아 주는 음의 성향이라는 뜻입니다. 분석상 가장 안정적인 짝입니다.',
    observation: '추진하는 쪽이 방향을 제시하고 받아 주는 쪽이 흡수하는 구도라, 큰 마찰 없이 결정이 흘러갑니다.',
    strength: '의사결정 속도가 빠르면서도 관계가 거칠어지지 않습니다.',
    caution: '역할이 고착되면 받아 주는 쪽이 답답함을 쌓아 두기 쉽습니다.',
    action: '반기에 한 번 정도 "역할을 바꿔서" 생활해 보는 실험을 해 보세요.',
  ),
  YinYangPatternKind.yangYang: _FindingTemplate(
    title: '강 대 강의 충돌',
    domain: '성향·대화',
    meaning: '두 분 모두 추진형 양의 성향이라, 같은 자리를 놓고 다투기 쉽다는 뜻입니다.',
    observation: '의견이 엇갈리면 둘 다 물러서지 않아 갈등이 길어지고, 집안 분위기가 자주 팽팽해집니다.',
    strength: '둘 다 에너지가 강해, 목표를 향해 빠르게 움직이는 추진력은 최고 수준입니다.',
    caution: '주도권 다툼이 일상적으로 발생해, 감정 피로가 빠르게 쌓입니다.',
    scenario: '여행지 선택·자녀 교육 방향·집안 인테리어까지, 크고 작은 선택마다 서로 양보를 안 해 매번 소규모 냉전이 반복됩니다.',
    action: '영역별 결정권자를 문서화하고, 갈등 시 3-3-3 규칙(3분 말하고 3분 듣고 3분 쉬기)을 적용하세요.',
  ),
  YinYangPatternKind.yinYin: _FindingTemplate(
    title: '둘 다 수용형의 늘어짐',
    domain: '성향·대화',
    meaning: '두 분 모두 받아 주는 음의 성향이라, 먼저 나서는 사람이 없어 관계가 정체되기 쉽다는 뜻입니다.',
    observation: '무슨 일이든 "너가 결정해" 가 돌아오는 패턴이 반복되면서, 결정이 미뤄지고 일상이 느슨해집니다.',
    strength: '서로를 배려하는 태도가 자연스러워 큰 다툼은 적습니다.',
    caution: '추진력 부족으로 기회를 놓치고, 관계가 지루해지기 쉽습니다.',
    scenario: '이사·이직·결혼 준비 같은 큰 결정을 앞두고 서로 "네가 원하는 대로 해" 만 반복하다가, 시간만 흐르고 주변에서 안타까워하는 상황이 자주 생깁니다.',
    action: '격주 단위로 "이번 주 결정 담당" 을 정해 두고, 그 주는 그 사람이 무조건 리드하는 규칙을 만드세요.',
  ),
  YinYangPatternKind.balancedBoth: _FindingTemplate(
    title: '중용의 조합',
    domain: '성향·대화',
    meaning: '두 분 모두 양이나 음으로 치우치지 않았다는 뜻입니다. 일상이 평화롭게 흘러갑니다.',
    observation: '큰 갈등도, 큰 자극도 없이 잔잔한 일상이 이어집니다.',
    strength: '관계가 안정적이고 예측 가능해, 주변 어른이나 친구들에게도 편안한 커플로 보입니다.',
    caution: '자극이 부족해 관계가 지루해지고, 감정의 진폭이 좁아집니다.',
    action: '분기에 한 번씩 "약간 모험적인 활동" 을 일부러 기획해 보세요 — 여행지 하나, 새 취미 하나.',
  ),
  YinYangPatternKind.oneBalanced: _FindingTemplate(
    title: '중심 잡아 주기',
    domain: '성향·대화',
    meaning: '한 분은 균형 잡힌 상태, 다른 분은 한쪽으로 살짝 기운 구도라, 중심 잡힌 쪽이 완충 역할을 하는 모양입니다.',
    observation: '기운 쪽이 감정이 요동칠 때, 중심 쪽이 조용히 잡아 주는 흐름이 자연스럽게 생깁니다.',
    strength: '한쪽이 흔들려도 다른 쪽이 안정감을 제공해, 관계가 크게 무너지지 않습니다.',
    caution: '중심 쪽이 완충 역할에 지쳐 "나는 누가 받쳐 주냐" 고 느낄 수 있습니다.',
    action: '중심 쪽도 주기적으로 감정 환기가 필요합니다 — 혼자 시간, 친구와의 시간을 주저 없이 가질 수 있게 지원해 주세요.',
  ),
  YinYangPatternKind.modernCross: _FindingTemplate(
    title: '전통 역할과 다른 구도',
    domain: '성향·대화',
    meaning: '성별 기대와 음양이 반대라는 뜻입니다. 여성 쪽이 추진형, 남성 쪽이 수용형 같은 식입니다.',
    observation: '집안일·의사결정·경제 활동 같은 전통적 역할 분담이 그대로 들어맞지 않고, 두 분이 직접 새로 정의하게 됩니다.',
    strength: '고정 역할에서 자유로워, 서로의 재능에 맞게 최적화된 역할 분담이 가능합니다.',
    caution: '양가 부모나 주변 사람과 기대 충돌이 생기기 쉽습니다.',
    scenario: '양가 행사·육아·경제 활동 분담 같은 이슈에서, 양쪽 부모의 전통적 기대와 부딪혀 스트레스가 관계로 튀는 날이 반복됩니다.',
    action: '양가에 "우리는 이렇게 살겠다" 는 역할 분담을 일찍 분명히 선언해 두세요.',
  ),
};

// ─────────────── 오행 관계 템플릿 ───────────────

const Map<ElementRelationKind, _FindingTemplate> _elementTemplate = {
  ElementRelationKind.generating: _FindingTemplate(
    title: '내가 상대를 북돋우는 관계',
    domain: '성향·대화',
    meaning: '내 쪽 얼굴형({my})이 상대 얼굴형({album})을 살려 주는 구도입니다. 베푸는 쪽이 나라는 뜻입니다.',
    observation: '일상에서 내가 먼저 챙기고 먼저 제안하는 흐름이 자연스럽게 만들어집니다.',
    strength: '상대가 내 옆에서 편안해하고 성장이 빠릅니다.',
    caution: '베푸는 쪽이 지치지 않도록, 상대의 감사와 반응이 중요합니다.',
    action: '베푸는 쪽이 "고맙다" 는 말을 정기적으로 들을 수 있도록, 상대에게 감사 표현을 의식적으로 요구해도 괜찮습니다.',
  ),
  ElementRelationKind.generated: _FindingTemplate(
    title: '상대가 나를 받쳐 주는 관계',
    domain: '성향·대화',
    meaning: '상대 얼굴형({album})이 내 얼굴형({my})을 살려 주는 구도입니다. 기대면 뿌리가 깊어지는 방향입니다.',
    observation: '큰 결정, 위기 상황에서 상대가 먼저 방향을 제시하고 내가 따라가는 흐름이 반복됩니다.',
    strength: '나 혼자 무리하지 않아도 되니 안정감이 큽니다.',
    caution: '지나치게 의존하면 상대가 지쳐, 관계가 기울어집니다.',
    action: '받는 쪽이 주기적으로 먼저 챙기는 이벤트(식사·여행·선물)를 기획해 균형을 맞춰 주세요.',
  ),
  ElementRelationKind.overcoming: _FindingTemplate(
    title: '내가 상대를 누르는 관계',
    domain: '성향·대화',
    meaning: '내 쪽 얼굴형({my})이 상대 얼굴형({album})을 억누르는 구도입니다. 힘으로 지배할 위험이 있는 방향입니다.',
    observation: '평소 내가 결정을 밀어붙이고 상대가 맞춰 주는 패턴이 굳어져 있습니다.',
    strength: '의사결정 속도는 빠르고 방향은 명확합니다.',
    caution: '누르는 쪽이 반복되면 상대가 위축되어 소통이 단절됩니다.',
    scenario: '내가 무심코 던진 한 마디에 상대가 눈에 띄게 조용해지면서 며칠간 거리감이 생기는 일이 반복됩니다.',
    action: '결정을 밀어붙이기 전에 "너는 어떻게 생각해?" 를 먼저 묻고, 상대의 답을 반드시 듣는 규칙을 만드세요.',
  ),
  ElementRelationKind.overcome: _FindingTemplate(
    title: '상대가 나를 누르는 관계',
    domain: '성향·대화',
    meaning: '상대 얼굴형({album})이 내 얼굴형({my})을 억누르는 구도입니다. 내가 위축될 수 있는 방향입니다.',
    observation: '중요한 결정 앞에서 상대의 의견이 먼저 나오고 내 의견은 뒤로 밀리는 일이 반복됩니다.',
    strength: '상대가 주도하니 내가 실수할 일은 적습니다.',
    caution: '내 의견을 꺼내지 않는 일이 굳어지면, 어느 순간 "나는 왜 여기 있냐"는 허탈감이 옵니다.',
    scenario: '사소한 메뉴 선택에서조차 상대 의견을 따르는 일이 몇 달간 쌓이면서, 내가 정말 원하는 게 뭔지조차 흐려지는 상황이 생깁니다.',
    action: '내 의견을 말할 수 있는 "안전한 대화 시간" 을 주 1회 고정하고, 그 시간엔 상대가 반박 없이 들어 주기로 약속하세요.',
  ),
  ElementRelationKind.identity: _FindingTemplate(
    title: '닮은 결끼리의 공명',
    domain: '성향·대화',
    meaning: '두 분 얼굴형({my})이 같다는 건, 성향·반응 속도·취향이 매우 비슷하다는 뜻입니다.',
    observation: '말하지 않아도 통하는 순간이 많고, 취향이 자연스럽게 겹칩니다.',
    strength: '의사소통 비용이 낮고, 같이 있을 때 편안합니다.',
    caution: '비슷한 만큼 자극이 부족해 권태가 빠르게 찾아옵니다.',
    action: '일부러 서로 다른 영역의 취미나 친구 모임을 갖고, 그 경험을 서로에게 공유하는 습관을 들이세요.',
  ),
};
