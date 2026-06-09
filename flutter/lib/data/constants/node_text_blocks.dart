/// 14-node × 3-band 관상학 해석 SSOT.
///
/// UI 의 `_ExpandableNodeBar` 가 탭 시 band 에 해당하는 본문을 노출.
/// 관상 점수(attribute) 는 "종합 평가" 이고, 이 본문은 "근거 제시" — 왜 그
/// 점수가 나오는지 부위 단위로 설명한다.
///
/// Band 경계 (attribute_derivation 와 일관):
///   z ≥ +1.0 → high
///   |z| < 1.0 → mid
///   z ≤ -1.0 → low
/// zone (upper/middle/lower) 은 rollUpMeanZ, leaf 는 ownMeanZ 기준.
///
/// 성별 분기는 eye·nose·mouth·cheekbone 4 node 에서만 제공. 나머지는 shared 로
/// 충분. `resolveNodeBody(block, gender)` 가 male/female 우선 선택, 없으면 shared.
library;

import 'package:face_engine/data/enums/gender.dart';

/// 한 band 의 본문. 성별 분기는 선택적 — male/female 이 null 이면 shared 로 폴백.
class NodeTextBlock {
  final String? shared;
  final String? male;
  final String? female;
  const NodeTextBlock({this.shared, this.male, this.female});
}

class NodeTextSet {
  final NodeTextBlock high;
  final NodeTextBlock mid;
  final NodeTextBlock low;
  const NodeTextSet({
    required this.high,
    required this.mid,
    required this.low,
  });
}

String resolveNodeBody(NodeTextBlock block, Gender gender) {
  if (gender == Gender.male && block.male != null) return block.male!;
  if (gender == Gender.female && block.female != null) return block.female!;
  return block.shared ?? '';
}

/// band 분기 helper. z 값에서 high/mid/low 결정 후 해당 NodeTextBlock 반환.
NodeTextBlock? nodeBlockForZ(String nodeId, double z) {
  final set = nodeTextBlocks[nodeId];
  if (set == null) return null;
  if (z >= 1.0) return set.high;
  if (z <= -1.0) return set.low;
  return set.mid;
}

// ────────────────────────── 14-node × 3-band ──────────────────────────

