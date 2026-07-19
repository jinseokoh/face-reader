import 'package:facely/domain/models/battle.dart';

const List<BattleTitleCategory> kBattleTitleCatalog = [
  BattleTitleCategory('지역', [
    BattleTitlePreset('서울지역 케미 그룹', _kBoth),
    BattleTitlePreset('경기 인천 케미 그룹', _kBoth),
    BattleTitlePreset('부산 경남 케미 그룹', _kBoth),
    BattleTitlePreset('대구 경북 케미 그룹', _kBoth),
    BattleTitlePreset('대전 충청 케미 그룹', _kBoth),
    BattleTitlePreset('광주 전라 케미 그룹', _kBoth),
    BattleTitlePreset('강원지역 케미 그룹', _kBoth),
    BattleTitlePreset('제주지역 케미 그룹', _kBoth),
  ]),
  BattleTitleCategory('직업', [
    BattleTitlePreset('직장인 케미 그룹', _kBoth),
    BattleTitlePreset('대학생 대학원생 케미 그룹', _kBoth),
    BattleTitlePreset('개발자 케미 그룹', _kBoth),
    BattleTitlePreset('병원에서 일하는 사람들 케미 그룹', _kBoth),
    BattleTitlePreset('선생님들의 케미 그룹', _kBoth),
    BattleTitlePreset('공무원 케미 그룹', _kBoth),
    BattleTitlePreset('자영업 사장님 케미 그룹', _kBoth),
    BattleTitlePreset('프리랜서 케미 그룹', _kBoth),
  ]),
  BattleTitleCategory('MBTI', [
    BattleTitlePreset('E끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('I끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('N끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('S끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('T끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('F끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('J끼리 모이는 케미 그룹', _kBoth),
    BattleTitlePreset('P끼리 모이는 케미 그룹', _kBoth),
  ]),
  BattleTitleCategory('취미', [
    BattleTitlePreset('천생연분 궁합 나오면 전시회 한번 같이 가요.', _kBoth),
    BattleTitlePreset('천생연분 궁합 나오면 영화 한편 같이 봐요.', _kBoth),
    BattleTitlePreset('천생연분 궁합 나오면 식사 한번 같이해요.', _kBoth),
    BattleTitlePreset('천생연분 궁합 나오면 커피 한잔 같이해요.', _kBoth),
    BattleTitlePreset('천생연분 궁합 나오면 술 한잔 같이해요.', _kBoth),
  ]),
  BattleTitleCategory('즉석', [
    BattleTitlePreset('그것이 알고 싶다 케미 그룹', _kBoth),
    BattleTitlePreset('나는 솔로 케미 그룹', _kBoth),
    BattleTitlePreset('무한도전 케미 그룹', _kBoth),
    BattleTitlePreset('한국인의 밥상 케미 그룹', _kBoth),
    BattleTitlePreset('나는 자연인이다 케미 그룹', _kBoth),
    BattleTitlePreset('나 혼자 산다 케미 그룹', _kBoth),
    BattleTitlePreset('놀면 뭐하니 케미 그룹', _kBoth),
    BattleTitlePreset('전지적 참견 시점 케미 그룹', _kBoth),
    BattleTitlePreset('전국 노래자랑 케미 그룹', _kBoth),
    BattleTitlePreset('세상에 이런 일이 케미 그룹', _kBoth),
  ]),
  BattleTitleCategory('기타', [], isCustom: true),
];

const _kBoth = {BattleRoomKind.all, BattleRoomKind.match};
class BattleTitleCategory {
  final String name;
  final List<BattleTitlePreset> titles;

  /// true 면 프리셋 리스트 대신 자유 입력 필드를 보여준다 (기타 전용).
  final bool isCustom;

  const BattleTitleCategory(this.name, this.titles, {this.isCustom = false});
}

/// 방 제목 프리셋 카탈로그 — 6 카테고리(지역/직업/MBTI/취미/즉석/기타).
/// 기타는 프리셋 없이 자유 입력([BattleTitleCategory.isCustom]). 서버에는
/// 확정된 title 문자열만 저장된다(카테고리는 클라이언트 UI 전용, 서버 컬럼 없음).
class BattleTitlePreset {
  final String title;
  final Set<BattleRoomKind> allowedKinds;

  const BattleTitlePreset(this.title, this.allowedKinds);
}
