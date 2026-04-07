import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';

abstract class MetaphorLocalDataSource {
  String? get(String key);
  Future<void> save(String key, String value);
}

class MetaphorLocalDataSourceImpl implements MetaphorLocalDataSource {
  Box<String> get _box => Hive.box<String>(HiveBoxes.metaphorCache);

  @override
  String? get(String key) => _box.get(key);

  @override
  Future<void> save(String key, String value) => _box.put(key, value);
}
