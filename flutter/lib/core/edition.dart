/// 빌드 에디션 — 컴파일 상수.
///
/// iOS 는 `--dart-define=FACELY_EDITION=measure`, Android 는 기본값 `full`.
/// 관상 서술·관상 쌍 엔진·관상 케미 방 경로는 [kMeasureEdition] 상수 분기 뒤에
/// 두어 iOS release 빌드에서 tree-shake 로 사라진다. 원격 설정이나 런타임
/// 플래그로 숨기지 않는다 (App Review 2.3.1). 근거: APPLE.md §81.6.
const String kEdition =
    String.fromEnvironment('FACELY_EDITION', defaultValue: 'full');

/// true 면 측정·첫인상 전용 빌드(iOS v1). 관상 경로가 빌드에 없다.
const bool kMeasureEdition = kEdition == 'measure';
