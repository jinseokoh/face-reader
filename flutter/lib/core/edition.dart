import 'dart:io';


/// 빌드 에디션.
///
/// 기본은 **플랫폼으로 자동 결정** — iOS = `measure`(측정·첫인상 전용, 관상 경로를
/// 화면에서 쓰지 않음), Android = `full`. 그래서 `flutter run --release` 만으로
/// 양쪽이 맞는 화면을 낸다 (APPLE.md §81.6, 2026-09-06 B안).
///
/// `--dart-define=FACELY_EDITION=measure|full` 을 주면 그 값이 우선한다 —
/// 테스트(`flutter test --dart-define=FACELY_EDITION=measure`)와 디버깅용.
///
/// 런타임 판정이므로 관상 코드가 iOS 바이너리에서 빠지지는 않는다. 다만 이 값을
/// 바꾸는 원격 스위치·런타임 플래그는 없다 — 플랫폼과 컴파일 플래그뿐이다.
const String _kEditionDefine =
    String.fromEnvironment('FACELY_EDITION', defaultValue: '');

/// true 면 측정·첫인상 전용(iOS). 관상·궁합 화면 경로를 쓰지 않는다.
final bool kMeasureEdition = switch (_kEditionDefine) {
  'measure' => true,
  'full' => false,
  _ => Platform.isIOS,
};

/// 표시용 에디션 이름.
String get kEdition => kMeasureEdition ? 'measure' : 'full';

