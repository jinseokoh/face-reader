import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:face_reader/data/enums/age_group.dart';

final ageGroupProvider =
    NotifierProvider<AgeGroupNotifier, AgeGroup>(AgeGroupNotifier.new);

class AgeGroupNotifier extends Notifier<AgeGroup> {
  @override
  AgeGroup build() => AgeGroup.twenties;

  void select(AgeGroup value) => state = value;
}
