import 'dart:convert';

class CompatibilityResult {
  final String myFaceTimestamp;
  final String albumTimestamp;
  final DateTime evaluatedAt;
  final double score;
  final String summary;
  final Map<String, double> categoryScores;
  final double archetypeScore;
  final String? specialNote;
  final String myArchetype;
  final String albumArchetype;

  CompatibilityResult({
    required this.myFaceTimestamp,
    required this.albumTimestamp,
    required this.evaluatedAt,
    required this.score,
    required this.summary,
    required this.categoryScores,
    required this.archetypeScore,
    this.specialNote,
    required this.myArchetype,
    required this.albumArchetype,
  });

  /// Key for Hive storage: combines both timestamps
  String get key => '${myFaceTimestamp}_$albumTimestamp';

  String toJsonString() => jsonEncode({
        'myFaceTimestamp': myFaceTimestamp,
        'albumTimestamp': albumTimestamp,
        'evaluatedAt': evaluatedAt.toIso8601String(),
        'score': score,
        'summary': summary,
        'categoryScores': categoryScores,
        'archetypeScore': archetypeScore,
        'specialNote': specialNote,
        'myArchetype': myArchetype,
        'albumArchetype': albumArchetype,
      });

  factory CompatibilityResult.fromJsonString(String jsonStr) {
    final j = jsonDecode(jsonStr) as Map<String, dynamic>;
    final rawCategoryScores = j['categoryScores'] as Map<String, dynamic>? ?? {};
    return CompatibilityResult(
      myFaceTimestamp: j['myFaceTimestamp'] as String,
      albumTimestamp: j['albumTimestamp'] as String,
      evaluatedAt: DateTime.parse(j['evaluatedAt'] as String),
      score: (j['score'] as num).toDouble(),
      summary: j['summary'] as String,
      categoryScores: rawCategoryScores.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      ),
      archetypeScore: (j['archetypeScore'] as num).toDouble(),
      specialNote: j['specialNote'] as String?,
      myArchetype: j['myArchetype'] as String,
      albumArchetype: j['albumArchetype'] as String,
    );
  }
}
