/// 十二宮 (12 Palaces) — 궁합 엔진 L2 층의 데이터 타입.
///
/// 柳莊相法·神相全編 十二宮 grounded. 관상 엔진의 14-node 측정을 그대로
/// 재활용하되, 궁합 해석 관점에서 palace state (weak/balanced/strong) +
/// sub-flag (魚尾紋, 山根, 印堂) 로 재조직한다.
///
/// 설계 SSOT: `docs/compat/FRAMEWORK.md` §3.
library;

/// 十二宮. 전통 배치대로 1=命 ~ 12=父母.
enum Palace {
  /// 命宮 — 印堂 (미간). 일생의 根幹·기개.
  life,

  /// 財帛宮 — 코 전체 (準頭·蘭台·廷尉). 재물·축적.
  wealth,

  /// 兄弟宮 — 눈썹 (眉). 형제애·동료.
  sibling,

  /// 田宅宮 — 눈과 눈썹 사이·상안검. 주거·가정 안정.
  property,

  /// 男女宮 — 누당·눈 아래 와잠. 자녀·성적 매력.
  children,

  /// 奴僕宮 — 地閣 兩側 (턱 옆). 부하·인맥.
  slave,

  /// 妻妾宮 (夫妻宮) — 魚尾 (눈꼬리 옆 奸門). 배우자·부부 궁합.
  spouse,

  /// 疾厄宮 — 山根 (nose root·비근). 건강·저항력.
  illness,

  /// 遷移宮 — 驛馬 (이마 옆 끝). 이주·외출.
  migration,

  /// 官祿宮 — 중정 (이마 중앙). 관운·직업·사회적 지위.
  career,

  /// 福德宮 — 天倉 (이마 위 좌우). 복·덕·평온.
  fortune,

  /// 父母宮 — 日角·月角 (이마 위 좌우). 부모 운.
  parents,
}

extension PalaceLabel on Palace {
  /// 한자 4자 고전 표기 (옛 문헌 인용 또는 괄호 보조용).
  String get hanja {
    switch (this) {
      case Palace.life:
        return '命宮';
      case Palace.wealth:
        return '財帛宮';
      case Palace.sibling:
        return '兄弟宮';
      case Palace.property:
        return '田宅宮';
      case Palace.children:
        return '男女宮';
      case Palace.slave:
        return '奴僕宮';
      case Palace.spouse:
        return '妻妾宮';
      case Palace.illness:
        return '疾厄宮';
      case Palace.migration:
        return '遷移宮';
      case Palace.career:
        return '官祿宮';
      case Palace.fortune:
        return '福德宮';
      case Palace.parents:
        return '父母宮';
    }
  }

  /// 한국어 이름. 해설문 본문에서 이 이름을 우선 쓴다.
  String get korean {
    switch (this) {
      case Palace.life:
        return '명궁';
      case Palace.wealth:
        return '재백궁';
      case Palace.sibling:
        return '형제궁';
      case Palace.property:
        return '전택궁';
      case Palace.children:
        return '남녀궁';
      case Palace.slave:
        return '노복궁';
      case Palace.spouse:
        return '부부궁';
      case Palace.illness:
        return '질액궁';
      case Palace.migration:
        return '천이궁';
      case Palace.career:
        return '관록궁';
      case Palace.fortune:
        return '복덕궁';
      case Palace.parents:
        return '부모궁';
    }
  }

  /// 얼굴 위 어디에 있는 궁인지 한 줄 설명. 처음 언급될 때만 쓴다.
  String get locationKo {
    switch (this) {
      case Palace.life:
        return '미간 가운데';
      case Palace.wealth:
        return '코 전체';
      case Palace.sibling:
        return '눈썹';
      case Palace.property:
        return '눈과 눈썹 사이';
      case Palace.children:
        return '눈 아래 와잠 부근';
      case Palace.slave:
        return '턱 옆면';
      case Palace.spouse:
        return '눈꼬리 바깥';
      case Palace.illness:
        return '콧대 뿌리(산근)';
      case Palace.migration:
        return '관자놀이';
      case Palace.career:
        return '이마 한가운데';
      case Palace.fortune:
        return '이마 위 좌우';
      case Palace.parents:
        return '이마 윗부분 좌우';
    }
  }