const Map<String, NodeTextSet> nodeTextBlocks = {
  // ─── face (root · 얼굴 전체) ─────────────────────────────────────────
  'face': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '얼굴 전체 비례와 가운데(코·광대) 비율이 평균보다 뚜렷한 편입니다. 부위들이 전반적으로 강한 쪽으로 기울어 존재감이 선명한 유형이라, 강점의 총합이 큰 만큼 피로가 쌓였을 때 여파도 큽니다. 쉬어가는 리듬을 의식적으로 설계해야 타고난 결이 오래 갑니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '얼굴 전체가 균형을 유지하는 편입니다. 특정 부위가 극단적으로 튀지 않고 고르게 자리한 균형형이라, 화려함은 덜해도 어느 자리에 들어가도 잘 안 무너지는 적응력과 꾸준함이 최대 자산입니다. 시간이 쌓일수록 평가가 올라가는 유형입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '얼굴 전체가 평균보다 차분한 쪽입니다. 돌출되지 않아 겸허하고 온화하게 보이는 장점이 있는 대신, 자기 표현이 약해 저평가되기 쉽습니다. 포트폴리오·SNS·1대1 대화 같은 드러내는 장치를 만들어 둬야 타고난 기운이 사회적 보상으로 이어집니다.',
    ),
  ),

  // ─── upper zone (상정) ──────────────────────────────────────────────
  'upper': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '이마·미간·눈썹 쪽이 가운데·아래보다 뚜렷하게 강한 편입니다. 지적인 인상이 깊게 흐르고 젊은 시기의 도약이 빠른 유형입니다. 다만 위쪽이 너무 강하면 감정·생활 쪽이 뒤로 밀려 관계의 온기가 식기 쉬우니, 아래쪽(입·턱)의 활력을 의식적으로 보강하는 게 균형의 열쇠입니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '이마 쪽이 가운데·아래와 비슷하게 균형을 이룬 편입니다. 한 시기에 몰아치는 발복이 아니라 평생 고르게 퍼지는 대기만성형이라, 한 번의 기회보다 쌓은 시간이 가장 큰 자산입니다. 꾸준한 자기 성장 리듬이 평가의 기반이 됩니다.',
    ),
    low: NodeTextBlock(
      shared:
          '이마 쪽이 가운데·아래보다 상대적으로 작은 편입니다. 초년에 윗선의 도움은 약할 수 있지만, 오히려 혼자 뚫고 나가는 기질로 바뀌는 경우가 많습니다. 외부 의존 없이 쌓은 결과물이 중년 이후 강한 반전의 발판이 되는, 늦게 피는 유형입니다.',
    ),
  ),

  // ─── forehead (이마) ────────────────────────────────────────────────
  'forehead': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '이마가 넓고 반듯하게 열린 편입니다. 머리가 명민하고 학문·공직·교육 쪽 인연의 문이 또래보다 일찍 열립니다. 지도력의 밑판이 되는 부위라 앞에 서는 자리에 기회가 먼저 들어오고, 윗사람의 신뢰가 젊은 시기에 결정적 도약을 만드는 경우가 많습니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '이마가 평균 폭과 높이로 자리한 안정형입니다. 학습 감각과 무게감이 극단적이지 않게 조화를 이뤄, 한 전문 영역을 정해 꾸준히 깊이를 쌓는 장인형 경로에서 진가가 납니다. 화려한 출발보다 탄탄한 중년을 만드는 편입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '이마가 좁거나 낮은 편입니다. 초년의 윗사람 지원은 약할 수 있지만 독학·독립 기질이 강해 자기 힘으로 길을 엽니다. 중년 이후 오히려 위로 치솟는 반전의 여지가 있는 유형이라, 조급함을 다스리는 게 핵심입니다.',
    ),
  ),

  // ─── glabella (미간 · 印堂) ────────────────────────────────────────
  'glabella': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '미간이 넓고 맑게 열린 편입니다. 대범하고 포용력이 있으며 스트레스에 잘 안 흔들립니다. 큰 결정 앞에서도 중심이 흔들리지 않고, 급한 판단을 강요받는 자리에서도 한 호흡 쉬는 여유가 자연스럽게 나옵니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '미간 폭이 평균 범위입니다. 닫혀 있지도 과하게 열려 있지도 않은 균형형이라, 안정된 판단력과 적절한 긴장감을 함께 갖췄습니다. 상황에 따라 유연하게 대응하는 중용의 감각이 최대 강점입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '미간이 좁은 편입니다. 예민하고 세심하며 생각이 많은데, 이건 뒤집으면 관찰력과 섬세함의 원천입니다. 예술·연구·상담처럼 미세한 결을 읽는 일에서 강점을 발휘하는 유형이라, 과한 긴장은 호흡·수면 루틴으로 의식적으로 풀어줘야 합니다.',
    ),
  ),

  // ─── eyebrow (눈썹) ────────────────────────────────────────────────
  'eyebrow': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '눈썹이 짙고 정돈된 편입니다. 의지·결단이 강하고 형제·동료운도 두터워서, 한 번 목표를 세우면 결실까지 밀어붙이는 집요함이 있습니다. 사회생활에서 "등을 맡길 수 있는 사람"이라는 평이 자연스럽게 따라붙습니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '눈썹이 적절한 굵기와 결입니다. 의지와 유연함이 균형을 이뤄, 강하게 집중하는 시기와 쉬어가는 리듬을 자연스럽게 바꿔 쓰는 유형입니다. 지속 가능한 페이스가 장기 성취의 기반이 됩니다.',
    ),
    low: NodeTextBlock(
      shared:
          '눈썹이 희미하거나 흐트러진 편입니다. 형제·동료의 지원이 약해 혼자 뚫는 구조일 수 있지만, 뒤집으면 독립·자주의 기질입니다. 의지가 약해 보일 땐 결심을 작게 쪼개 실행하는 습관이 보완책이 되고, 꾸준한 기록·체크리스트 루틴이 평생 자산이 됩니다.',
    ),
  ),

  // ─── middle zone (중정) ────────────────────────────────────────────
  'middle': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '가운데 영역(눈·코·광대)이 셋 중 뚜렷하게 우세한 편입니다. 30대 후반에서 40대 사이에 재물·권위·사회적 영향력이 같이 오르는 주기를 타는 유형입니다. 활동기의 폭발력이 강점이지만, 관리 없이 쏟아부으면 50대 이후 급격히 지치기 쉬우니 건강과 관계의 저축을 병행해야 합니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '가운데 영역이 위·아래와 비슷한 균형형입니다. 한 구간에 몰리는 성취보다 꾸준히 쌓이는 누적형이라, 한 번의 도약보다 5~10년 단위의 방향성이 평생 궤적을 정합니다. 재물·복·덕이 고르게 균형을 이루는 편입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '가운데 영역이 위·아래보다 약한 편입니다. 중년의 폭발적 발복은 덜할 수 있지만, 반대로 초년·말년이 살아나는 "젊거나 늙어 빛나는" 유형입니다. 중년의 평탄기를 초조해하지 않고 축적기로 받아들이는 태도가 말년 결실의 밑거름이 됩니다.',
    ),
  ),

  // ─── eye (눈) · gender split ──────────────────────────────────────
  'eye': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '눈이 맑고 또렷하게 살아 있는 편입니다. 흐름을 먼저 꿰뚫어 보는 통찰과 결단력이 강하게 자리한 구조입니다.',
      male:
          '눈이 맑고 또렷한 편입니다. 위엄·기백·결단이 정면에서 먼저 드러나고, 사회적 신뢰와 가정 안정의 축이 같이 받쳐줍니다. 리더·경영·공직·교육처럼 "먼저 보는 사람"의 자리에서 특히 빛나는 유형이라, 눈빛의 무게가 말보다 먼저 작동합니다.',
      female:
          '눈이 맑고 또렷한 편입니다. 정이 깊고 영민함이 같이 깃들어, 가정·연애의 결이 깊게 유지되는 유형입니다. 눈빛에 실린 감수성이 예술·상담·교육에서 강한 공감대를 만드는, "눈으로 읽고 눈으로 말하는" 사람입니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '눈이 평균 범위입니다. 통찰과 감수성이 극단적이지 않게 균형을 이뤄, 필요할 때 집중하고 아닐 때 유연해지는 결입니다. 감정의 온·오프가 자연스러운 유형입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '눈이 상대적으로 작거나 흐린 편입니다. 앞에 나서는 기세보다 속으로 관찰하는 데 에너지가 모이는 편이라, 신중하고 수비적인 판단이 강점이 됩니다.',
      male:
          '눈이 작거나 흐린 편입니다. 앞에 드러내는 위엄보다 속으로 쌓는 신중파라, 성급한 돌파보다 오랜 관찰과 축적이 강점입니다. 장기전·참모·연구에서 진가가 나고, 중년 이후 "속 깊은 사람"이라는 평이 자산이 됩니다.',
      female:
          '눈이 작거나 흐린 편입니다. 감수성이 안으로 깊이 잠겨, 먼저 드러내기보다 오래 지켜보고 깊이 판단하는 유형입니다. 섬세함과 꾸준한 정이 관계의 밀도를 만드는 최대 자산이고, 소수 정예의 우정이 평생 갑니다.',
    ),
  ),

  // ─── nose (코) · gender split ──────────────────────────────────────
  'nose': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '코가 높고 또렷하게 자리한 편입니다. 재물의 흐름과 자기 신념의 축이 강하게 작동하는 구조입니다.',
      male:
          '코가 높고 또렷한 편입니다. 중년에 재물이 크게 풀리는 기질이 두드러지고, 권위·자기 주장·재물의 축이 한 줄기로 정렬된 유형입니다. 사업·관리직에서 진가를 발휘하지만, 자신감의 날이 너무 서면 주변과 마찰이 커지니 겸양의 기술이 장기 자산이 됩니다.',
      female:
          '코가 높고 또렷한 편입니다. 자기 결을 분명히 세우는 골격이라 사회 활동·독립 경제의 축이 깊습니다. 전문직·리더 자리에 잘 맞는 유형이고, 배우자와의 긴장이 커지기 쉬우니 관계 안에서 결을 조율하는 대화가 함께 될 때 가장 좋습니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '코가 평균 범위입니다. 재물·신념의 결이 극단적이지 않게 중용을 이룬 구조라, 꾸준히 쌓는 축적형 재물 기질이 깊습니다. 시간을 아군으로 만드는 운영이 최대 강점입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '코가 낮거나 작게 자리한 편입니다. 돈의 흐름이 빠르게 지나가는 편이라, 의식적인 저축과 시스템 설계가 재물 곡선의 핵심이 됩니다.',
      male:
          '코가 낮거나 작은 편입니다. "벌되 남기는 설계"가 평생 과제고, 욕심을 누르는 겸허함으로 사람을 모으는 쪽에서 진가가 납니다. 조직·중개·협업에서 강점을 발휘하고, 남의 자원을 움직여 성과를 만드는 게 자산입니다.',
      female:
          '코가 낮거나 작은 편입니다. 자기 주장을 앞세우기보다 관계 안에서 공간을 비워주는 방식이 자산이 됩니다. 협업·공감 기반의 일에서 특히 빛나는 유형이라, 부드러움이 최대의 사회 자본이 됩니다.',
    ),
  ),

  // ─── cheekbone (광대 · 태산·화산) · gender split ──────────────────
  'cheekbone': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '광대가 힘차게 자리한 편입니다. 사람을 부려 일을 만드는 기질과 자기 주장의 축이 같이 살아 있습니다.',
      male:
          '광대가 힘차게 솟은 편입니다. 호령과 권위의 축이 정면에 드러나, 조직을 이끄는 자리에서 진가가 납니다. 운영·관리·정치 쪽에서 강한 리더십을 보이는 "장군형"이고, 주변을 품는 여유가 같이 갖춰질 때 완성됩니다.',
      female:
          '광대가 또렷하게 자리한 편입니다. 자기 주장과 사회 활동의 축이 강해, 전통적 "순종형" 이미지와는 거리가 있지만 현대 사회에선 오히려 리더·전문직의 큰 자산입니다. 관계 안에서 "부드럽게 이끄는 기술"이 함께 될 때 일과 가정을 동시에 다루는 역량이 됩니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '광대가 튀지 않고 얼굴과 조화를 이룬 편입니다. 밖으로 나서는 기운과 안에서 쌓는 기운이 균형을 이뤄, 협업·중립의 자리에서 가장 잘 작동합니다. 극단적 주장보다 합리적 조정자형입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '광대가 낮고 부드럽게 자리한 편입니다. 호령보다 친화·중재의 기운이 우세해, 관계를 매끄럽게 만드는 능력이 타고났습니다.',
      male:
          '광대가 낮은 편입니다. 앞에서 호령하기보다 전략을 짜는 참모형이라, 설계·자문·2인자 자리에서 강점을 보입니다. 부드러움이 오히려 무기가 되고, 경쟁에서 한 발 물러선 자리가 가장 큰 자산이 됩니다.',
      female:
          '광대가 낮은 편입니다. 유순하고 단아한 인상이라 관계 안에서 편안함을 주는 매력이 최대 자산입니다. 상담·교육·의료처럼 사람의 마음을 다루는 일에서 빛나는 유형이고, 부드러움이 전문성과 결합할 때 가장 오래 사랑받습니다.',
    ),
  ),

  // 귀(ear) 는 MediaPipe 정면 메시 커버리지 부족으로 측정 미지원 노드. UI 및
  // 본문에서 완전히 제외. physiognomy_tree 에는 구조 정합성 유지 위해 남아
  // 있지만(`unsupported=true`), node_text_blocks 에서는 항목 자체를 둘 필요가
  // 없다.

  // ─── lower zone (하정) ─────────────────────────────────────────────
  'lower': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '아래 영역(입·턱·인중)이 셋 중 뚜렷하게 우세한 편입니다. 50대 이후 오히려 기운이 깊어지는 "말년 복" 유형이라, 식복·자손운·가정 안정의 축이 같이 받쳐줍니다. 관계와 가정에 쏟는 투자가 평생 최대 수익률을 만듭니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '아래 영역이 균형 잡힌 편입니다. 말년의 폭발보다 꾸준한 안정이 어울리고, 가족·친구 같은 가까운 사람과의 결이 시간과 함께 단단해지는 유형입니다. 속 깊고 두터운 안정형입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '아래 영역이 위·가운데보다 가벼운 편입니다. 말년 자원을 의식적으로 설계하지 않으면 얇아지는 구조라, 30~40대 절정기에 자본·관계·건강 세 축에 투자를 분산해 둬야 합니다. 가볍고 유연해서 환경 변화에 빠르게 적응하는 강점도 있지만, "너무 흐름에 맡긴" 결과가 되지 않게 의식적 설계가 필요합니다.',
    ),
  ),

  // ─── philtrum (인중) ───────────────────────────────────────────────
  'philtrum': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '인중이 깊고 길게 자리한 편입니다. 안정·자손운·건강한 수명의 축이 깊어, 말년으로 갈수록 평가가 올라가는 유형입니다. 한 번 시작한 일은 끝까지 끌고 가는 뚝심이 있고, 그 꾸준함이 결실의 품질을 정합니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '인중이 평균 깊이인 균형형입니다. 활력과 안정이 적당한 비율을 이뤄, 생애 구간마다 적응력이 고르게 나옵니다. 관계와 건강의 결이 자연스럽게 유지되는 안정형입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '인중이 짧거나 얕은 편입니다. 열정과 활력이 높은 대신 안정의 축은 의식적으로 설계해야 하는 구조입니다. 관계와 건강의 리듬 관리가 평생 과제고, 자기 에너지의 주기를 알고 조절하는 훈련이 장기 자산이 됩니다.',
    ),
  ),

  // ─── mouth (입) · gender split ────────────────────────────────────
  'mouth': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '입이 크고 입꼬리가 살아 있는 편입니다. 식복·표현력·사교의 축이 같이 자리합니다.',
      male:
          '입이 크고 도톰한 편입니다. 말재주·호방함·식복이 같이 있어 영업·정치·강연처럼 "입으로 성공하는" 영역에서 진가가 납니다. 다만 말의 무게를 스스로 다스리지 않으면 구설이 따르기 쉬워, 침묵의 훈련이 장기 자산이 됩니다.',
      female:
          '입이 크고 도톰한 편입니다. 표현력과 사교의 기운이 같이 살아 있어, 사람을 모으고 마음을 부드럽게 움직이는 자질이 강합니다. 가정·사회 양쪽에서 중심 역할을 맡기 좋은 유형입니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '입이 평균 크기인 안정형입니다. 표현과 절제가 균형을 이뤄, 자리와 상대에 따라 톤을 자연스럽게 조절합니다. 필요할 때 열고 아닐 때 닫는 감각이 자산입니다.',
    ),
    low: NodeTextBlock(
      shared:
          '입이 작거나 다문 결이 강한 편입니다. 말수가 적고 속을 깊이 간직하는 유형이라, 말의 무게가 실리는 자리에서 오히려 신뢰를 얻습니다.',
      male:
          '입이 작고 다문 결이 강한 편입니다. 과묵·절제가 몸에 배어, 한마디의 무게가 큰 자리(법조·연구·전문직)에서 강점이 큽니다. 사교가 필요한 자리에선 의도적으로 표현의 문을 여는 훈련이 함께 될 때 균형이 맞습니다.',
      female:
          '입이 작고 다물어진 결이 강한 편입니다. 맑고 단정한 인상이라, 전문직·연구 자리에서 깊이를 만드는 강점이 됩니다. 말수가 적어도 한 마디의 무게가 실려, 존재감이 오래 남는 유형입니다.',
    ),
  ),

  // ─── chin (턱 · 항산·지각) ────────────────────────────────────────
  'chin': NodeTextSet(
    high: NodeTextBlock(
      shared:
          '턱이 듬직하고 넓게 자리한 편입니다. 말년 안정·가정·아랫사람운의 축이 모두 받쳐주는 "말년 복"형이라, 50대 이후 오히려 기운이 깊어집니다. 책임의 무게를 감당할수록 완성되는 상입니다.',
    ),
    mid: NodeTextBlock(
      shared:
          '턱이 평균 범위인 안정형입니다. 말년의 축이 중용을 유지해, 한 방에 큰 복을 받기보다 꾸준히 안정이 쌓여가는 유형입니다. 가정과 일의 균형이 자연스럽게 유지됩니다.',
    ),
    low: NodeTextBlock(
      shared:
          '턱이 짧거나 가벼운 편입니다. 말년의 완충이 얇아, 30~40대 절정기에 자본·관계·건강 세 축의 투자를 의식적으로 분산해 둬야 합니다. 동시에 가볍고 유연해 환경 변화에 빠르게 적응하는 강점이 있어, 이동·변화가 많은 일에서 진가를 발휘합니다.',
    ),
  ),
};

