import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';

/// Set of album report UUIDs that the user has explicitly added to the
/// compatibility list. Compat is purely opt-in: a new album report does
/// NOT auto-appear in 궁합 tab. The user must long-press the album row
/// and tap "궁합 보기" to bring it in.
///
/// When an album is deleted from history, its uuid is also removed here
/// (orphan prevention).
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
