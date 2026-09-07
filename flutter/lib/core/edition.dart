import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'hive/hive_setup.dart';

/// 빌드 에디션 = 현재 분석 모드.
///
/// - iOS: `measure`(측정·첫인상 전용) 고정. 관상·궁합 화면 경로를 쓰지 않는다
///   (APPLE.md §81.6).
/// - Android: 두 모드를 다 지원한다 (2026-09-07). 기본은 `full`(관상)이고, 관상
///   탭 앱바의 "관상 | 첫인상" 스위치로 바꾸며 선택은 기기에 저장된다. 카드
///   데이터는 한 종류라 모드를 바꿔도 다시 찍을 것이 없다.
/// - `--dart-define=FACELY_EDITION=measure|full` 을 주면 그 값이 고정된다 —
///   테스트(`flutter test --dart-define=FACELY_EDITION=measure`)와 디버깅용.
///
/// 런타임 판정이므로 관상 코드가 iOS 바이너리에서 빠지지는 않는다. 원격 스위치는
/// 없다.
const String _kEditionDefine =
    String.fromEnvironment('FACELY_EDITION', defaultValue: '');

bool _measure = switch (_kEditionDefine) {
  'measure' => true,
  'full' => false,
  _ => Platform.isIOS,
};

/// true 면 측정·첫인상 전용. 관상·궁합 화면 경로를 쓰지 않는다.
bool get kMeasureEdition => _measure;

/// 사용자가 모드를 바꿀 수 있는가 — Android 이고 컴파일 플래그로 고정되지 않았을 때.
bool get kEditionSwitchable => _kEditionDefine.isEmpty && !Platform.isIOS;

/// 표시용 에디션 이름.
String get kEdition => kMeasureEdition ? 'measure' : 'full';

const String _kPrefKey = 'edition_mode';

/// 앱 시작 때 저장된 선택을 읽는다 (initHive 뒤). 스위치가 없는 빌드는 무시.
void loadEditionPreference() {
  if (!kEditionSwitchable) return;
  final v = Hive.box<String>(HiveBoxes.prefs).get(_kPrefKey);
  if (v == 'measure') _measure = true;
  if (v == 'full') _measure = false;
}

/// 모드를 바꾸고 기기에 저장한다. 화면 갱신은 `editionModeProvider` 가 맡는다.
Future<void> setMeasureEdition(bool measure) async {
  _measure = measure;
  if (Hive.isBoxOpen(HiveBoxes.prefs)) {
    await Hive.box<String>(HiveBoxes.prefs)
        .put(_kPrefKey, measure ? 'measure' : 'full');
  }
}
