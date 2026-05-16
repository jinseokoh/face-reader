/// Result of the DeepFace age/gender/race inference pipeline.
///
/// `thumbnailUrl` is null until the post-analyze 256×256 thumbnail upload
/// completes (orphan-zero strategy: thumbnail is only uploaded if analysis
/// succeeds, so until then the UI must show a gender-based fallback).
class FaceMetadata {
  final int age;
  final String gender; // "Man" | "Woman" (직접 enum 으로 매핑하지 않음 — API SSOT 그대로)
  final String race; // "asian" | "white" | "black" | "indian" | "middle eastern" | "latino hispanic"
  final String? thumbnailUrl;

  const FaceMetadata({
    required this.age,
    required this.gender,
    required this.race,
    this.thumbnailUrl,
  });

  FaceMetadata copyWith({String? thumbnailUrl}) => FaceMetadata(
        age: age,
        gender: gender,
        race: race,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      );

  factory FaceMetadata.fromJson(Map<String, dynamic> j) => FaceMetadata(
        age: (j['age'] as num).toInt(),
        gender: j['gender'] as String,
        race: j['race'] as String,
      );

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'race': race,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      };
}
