import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class HiveBoxes {
  static const String settings = 'settings';
  static const String history = 'history';
  static const String metaphorCache = 'metaphor_cache';
}

Future<void> initHive() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(HiveBoxes.settings);
  await Hive.openBox<String>(HiveBoxes.history);
  await Hive.openBox<String>(HiveBoxes.metaphorCache);
}
