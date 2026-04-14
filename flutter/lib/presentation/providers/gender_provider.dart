import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/data/enums/gender.dart';

const _key = 'gender';

final genderProvider =
    NotifierProvider<GenderNotifier, Gender?>(GenderNotifier.new);

class GenderNotifier extends Notifier<Gender?> {
  @override
  Gender? build() {
    final box = Hive.box<String>(HiveBoxes.prefs);
    final name = box.get(_key);
    if (name == null) return null;
    return Gender.values.firstWhere(
      (e) => e.name == name,
      orElse: () => Gender.values.first,
    );
  }

  void select(Gender value) {
    state = value;
    Hive.box<String>(HiveBoxes.prefs).put(_key, value.name);
  }
}
