enum Ethnicity {
  eastAsian,
  caucasian,
  african,
  southeastAsian,
  hispanic,
  middleEastern,
}

extension EthnicityLabel on Ethnicity {
  String get labelKo => switch (this) {
        Ethnicity.eastAsian => '동아시아인',
        Ethnicity.caucasian => '백인',
        Ethnicity.african => '아프리카인',
        Ethnicity.southeastAsian => '동남아시아인',
        Ethnicity.hispanic => '히스패닉',
        Ethnicity.middleEastern => '중동인',
      };
}
