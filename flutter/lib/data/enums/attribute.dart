enum Attribute {
  wealth,
  leadership,
  intelligence,
  sociability,
  emotionality,
  stability,
  sensuality,
  trustworthiness,
  attractiveness,
  libido,
}

extension AttributeLabel on Attribute {
  String get labelEn => switch (this) {
        Attribute.wealth => 'Wealth Fortune',
        Attribute.leadership => 'Leadership',
        Attribute.intelligence => 'Intelligence',
        Attribute.sociability => 'Sociability',
        Attribute.emotionality => 'Emotionality',
        Attribute.stability => 'Stability',
        Attribute.sensuality => 'Sensuality',
        Attribute.trustworthiness => 'Trustworthiness',
        Attribute.attractiveness => 'Attractiveness',
        Attribute.libido => 'Sexual Energy',
      };

  String get labelKo => switch (this) {
        Attribute.wealth => '재물운',
        Attribute.leadership => '리더십',
        Attribute.intelligence => '지능/통찰',
        Attribute.sociability => '사회성',
        Attribute.emotionality => '감정성',
        Attribute.stability => '안정성',
        Attribute.sensuality => '바람기',
        Attribute.trustworthiness => '신뢰성',
        Attribute.attractiveness => '매력',
        Attribute.libido => '관능 에너지',
      };
}
