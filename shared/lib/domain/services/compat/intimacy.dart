/// 性情諧 (intimacy) sub-score — §9.
///
/// Gate: 30~50 대 + opposite gender 만 fire. 그 외는 50 중립 + 섹션 숨김.
///
/// 재료:
/// - 男女宮 · 妻妾宮 state pair delta
/// - lip geometry (lipFullnessRatio · mouthCornerAngle · philtrumLength)
/// - eye charisma (eyeCanthalTilt + yinYang skew)
library;

import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'palace.dart';

class IntimacyComponent {
  final String id;
  final double value;
  final String note;

  const IntimacyComponent({
    required this.id,
    required this.value,
    required this.note,
  });
}

class IntimacyResult {
  final double subScore; // 5~99
  final bool gateActive;
  final List<IntimacyComponent> components;

  const IntimacyResult({
    required this.subScore,
    required this.gateActive,
    required this.components,
  });
}

/// age gate: 30s~50s.
bool _ageInGate(AgeGroup g) =>
    g == AgeGroup.thirties || g == AgeGroup.forties || g == AgeGroup.fifties;

/// gender gate: opposite.
bool _genderOpposite(Gender a, Gender b) => a != b;

double _clamp(double v, double lo, double hi) =>
    v < lo ? lo : (v > hi ? hi : v);

/// 男女宮 pair delta (range ±18).
/// 양방향 비대칭: strong fire 가 template 양성 bias 로 흔하므로 delta 축소,
/// weak fire 는 rare 라 delta 를 확대해 mean 을 50 근방에 유지.
double _mwGongDelta(PalaceState? my, PalaceState? al) {
  if (my == null || al == null) return 0.0;
  if (my.isStrong && al.isStrong) {
    return my.hasFlag(PalaceFlag.plumpLowerEyelid) &&
            al.hasFlag(PalaceFlag.plumpLowerEyelid)
        ? 10
        : 5;
  }
  if (my.isWeak && al.isWeak) {
    return my.hasFlag(PalaceFlag.hollowLowerEyelid) ||
            al.hasFlag(PalaceFlag.hollowLowerEyelid)
        ? -18
        : -14;
  }
  if ((my.isStrong && al.isWeak) || (my.isWeak && al.isStrong)) {
    return 2;
  }
  return 0;
}

/// 妻妾宮 pair delta (range ±18).
double _spouseDelta(PalaceState? my, PalaceState? al) {
  if (my == null || al == null) return 0.0;
  if (my.isStrong && al.isStrong) {
    return my.hasFlag(PalaceFlag.smoothFishTail) &&
            al.hasFlag(PalaceFlag.smoothFishTail)
        ? 12
        : 6;
  }
  if (my.isWeak && al.isWeak) {
    return my.hasFlag(PalaceFlag.fishTailWrinkle) ||
            al.hasFlag(PalaceFlag.fishTailWrinkle)
        ? -18
        : -14;
  }
  if ((my.isStrong && al.isWeak) || (my.isWeak && al.isStrong)) {
    return 3;
  }
  return 0;
}

/// lip geometry delta (range ±14).
double _lipGeometryDelta(
    Map<String, double> myZ, Map<String, double> albumZ) {
  double d = 0.0;
  final myLip = myZ['lipFullnessRatio'] ?? 0.0;
  final alLip = albumZ['lipFullnessRatio'] ?? 0.0;
  final myCorner = myZ['mouthCornerAngle'] ?? 0.0;
  final alCorner = albumZ['mouthCornerAngle'] ?? 0.0;
  final myPhil = myZ['philtrumLength'] ?? 0.0;
  final alPhil = albumZ['philtrumLength'] ?? 0.0;

  // 둘 다 입술 두툼 — 감각적 공명.
  if (myLip >= 0.6 && alLip >= 0.6) d += 4;
  // 둘 다 입술 얇음 — 감각 표현 위축.
  if (myLip <= -0.6 && alLip <= -0.6) d -= 10;
  // 한 쪽 풍성 한 쪽 절제 — 보완.
  if ((myLip >= 0.6 && alLip <= -0.2) || (alLip >= 0.6 && myLip <= -0.2)) {
    d += 2;
  }
  // 웃는 입꼬리 동반.
  if (myCorner >= 0.3 && alCorner >= 0.3) d += 2;
  // 처진 입꼬리 동반.
  if (myCorner <= -0.5 && alCorner <= -0.5) d -= 12;
  // 긴 인중 — 전통적 관능 지표.
  if ((myPhil >= 0.5 || alPhil >= 0.5) && (myPhil + alPhil) / 2 >= 0.3) {
    d += 1;
  }
  return _clamp(d, -14, 14);
}

/// eye charisma delta (range ±10).
double _eyeCharismaDelta(
    Map<String, double> myZ, Map<String, double> albumZ) {
  final myTilt = myZ['eyeCanthalTilt'] ?? 0.0;
  final alTilt = albumZ['eyeCanthalTilt'] ?? 0.0;
  final myFiss = myZ['eyeFissureRatio'] ?? 0.0;
  final alFiss = albumZ['eyeFissureRatio'] ?? 0.0;

  double d = 0.0;
  // 한 쪽 날카로움 × 한 쪽 큰 눈 — 매혹.
  if ((myTilt >= 0.6 && alFiss >= 0.5) || (alTilt >= 0.6 && myFiss >= 0.5)) {
    d += 4;
  }
  // 둘 다 처진 눈 — 무드 다운.
  if (myTilt <= -0.6 && alTilt <= -0.6) d -= 10;
  // 둘 다 큰 눈 — 감수성 공명.
  if (myFiss >= 0.5 && alFiss >= 0.5) d += 2;
  return _clamp(d, -10, 10);
}

IntimacyResult computeIntimacy({
  required Map<String, double> myZ,
  required Map<String, double> albumZ,
  required Map<Palace, PalaceState> myPalaces,
  required Map<Palace, PalaceState> albumPalaces,
  required Gender myGender,
  required Gender albumGender,
  required AgeGroup myAge,
  required AgeGroup albumAge,
}) {
  final gate =
      _ageInGate(myAge) && _ageInGate(albumAge) && _genderOpposite(myGender, albumGender);

  if (!gate) {
    return const IntimacyResult(
      subScore: 50.0,
      gateActive: false,
      components: [],
    );
  }

  final mw = _mwGongDelta(myPalaces[Palace.children], albumPalaces[Palace.children]);
  final sp = _spouseDelta(myPalaces[Palace.spouse], albumPalaces[Palace.spouse]);
  final lip = _lipGeometryDelta(myZ, albumZ);
  final eye = _eyeCharismaDelta(myZ, albumZ);

  final total = 50 + mw + sp + lip + eye;
  final sub = total.clamp(5.0, 99.0);

  return IntimacyResult(
    subScore: sub,
    gateActive: true,
    components: [
      IntimacyComponent(id: 'mwGong', value: mw, note: '男女宮 pair'),
      IntimacyComponent(id: 'spouse', value: sp, note: '妻妾宮 pair'),
      IntimacyComponent(id: 'lip', value: lip, note: 'lip geometry'),
      IntimacyComponent(id: 'eye', value: eye, note: 'eye charisma'),
    ],
  );
}