// ────────────────────────── Metric display labels ──────────────────────────

/// Metric id → 친화 label. 펼친 node 뷰에서 세부 측정값 줄에 사용.
const Map<String, String> metricDisplayLabels = {
  // face root
  'faceAspectRatio': '얼굴 세로/가로 비',
  'faceTaperRatio': '얼굴 테이퍼',
  'midFaceRatio': '중정 비율',
  // forehead
  'upperFaceRatio': '상정 비율',
  'foreheadWidth': '이마 너비',
  // glabella
  'browSpacing': '미간 간격',
  // eyebrow
  'eyebrowThickness': '눈썹 두께',
  'browEyeDistance': '눈썹-눈 거리',
  'eyebrowTiltDirection': '눈썹 기울기',
  'eyebrowCurvature': '눈썹 곡률',
  // eye
  'intercanthalRatio': '눈 간격',
  'eyeFissureRatio': '눈 폭',
  'eyeCanthalTilt': '눈꼬리 기울기',
  'eyeAspect': '눈 세로 비',
  // nose (frontal + lateral)
  'nasalWidthRatio': '코 너비',
  'nasalHeightRatio': '코 길이',
  'nasofrontalAngle': '비전두각',
  'nasolabialAngle': '코끝 각도',
  'noseTipProjection': '코끝 돌출',
  'dorsalConvexity': '콧대 곡률',
  // cheekbone
  'cheekboneWidth': '광대 너비',
  // philtrum
  'philtrumLength': '인중 길이',
  // mouth (frontal + lateral)
  'mouthWidthRatio': '입 너비',
  'mouthCornerAngle': '입꼬리 각도',
  'lipFullnessRatio': '입술 두께',
  'upperVsLowerLipRatio': '윗·아랫입술 비',
  'upperLipEline': '상순 E-line',
  'lowerLipEline': '하순 E-line',
  'mentolabialAngle': '순이각',
  // chin (frontal + lateral)
  'gonialAngle': '턱 각',
  'lowerFaceRatio': '하정 비율',
  'lowerFaceFullness': '하정 풍성도',
  'chinAngle': '턱 끝 각도',
  'facialConvexity': '안면 돌출각',
};
