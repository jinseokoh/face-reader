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

extension AgeGroupCategory on AgeGroup {
  bool get isOver50 => index >= 4; // fifties(4) ~ nineties(8)
  bool get isOver20 => index >= 1; // twenties(1) ~
  bool get isOver30 => index >= 2; // thirties(2) ~
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

/// 두 포맷 모두 accept — 새 decade 라벨 + legacy enum 이름.
/// v6 이전에 저장된 Hive·Supabase 행이 `"twenties"` 형태라 backward compat 필요.
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
