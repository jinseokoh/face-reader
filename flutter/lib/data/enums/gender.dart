enum Gender {
  male,
  female,
}

extension GenderLabel on Gender {
  String get labelKo => switch (this) {
        Gender.male => '남자',
        Gender.female => '여자',
      };
}
