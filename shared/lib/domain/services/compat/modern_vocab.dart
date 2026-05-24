/// 궁합 엔진 모던 한국어 vocabulary SSOT.
///
/// 전통 4 축 (오행·궁위·기질·친밀), 12 궁, 5 행, 5 관계, 4 등급 라벨을
/// 현대 한국인이 한 번에 이해할 수 있는 표현으로 매핑한다.
///
/// 운영 원칙:
///   - **전통 용어는 메인 라벨로 유지** — "천작지합 (天作之合)" 같이 한자 메타까지
///     함께 노출해 *근거*로서의 자료 가치 보존.
///   - **모던 한국어 보조 라벨 병행** — 별도 색의 작은 chip 으로 사용자가 즉시
///     의미를 이해하도록. UI 본문 (verdict/headline/detail) 은 전부 모던 한국어.
///   - **영문 병행 표기** — dimension 명에 "(Values)" 같은 영문을 괄호로 병행해
///     국제적·현대적 앱 인상.
///
/// 모든 narrative/UI 코드는 이 사전을 anchor 로 호출해야 한다.
/// 새 도메인 어휘 도입 시 본 파일을 먼저 갱신.
library;

import 'compat_label.dart';
import 'compat_sub_display.dart';
import 'five_element.dart';
import 'palace.dart';

const String kFiveFeaturesEnglish = 'Five Features';

// ─────────────────────── Dimension (4 축) ───────────────────────────────────

/// 五官 모던 별칭.
const String kFiveFeaturesModern = '얼굴 5 부위';

const String kThreeZonesEnglish = 'Three Zones';

/// 三停 (이마/코/턱) 모던 별칭.
const String kThreeZonesModern = '얼굴 3 구역';

const String kYinYangEnglish = 'Energy';

// ─────────────────────── Yin-Yang / Three Zones 모던 표현 ───────────────────

/// 음양 모던 별칭. "음양" 직접 노출 대신 사용.
const String kYinYangModern = '에너지 균형';
// ─────────────────────── CompatLabel (4 등급) ───────────────────────────────

extension CompatLabelModern on CompatLabel {
  /// 일반 사용자가 즉시 이해할 수 있는 모던 부제. list 카드의 chip 아래
  /// 흐린 caption 으로 노출. ≈ "한 문장 정도" 분량.
  String get modernKo {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '굳이 맞추지 않아도 손발이 맞는 사이';
      case CompatLabel.sangkyeongyeobin:
        return '서로 존중하며 오래가는 사이';
      case CompatLabel.mahapgaseong:
        return '시간을 들이면 점점 빛나는 사이';
      case CompatLabel.hyeonggeuknanjo:
        return '박자가 달라 부딪힘이 잦은 사이';
    }
  }

  /// 한 줄 캐치프레이즈. detail/report 헤더에 사용.
  String get tagline {
    switch (this) {
      case CompatLabel.cheonjakjihap:
        return '굳이 노력하지 않아도 손발이 척척 맞는 사이';
      case CompatLabel.sangkyeongyeobin:
        return '서로의 거리를 존중하며 오래 갈 수 있는 사이';
      case CompatLabel.mahapgaseong:
        return '시간과 정성을 들이면 좋은 짝이 되는 사이';
      case CompatLabel.hyeonggeuknanjo:
        return '결이 달라 부딪힘이 잦은 사이';
    }
  }
}

/// 점수 4 축 — UI/narrative 의 dimension 명. 한국어·영문 병행.
extension CompatSubKindModern on CompatSubKind {
  /// 그 dimension 이 *무엇을 보는지* 한 줄 설명. info row 본문에 쓴다.
  /// 명사형 종결 (판단·측정 등) 로 통일 — UX 톤 일관성.
  String get descriptionKo {
    switch (this) {
      case CompatSubKind.element:
        return '얼굴형(五行)이 드러내는 기본 성향과 삶의 태도가 얼마나 잘 맞는지를 판단.';
      case CompatSubKind.palace:
        return '결혼·돈·자녀·일 등 12 가지 생활 영역(十二宮)에서 두 사람이 어떻게 어우러지는지를 판단.';
      case CompatSubKind.qi:
        return '눈·코·입이 만드는 표현 방식(五官)이 만나 평소 어떻게 말하고 어떻게 듣는지를 판단.';
      case CompatSubKind.intimacy:
        return '이성 친밀감의 결은 매혹도와 연결이 되며, 관계의 출발이 될 수 있는 요소로 판단.';
    }
  }

  /// "가치관 (Values)" 한 줄 조합.
  String get displayLabel => '$modernKo ($englishLabel)';

  /// 영문 병행 표기 — "가치관 (Values)" 형태로 조합.
  String get englishLabel {
    switch (this) {
      case CompatSubKind.element:
        return 'Values';
      case CompatSubKind.palace:
        return 'Life Areas';
      case CompatSubKind.qi:
        return 'Communication';
      case CompatSubKind.intimacy:
        return 'Romance';
    }
  }