  /// 그 궁이 맡은 삶의 영역. 해설 본문에서 "무엇을 보는 궁인지" 안내에 쓴다.
  String get domainKo {
    switch (this) {
      case Palace.life:
        return '일상의 기개와 결단';
      case Palace.wealth:
        return '재물과 축적';
      case Palace.sibling:
        return '형제·동료와의 정';
      case Palace.property:
        return '주거와 가정의 안정';
      case Palace.children:
        return '자녀와 친밀함';
      case Palace.slave:
        return '주변 사람·인맥';
      case Palace.spouse:
        return '배우자와의 인연';
      case Palace.illness:
        return '건강과 체력';
      case Palace.migration:
        return '이주와 바깥 활동';
      case Palace.career:
        return '직업과 사회적 지위';
      case Palace.fortune:
        return '복과 여유';
      case Palace.parents:
        return '부모와의 인연';
    }
  }
}

/// 결혼 중요도 weight — PalacePair aggregator 에서 delta 에 곱해진다.
/// 합 = 1.00. FRAMEWORK §3.1.
const Map<Palace, double> palaceMarriageWeight = {
  Palace.spouse: 0.28,
  Palace.children: 0.22,
  Palace.life: 0.15,
  Palace.property: 0.13,
  Palace.fortune: 0.12,
  Palace.wealth: 0.05,
  Palace.slave: 0.03,
  Palace.illness: 0.01,
  Palace.sibling: 0.003,
  Palace.career: 0.003,
  Palace.migration: 0.002,
  Palace.parents: 0.002,
};

/// 3 단계 state — 각 궁의 우세/위축 강도.
enum PalaceLevel { weak, balanced, strong }

/// 전통 서술에서 이름이 붙은 sub-feature. PP rule 의 필요 조건으로 쓰인다.
enum PalaceFlag {
  /// 印堂明潤 — 미간이 넓고 밝음. 命宮 strong 보강.
  glabellaBright,

  /// 印堂緊結 — 미간이 좁고 어두움. 命宮 weak 보강.
  glabellaTight,

  /// 準頭豊肉 — 코끝이 복스럽게 볼룸. 財帛 strong 보강.
  bulbousTip,

  /// 매부리코. 財帛 강하나 독단 경향.
  hookedNose,

  /// 細樑 — 가늘고 예리한 콧대. 財帛 weak 보강.
  thinBridge,

  /// 淚堂飽滿 — 와잠이 통통. 男女宮 strong 보강.
  plumpLowerEyelid,

  /// 淚堂陷 — 와잠 함몰. 男女宮 weak 보강.
  hollowLowerEyelid,

  /// 魚尾清潤 — 눈꼬리 매끈 (주름 없음). 妻妾宮 strong 보강.
  smoothFishTail,

  /// 魚尾紋 — 눈꼬리 잔주름. 妻妾宮 weak 보강 (age 30+ gate).
  fishTailWrinkle,

  /// 山根高 — 산근이 높음. 疾厄 strong.
  sanGenHigh,

  /// 山根陷 — 산근 함몰. 疾厄 weak.
  sanGenLow,

  /// 이마 밝고 평탄. 福德 strong.
  cloudlessForehead,

  /// 天倉 함몰. 福德 weak.
  dentedTemple,
}

/// 한 사람의 한 궁 state — level + 수치 요약 + sub-flag 집합.
class PalaceState {
  final Palace palace;
  final PalaceLevel level;

  /// 해당 궁 관여 metric/node 의 평균 z.
  final double zMean;

  /// 가장 극단 metric 의 |z|.
  final double absZMax;

  final Set<PalaceFlag> flags;

  const PalaceState({
    required this.palace,
    required this.level,
    required this.zMean,
    required this.absZMax,
    required this.flags,
  });

  bool hasFlag(PalaceFlag f) => flags.contains(f);
  bool get isStrong => level == PalaceLevel.strong;
  bool get isWeak => level == PalaceLevel.weak;
}

/// PP rule 발동 기록 — narrative 와 invariant 검사에 사용.
class PalacePairEvidence {
  final String ruleId;
  final Palace palace;
  final double delta;
  final String verdict;

  const PalacePairEvidence({
    required this.ruleId,
    required this.palace,
    required this.delta,
    required this.verdict,
  });
}

/// L2 최종 산출 — sub-score + 발동 rule 리스트.
class PalacePairResult {
  /// 0~100 normalize (clamp 5~99). §3.4 formula.
  final double subScore;
  final List<PalacePairEvidence> evidence;

  const PalacePairResult({required this.subScore, required this.evidence});
}
