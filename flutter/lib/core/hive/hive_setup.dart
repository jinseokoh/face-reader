import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class HiveBoxes {
  static const String history = 'history';
  static const String auth = 'auth';
  static const String compatAlbums = 'compat_albums';
  static const String prefs = 'prefs';
}

Future<void> initHive() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(HiveBoxes.history);
  await Hive.openBox<String>(HiveBoxes.auth);
  await Hive.openBox<String>(HiveBoxes.compatAlbums);
  await Hive.openBox<String>(HiveBoxes.prefs);
}
