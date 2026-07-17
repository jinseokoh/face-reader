import 'package:hive_ce_flutter/hive_ce_flutter.dart';

class HiveBoxes {
  static const String history = 'history';
  static const String auth = 'auth';

  /// 앱 단위 flag 저장소 (온보딩 노출 여부 등).
  static const String prefs = 'prefs';
}

Future<void> initHive() async {
  await Hive.initFlutter();
  await Hive.openBox<String>(HiveBoxes.history);
  await Hive.openBox<String>(HiveBoxes.auth);
  await Hive.openBox<String>(HiveBoxes.prefs);
}
