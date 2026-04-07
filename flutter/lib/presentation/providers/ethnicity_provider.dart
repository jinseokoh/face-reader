import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:face_reader/data/enums/ethnicity.dart';

final ethnicityProvider =
    NotifierProvider<EthnicityNotifier, Ethnicity>(EthnicityNotifier.new);

class EthnicityNotifier extends Notifier<Ethnicity> {
  @override
  Ethnicity build() => Ethnicity.eastAsian;

  void select(Ethnicity value) => state = value;
}
