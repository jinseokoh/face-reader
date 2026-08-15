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
        Attribute.wealth => 'Financial Strength',
        Attribute.leadership => 'Leadership',
        Attribute.intelligence => 'Intelligence',
        Attribute.sociability => 'Sociability',
        Attribute.emotionality => 'Emotionality',
        Attribute.stability => 'Stability',
        Attribute.sensuality => 'Magnetism',
        Attribute.trustworthiness => 'Trustworthiness',
        Attribute.attractiveness => 'Attractiveness',
        Attribute.libido => 'Vitality',
      };

  String get labelKo => switch (this) {
        Attribute.wealth => '재력',
        Attribute.leadership => '리더십',
        Attribute.intelligence => '통찰력',
        Attribute.sociability => '사회성',
        Attribute.emotionality => '감정성',
        Attribute.stability => '안정성',
        Attribute.sensuality => '흡인력',
        Attribute.trustworthiness => '신뢰성',
        Attribute.attractiveness => '매력도',
        Attribute.libido => '활력',
      };
}
