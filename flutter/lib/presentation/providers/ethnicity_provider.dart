import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/data/enums/ethnicity.dart';

const _key = 'ethnicity';

final ethnicityProvider =
    NotifierProvider<EthnicityNotifier, Ethnicity?>(EthnicityNotifier.new);

class EthnicityNotifier extends Notifier<Ethnicity?> {
  @override
  Ethnicity? build() {
    final box = Hive.box<String>(HiveBoxes.prefs);
    final name = box.get(_key);
    if (name == null) return null;
    return Ethnicity.values.firstWhere(
      (e) => e.name == name,
      orElse: () => Ethnicity.values.first,
    );
  }

  void select(Ethnicity value) {
    state = value;
    Hive.box<String>(HiveBoxes.prefs).put(_key, value.name);
  }
}
