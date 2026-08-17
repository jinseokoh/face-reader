part of 'compat_finding.dart';

// ═══════════════════════════════════════════════════════════════════════
// finding 텍스트의 v2 짝.
//
// finding 은 §2·§3·§4 세 섹션이 공유하는 데이터층이다. 템플릿 6개 1,240줄을
// 통째로 복제하면 오타 하나를 한쪽만 고치는 사고가 나므로, 여기서는 **v1 과
// 실제로 달라야 하는 항목만** 덮어쓴다. 섹션 단위 짝은 이미
// `buildCompatNarrative` 의 version switch 가 강제하고 있다.
//
// 덮어쓰는 기준은 하나 — v2 톤 규칙을 어기는 문장이다.
//   미래의 특정 장면을 단정하는 문장
//   측정으로 알 수 없는 일을 측정처럼 말하는 문장
//
// 전수 스캔 결과 걸린 것은 세 항목이다. 나머지 finding 은 "눈꼬리 바깥
// (배우자 자리)은 …를 보는 자리입니다" 처럼 이미 전통의 자리 개념을 근거로
// 삼고 있어 v2 톤과 어긋나지 않는다.
// ═══════════════════════════════════════════════════════════════════════

/// 덮어쓸 필드만 담는다. null 이면 v1 값을 그대로 쓴다.
/// 실제로 덮어쓰는 필드만 둔다 — 쓰지 않는 필드를 미리 열어 두면 죽은 코드다.
class _FindingV2Override {
  final String? meaning;
  final String? observation;
  final String? caution;
  final String? scenario;

  const _FindingV2Override({
    this.meaning,
    this.observation,
    this.caution,
    this.scenario,
  });
}

const Map<String, _FindingV2Override> _findingV2Overrides = {
  // v1 은 "자녀가 뒤늦게 털어놓는 순간" 이라는 특정 미래 장면을 단정했다.
  // 사진 두 장으로 알 수 없는 일이다. 조건형으로 바꾸고 주어를 전통에 넘긴다.
  'PP-CH-WEAK-HOLLOW': _FindingV2Override(
    caution: '자녀·가족에게 애정 표현이 부족해 오해가 누적되기 쉽습니다. '
        '전통 관상은 이 자리를 남녀궁이라 하여 아랫사람과의 정이 드나드는 곳으로 보았어요. '
        '표현 부족이 사랑의 부족으로 오해받는 것이 이 자리에서 가장 아까운 일입니다.',
    scenario: '두 분 다 표현이 적은 구성이라, 마음은 있는데 전달이 안 되는 구간이 생기기 쉽습니다. '
        '사랑이 없었던 게 아니라 표현이 없었을 뿐인데, 받는 쪽은 그 둘을 구분하기 어렵습니다. '
        '한 번 굳어진 인식을 되돌리는 데는 처음보다 몇 배의 품이 듭니다.',
  ),
  // v1 은 "며칠간 냉전이 이어지고" 로 시작해 사건의 전개를 확정했다.
  'PP-WE-HOOK-CLASH': _FindingV2Override(
    caution: '지출·투자·상속 같은 돈 결정에서 감정 싸움으로 번지기 쉬운 구성입니다. '
        '전통 관상은 콧방울을 재백궁의 곳간으로 보아, 이 자리가 서로 다르면 돈을 쓰는 기준도 갈린다고 했어요. '
        '냉전이 반복되면 돈 대화 자체를 피하게 되는 것이 이 구성의 전형적인 경로입니다.',
    scenario: '집 구매나 부모 지원 같은 큰 지출 앞에서 서로의 손익을 따지다 말이 날카로워지기 쉽습니다. '
        '그런 대화가 몇 번 반복되면 "이 사람과는 돈 얘기 하면 안 된다" 는 금기가 생깁니다. '
        '금기가 생기면 중요한 경제 결정을 혼자 진행하게 되고, 그게 신뢰를 무너뜨립니다.',
  ),
  // v1 은 "두 분이 직접 새로 정의하게 됩니다" 로 앞일을 확정했다.
  'YY-modernCross': _FindingV2Override(
    meaning: '성별 기대와 측정된 성향이 반대로 나온 구성입니다. '
        '여성 쪽이 추진형, 남성 쪽이 수용형 같은 구도라 전통적 역할 분담이 그대로 들어맞지 않아요. '
        '전통 관상도 음양을 성별이 아니라 얼굴의 기운으로 읽었습니다.',
    observation: '집안일·의사결정·경제 활동 같은 전통적 역할 분담이 그대로 들어맞지 않는 구성입니다. '
        '고정 역할에서 자유로운 만큼 서로의 재능에 맞춘 분담이 가능해요. '
        '다만 양가 부모·주변 사람과 기대 충돌이 생기기 쉽습니다.',
  ),
};

extension CompatFindingV2 on CompatFinding {
  /// v2 톤으로 덮어쓴 사본. 해당 id 의 override 가 없으면 자기 자신을 돌려준다.
  CompatFinding toV2() {
    final o = _findingV2Overrides[id];
    if (o == null) return this;
    return CompatFinding(
      id: id,
      title: title,
      domain: domain,
      delta: delta,
      meaning: o.meaning ?? meaning,
      observation: o.observation ?? observation,
      strength: strength,
      caution: o.caution ?? caution,
      scenario: o.scenario ?? scenario,
      action: action,
    );
  }
}
