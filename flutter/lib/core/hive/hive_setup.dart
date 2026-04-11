import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class HiveBoxes {
  static const String history = 'history';
  static const String auth = 'auth';
  static const String compatibility = 'compatibility';
}

Future<void> initHive() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(HiveBoxes.history);
  await Hive.openBox<String>(HiveBoxes.auth);
  await Hive.openBox<String>(HiveBoxes.compatibility);
}
