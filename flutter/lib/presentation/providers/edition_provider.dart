import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/edition.dart';

/// 현재 분석 모드 (true = 첫인상/measure). `kMeasureEdition` 을 화면이 구독할 수
/// 있게 감싼 것 — 값이 바뀌면 MainApp 이 탭 셸 전체를 다시 그린다.
final editionModeProvider =
    NotifierProvider<EditionModeNotifier, bool>(EditionModeNotifier.new);

class EditionModeNotifier extends Notifier<bool> {
  @override
  bool build() => kMeasureEdition;

  Future<void> switchTo({required bool measure}) async {
    if (measure == state) return;
    await setMeasureEdition(measure);
    state = measure;
  }
}
