import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:face_reader/data/enums/gender.dart';

final genderProvider =
    NotifierProvider<GenderNotifier, Gender>(GenderNotifier.new);

class GenderNotifier extends Notifier<Gender> {
  @override
  Gender build() => Gender.male;

  void select(Gender value) => state = value;
}
