import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/data/enums/age_group.dart';

const _key = 'ageGroup';

final ageGroupProvider =
    NotifierProvider<AgeGroupNotifier, AgeGroup?>(AgeGroupNotifier.new);

class AgeGroupNotifier extends Notifier<AgeGroup?> {
  @override
  AgeGroup? build() {
    final box = Hive.box<String>(HiveBoxes.prefs);
    final name = box.get(_key);
    if (name == null) return null;
    return AgeGroup.values.firstWhere(
      (e) => e.name == name,
      orElse: () => AgeGroup.values.first,
    );
  }

  void select(AgeGroup value) {
    state = value;
    Hive.box<String>(HiveBoxes.prefs).put(_key, value.name);
  }
}
