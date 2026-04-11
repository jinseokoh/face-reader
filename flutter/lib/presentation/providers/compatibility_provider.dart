import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/domain/models/compatibility_result.dart';

final compatibilityProvider =
    NotifierProvider<CompatibilityNotifier, Map<String, CompatibilityResult>>(
  CompatibilityNotifier.new,
);

class CompatibilityNotifier
    extends Notifier<Map<String, CompatibilityResult>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.compatibility);

  @override
  Map<String, CompatibilityResult> build() {
    return _loadFromHive();
  }

  void add(CompatibilityResult result) {
    state = {...state, result.key: result};
    _saveToHive();
  }

  CompatibilityResult? get(String myFaceTimestamp, String albumTimestamp) {
    return state['${myFaceTimestamp}_$albumTimestamp'];
  }

  Map<String, CompatibilityResult> _loadFromHive() {
    final results = <String, CompatibilityResult>{};
    for (int i = 0; i < _box.length; i++) {
      final json = _box.getAt(i);
      if (json != null) {
        try {
          final result = CompatibilityResult.fromJsonString(json);
          results[result.key] = result;
        } catch (e) {
          debugPrint('[Compatibility] failed to parse entry $i: $e');
        }
      }
    }
    return results;
  }

  void _saveToHive() {
    _box.clear();
    for (final result in state.values) {
      _box.add(result.toJsonString());
    }
  }
}
