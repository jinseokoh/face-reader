import 'package:facely/domain/models/battle.dart';

/// 방 제목 프리셋 카탈로그 — 6 카테고리(지역/직업/MBTI/취미/즉석/기타).
/// 기타는 프리셋 없이 자유 입력([BattleTitleCategory.isCustom]). 서버에는
/// 확정된 title 문자열만 저장된다(카테고리는 클라이언트 UI 전용, 서버 컬럼 없음).
class BattleTitlePreset {
  final String title;
  final Set<BattleRoomKind> allowedKinds;

  const BattleTitlePreset(this.title, this.allowedKinds);
}

class BattleTitleCategory {
  final String name;
  final List<BattleTitlePreset> titles;

  /// true 면 프리셋 리스트 대신 자유 입력 필드를 보여준다 (기타 전용).
  final bool isCustom;

  const BattleTitleCategory(this.name, this.titles, {this.isCustom = false});
}

const _kBoth = {BattleRoomKind.all, BattleRoomKind.match};
const _kAllOnly = {BattleRoomKind.all};

const List<BattleTitleCategory> kBattleTitleCatalog = [
  BattleTitleCategory('지역', [
    BattleTitlePreset('서울지역 케미 배틀', _kBoth),
    BattleTitlePreset('경기 인천 케미 배틀', _kBoth),
    BattleTitlePreset('부산 경남 케미 배틀', _kBoth),
    BattleTitlePreset('대구 경북 케미 배틀', _kBoth),
    BattleTitlePreset('대전 충청 케미 배틀', _kBoth),
    BattleTitlePreset('광주 전라 케미 배틀', _kBoth),
    BattleTitlePreset('강원지역 케미 배틀', _kBoth),
    BattleTitlePreset('제주지역 케미 배틀', _kBoth),
  ]),
  BattleTitleCategory('직업', [
    BattleTitlePreset('직장인 케미 배틀', _kBoth),
    BattleTitlePreset('대학생 대학원생 케미 배틀', _kBoth),
    BattleTitlePreset('개발자 케미 배틀', _kBoth),
    BattleTitlePreset('병원에서 일하는 사람들 케미 배틀', _kBoth),
    BattleTitlePreset('선생님들의 케미 배틀', _kBoth),
    BattleTitlePreset('공무원 케미 배틀', _kBoth),
    BattleTitlePreset('자영업 사장님 케미 배틀', _kBoth),
    BattleTitlePreset('프리랜서 케미 배틀', _kBoth),
  ]),
  BattleTitleCategory('MBTI', [
    BattleTitlePreset('E만 모이는 케미 배틀', _kBoth),
    BattleTitlePreset('I만 모이는 케미 배틀', _kBoth),
    BattleTitlePreset('N끼리 모인 케미 배틀', _kBoth),
    BattleTitlePreset('S끼리 모인 케미 배틀', _kBoth),
    BattleTitlePreset('T끼리 모인 케미 배틀', _kBoth),
    BattleTitlePreset('F끼리 모인 케미 배틀', _kBoth),
    BattleTitlePreset('J끼리 모인 케미 배틀', _kBoth),
    BattleTitlePreset('P끼리 모인 케미 배틀', _kBoth),
    BattleTitlePreset('MBTI 대신 관상으로 보는 케미 배틀', _kBoth),
  ]),
  BattleTitleCategory('취미', [
    BattleTitlePreset('천생연분 궁합이면 영화 한 편 같이 본다', _kBoth),
    BattleTitlePreset('천생연분 궁합이면 술 한잔 쏜다', _kBoth),
    BattleTitlePreset('베스트 케미면 커피 한잔 마시러 간다', _kBoth),
    BattleTitlePreset('베스트 케미면 노래방에서 한 곡 부른다', _kBoth),
    BattleTitlePreset('베스트 케미면 맛집 같이 간다', _kBoth),
    BattleTitlePreset('베스트 케미면 전시 보러 간다', _kBoth),
    BattleTitlePreset('베스트 케미면 보드게임 한 판 한다', _kBoth),
    BattleTitlePreset('천생연분 궁합이면 다음 모임 커피는 우리가 산다', _kAllOnly),
  ]),
  BattleTitleCategory('즉석', [
    BattleTitlePreset('오늘 처음 만난 사이 케미 배틀', _kBoth),
    BattleTitlePreset('친구의 친구 케미 배틀', _kBoth),
    BattleTitlePreset('소모임 첫날 케미 배틀', _kBoth),
    BattleTitlePreset('모임 뒤풀이 케미 배틀', _kBoth),
    BattleTitlePreset('번개 모임 케미 배틀', _kBoth),
    BattleTitlePreset('같은 테이블 케미 배틀', _kBoth),
  ]),
  BattleTitleCategory('기타', [], isCustom: true),
];
