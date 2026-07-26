import 'package:facely/domain/models/team.dart';

const List<TeamTitleCategory> kTeamTitleCatalog = [
  TeamTitleCategory('취미', [
    TeamTitlePreset('천생연분 궁합이면 전시회 한번 같이 가요.', _kBoth),
    TeamTitlePreset('천생연분 궁합이면 영화 한편 같이 봐요.', _kBoth),
    TeamTitlePreset('천생연분 궁합이면 식사 한번 같이해요.', _kBoth),
    TeamTitlePreset('천생연분 궁합이면 커피 한잔 같이해요.', _kBoth),
    TeamTitlePreset('천생연분 궁합이면 술 한잔 같이해요.', _kBoth),
  ]),
  TeamTitleCategory('즉석', [
    TeamTitlePreset('케미, 그것이 알고 싶다', _kBoth),
    TeamTitlePreset('나는 케미 솔로', _kBoth),
    TeamTitlePreset('무한 케미 도전', _kBoth),
    TeamTitlePreset('한국인의 케미 밥상', _kBoth),
    TeamTitlePreset('나는 케미 자연인이다', _kBoth),
    TeamTitlePreset('나 혼자 케미보며 산다', _kBoth),
    TeamTitlePreset('놀면 뭐하니 케미나 봐라', _kBoth),
    TeamTitlePreset('전지적 케미 참견 시점', _kBoth),
    TeamTitlePreset('전국 케미 자랑', _kBoth),
    TeamTitlePreset('세상에 이런 케미들이', _kBoth),
  ]),
  TeamTitleCategory('MBTI', [
    TeamTitlePreset('MBTI E끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI I끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI N끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI S끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI T끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI F끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI J끼리 모이는 자리', _kBoth),
    TeamTitlePreset('MBTI P끼리 모이는 자리', _kBoth),
  ]),
  TeamTitleCategory('직업', [
    TeamTitlePreset('대학생끼리', _kBoth),
    TeamTitlePreset('대학원생끼리', _kBoth),
    TeamTitlePreset('대기업 직장인끼리', _kBoth),
    TeamTitlePreset('좋소기업 직장인끼리', _kBoth),
    TeamTitlePreset('공무원끼리', _kBoth),
    TeamTitlePreset('자영업끼리', _kBoth),
    TeamTitlePreset('선생님끼리', _kBoth),
    TeamTitlePreset('의료인끼리', _kBoth),
    TeamTitlePreset('예술가끼리', _kBoth),
    TeamTitlePreset('전문직끼리', _kBoth),
  ]),
  TeamTitleCategory('지역', [
    TeamTitlePreset('서울지역', _kBoth),
    TeamTitlePreset('경기 인천', _kBoth),
    TeamTitlePreset('부산 경남', _kBoth),
    TeamTitlePreset('대구 경북', _kBoth),
    TeamTitlePreset('대전 충청', _kBoth),
    TeamTitlePreset('광주 전라', _kBoth),
    TeamTitlePreset('강원지역', _kBoth),
    TeamTitlePreset('제주지역', _kBoth),
  ]),
  TeamTitleCategory('기타', [], isCustom: true),
];

const _kBoth = {TeamRoomKind.all, TeamRoomKind.match};
class TeamTitleCategory {
  final String name;
  final List<TeamTitlePreset> titles;

  /// true 면 프리셋 리스트 대신 자유 입력 필드를 보여준다 (기타 전용).
  final bool isCustom;

  const TeamTitleCategory(this.name, this.titles, {this.isCustom = false});
}

/// 방 제목 프리셋 카탈로그 — 6 카테고리(지역/직업/MBTI/취미/즉석/기타).
/// 기타는 프리셋 없이 자유 입력([TeamTitleCategory.isCustom]). 서버에는
/// 확정된 title 문자열만 저장된다(카테고리는 클라이언트 UI 전용, 서버 컬럼 없음).
class TeamTitlePreset {
  final String title;
  final Set<TeamRoomKind> allowedKinds;

  const TeamTitlePreset(this.title, this.allowedKinds);
}
