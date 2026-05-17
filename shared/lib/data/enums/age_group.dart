enum AgeGroup {
  teens,
  twenties,
  thirties,
  forties,
  fifties,
  sixties,
  seventies,
  eighties,
  nineties,
}

abstract final class AgeGroupParser {
  static AgeGroup fromJsonValue(String s) {
    switch (s) {
      case '10s':
        return AgeGroup.teens;
      case '20s':
        return AgeGroup.twenties;
      case '30s':
        return AgeGroup.thirties;
      case '40s':
        return AgeGroup.forties;
      case '50s':
        return AgeGroup.fifties;
      case '60s':
        return AgeGroup.sixties;
      case '70s':
        return AgeGroup.seventies;
      case '80s':
        return AgeGroup.eighties;
      case '90s':
        return AgeGroup.nineties;
    }
    // legacy: enum 이름 (e.g. "twenties")
    return AgeGroup.values.byName(s);
  }
}

extension AgeGroupCategory on AgeGroup {
  bool get isOver20 => index >= 1; // twenties(1) ~
  bool get isOver30 => index >= 2; // thirties(2) ~
  bool get isOver40 => index >= 3; // forties(3) ~
  bool get isOver50 => index >= 4; // fifties(4) ~ nineties(8)
  bool get isOver60 => index >= 5; // sixties(5) ~

  /// Stage 5 age rule 발동을 위한 3-band 분류.
  /// young: 10대~20대 (잠재·기반)
  /// mid:   30대~40대 (정점·실행)
  /// late:  50대 이상 (회수·전수)
  AgeBand get band {
    if (isOver50) return AgeBand.late;
    if (isOver30) return AgeBand.mid;
    return AgeBand.young;
  }
}

enum AgeBand { young, mid, late }

/// JSON 직렬화 — decade 라벨 (`"10s".."90s"`). Dart enum 이름(`twenties` 등)
/// 대신 사용. Worker·Supabase·Flutter Hive 모두 이 포맷 SSOT.
extension AgeGroupJson on AgeGroup {
  String get jsonValue => switch (this) {
        AgeGroup.teens => '10s',
        AgeGroup.twenties => '20s',
        AgeGroup.thirties => '30s',
        AgeGroup.forties => '40s',
        AgeGroup.fifties => '50s',
        AgeGroup.sixties => '60s',
        AgeGroup.seventies => '70s',
        AgeGroup.eighties => '80s',
        AgeGroup.nineties => '90s',
      };
}

extension AgeGroupLabel on AgeGroup {
  String get labelKo => switch (this) {
        AgeGroup.teens => '10대',
        AgeGroup.twenties => '20대',
        AgeGroup.thirties => '30대',
        AgeGroup.forties => '40대',
        AgeGroup.fifties => '50대',
        AgeGroup.sixties => '60대',
        AgeGroup.seventies => '70대',
        AgeGroup.eighties => '80대',
        AgeGroup.nineties => '90대',
      };
}