  /// 사용자에게 보이는 한국어 이름.
  String get modernKo {
    switch (this) {
      case CompatSubKind.element:
        return '가치관';
      case CompatSubKind.palace:
        return '관심사';
      case CompatSubKind.qi:
        return '소통 스타일';
      case CompatSubKind.intimacy:
        return '이성적 끌림';
    }
  }

  /// 점수 weight (%) — info row 우측 작은 라벨.
  String get weightLabel {
    switch (this) {
      case CompatSubKind.element:
        return '20%';
      case CompatSubKind.palace:
        return '40%';
      case CompatSubKind.qi:
        return '25%';
      case CompatSubKind.intimacy:
        return '15%';
    }
  }
}
// ─────────────────────── ElementRelationKind (5 관계) ───────────────────────

extension ElementRelationKindModern on ElementRelationKind {
  /// 한 줄 부연. detail 페이지의 관계 설명에 사용.
  String get descriptionKo {
    switch (this) {
      case ElementRelationKind.identity:
        return '비슷한 결을 가진 두 사람이라 말이 별로 없어도 잘 통하는 조합.';
      case ElementRelationKind.generating:
        return '서로의 기운을 북돋아 함께 있을수록 힘과 활력이 살아나는 조합.';
      case ElementRelationKind.generated:
        return '상대가 가진 결이 나의 부족함을 자연스럽게 채워주는 든든한 상생의 조합.';
      case ElementRelationKind.overcoming:
        return '내 기운이 상대를 누르는 흐름이라 자연스레 주도권을 쥐기 쉬운 조합.';
      case ElementRelationKind.overcome:
        return '상대 기운이 나를 제어하는 흐름이라 눈치와 긴장이 쌓이기 쉬운 조합.';
    }
  }

  /// 사용자에게 직관적으로 들리는 관계 이름.
  String get modernKo {
    switch (this) {
      case ElementRelationKind.identity:
        return '닮은꼴 케미의 조합';
      case ElementRelationKind.generating:
        return '활력을 주는 상생의 조합';
      case ElementRelationKind.generated:
        return '든든하게 받쳐주는 상생의 조합';
      case ElementRelationKind.overcoming:
        return '관계의 주도권이 내쪽으로 흐르기 쉬운 조합';
      case ElementRelationKind.overcome:
        return '상대방으로부터 긴장과 압박이 생기기 쉬운 조합';
    }
  }
}

// ─────────────────────── FiveElement (5 행 체형) ────────────────────────────

extension FiveElementModern on FiveElement {
  /// 한 줄 핵심 성향 — narrative 안 "어떤 사람인지" 한 문장 보조.
  String get coreTraitKo {
    switch (this) {
      case FiveElement.wood:
        return '곧고 자라나려는 의지가 강한 사람';
      case FiveElement.fire:
        return '밝고 사교적이며 분위기를 끌어올리는 사람';
      case FiveElement.earth:
        return '말과 약속이 무겁고 진득한 사람';
      case FiveElement.metal:
        return '원칙과 기준이 분명하고 흔들리지 않는 사람';
      case FiveElement.water:
        return '상황을 부드럽게 흘려보내는 영리한 사람';
    }
  }

  /// 사용자가 한 번에 알 수 있는 모던 별칭. "목형" 옆에 보조 노출.
  String get modernKo {
    switch (this) {
      case FiveElement.wood:
        return '성장형';
      case FiveElement.fire:
        return '열정형';
      case FiveElement.earth:
        return '안정형';
      case FiveElement.metal:
        return '원칙형';
      case FiveElement.water:
        return '유연형';
    }
  }
}
// ─────────────────────── Palace (12 궁 → 모던 도메인) ───────────────────────

extension PalaceModern on Palace {
  /// "재물 (Money)" 한 줄 조합.
  String get displayLabel => '$modernKo ($englishLabel)';

  /// 영문 병행 — "재물 (Money)" 같이 합쳐 표시.
  String get englishLabel {
    switch (this) {
      case Palace.life:
        return 'Self';
      case Palace.wealth:
        return 'Money';
      case Palace.sibling:
        return 'Friends';
      case Palace.property:
        return 'Home';
      case Palace.children:
        return 'Family Warmth';
      case Palace.slave:
        return 'Network';
      case Palace.spouse:
        return 'Partner';
      case Palace.illness:
        return 'Health';
      case Palace.migration:
        return 'Mobility';
      case Palace.career:
        return 'Career';
      case Palace.fortune:
        return 'Well-being';
      case Palace.parents:
        return 'Parents';
    }
  }

  /// 사용자가 즉시 이해하는 모던 도메인명. "재백궁" 자리에 직접 노출.
  String get modernKo {
    switch (this) {
      case Palace.life:
        return '자기다움';
      case Palace.wealth:
        return '재물';
      case Palace.sibling:
        return '친구·동료';
      case Palace.property:
        return '집·생활';
      case Palace.children:
        return '자녀·다정함';
      case Palace.slave:
        return '사람 관계';
      case Palace.spouse:
        return '배우자';
      case Palace.illness:
        return '건강';
      case Palace.migration:
        return '변화·이동';
      case Palace.career:
        return '커리어';
      case Palace.fortune:
        return '행복·여유';
      case Palace.parents:
        return '부모·가족';
    }
  }
}
