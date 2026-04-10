import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class HiveBoxes {
  static const String history = 'history';
}

Future<void> initHive() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(HiveBoxes.history);
}
