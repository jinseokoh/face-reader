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
