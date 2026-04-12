import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';

/// Set of report UUIDs (album OR camera selfie) that the user has explicitly
/// added to the compatibility list. Compat is purely opt-in: a new report
/// does NOT auto-appear in 궁합 tab. The user must long-press the row in
/// 관상 탭 (카메라 또는 앨범) and tap "궁합 보기" to bring it in.
///
/// When a report is deleted from history, its uuid is also removed here
/// (orphan prevention) — regardless of source.
///
/// Note: 내 얼굴 자체는 페어링 불가이므로 이 set에 들어가지 않는다.
/// (관상 화면의 옵션 게이팅에서 막힘.)
final compatAlbumsProvider =
    NotifierProvider<CompatAlbumsNotifier, Set<String>>(
  CompatAlbumsNotifier.new,
);

class CompatAlbumsNotifier extends Notifier<Set<String>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.compatAlbums);

  @override
  Set<String> build() {
    return _box.values.toSet();
  }

  bool contains(String albumUuid) => state.contains(albumUuid);

  Future<void> add(String albumUuid) async {
    if (state.contains(albumUuid)) return;
    state = {...state, albumUuid};
    await _box.add(albumUuid);
  }

  Future<void> remove(String albumUuid) async {
    if (!state.contains(albumUuid)) return;
    final next = {...state}..remove(albumUuid);
    state = next;
    // Hive Box has no key for individual entries here; rebuild the box.
    await _box.clear();
    for (final v in next) {
      await _box.add(v);
    }
  }
}
