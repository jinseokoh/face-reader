import 'dart:convert';

class CompatibilityResult {
  final String myFaceTimestamp;
  final String albumTimestamp;
  final DateTime evaluatedAt;
  final double score;
  final String summary;

  CompatibilityResult({
    required this.myFaceTimestamp,
    required this.albumTimestamp,
    required this.evaluatedAt,
    required this.score,
    required this.summary,
  });

  /// Key for Hive storage: combines both timestamps
  String get key => '${myFaceTimestamp}_$albumTimestamp';

  String toJsonString() => jsonEncode({
        'myFaceTimestamp': myFaceTimestamp,
        'albumTimestamp': albumTimestamp,
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'score': score,
        'summary': summary,
      });

  factory CompatibilityResult.fromJsonString(String jsonStr) {
    final j = jsonDecode(jsonStr) as Map<String, dynamic>;
    return CompatibilityResult(
      myFaceTimestamp: j['myFaceTimestamp'] as String,
      albumTimestamp: j['albumTimestamp'] as String,
      evaluatedAt: DateTime.parse(j['evaluatedAt'] as String),
      score: (j['score'] as num).toDouble(),
      summary: j['summary'] as String,
    );
  }
}
