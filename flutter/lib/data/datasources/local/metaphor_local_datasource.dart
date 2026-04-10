abstract class MetaphorLocalDataSource {
  String? get(String key);
  Future<void> save(String key, String value);
}

class MetaphorLocalDataSourceImpl implements MetaphorLocalDataSource {
  final Map<String, String> _cache = {};

  @override
  String? get(String key) => _cache[key];

  @override
  Future<void> save(String key, String value) async {
    _cache[key] = value;
  }
}
