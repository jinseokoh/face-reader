import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/gender.dart';

/// Result of the DeepFace age/gender/ethnicity inference pipeline.
///
/// `uuid` is the **single capture id** generated once at analyze time and
/// reused across the entire face lifecycle:
///   - `temp/{uuid}.jpg`              (analyze 입력, 즉시 삭제)
///   - `thumbnails/{YYYYMM}/{uuid}.jpg` (영구 256 PNG)
///   - `FaceReadingReport.supabaseId`  (caller 가 즉시 assign)
///   - `metrics.id` (Supabase row PK)
///   - `https://facely.kr/r/{uuid}`    (share link)
///
/// 즉 "한 얼굴 캡처 = 한 UUID". 로그 grep + incident response 시 단일 trace id
/// 로 묶기 위함. Caller 는 [analyze] 가 반환한 객체의 `uuid` 를 반드시
/// `report.supabaseId` 에 흘려넣어야 한다 (saveMetrics 의 fallback v4 가
/// 발동하는 경로는 analyze 미경유 케이스 한정).
///
/// `thumbnailUrl` is null until the post-analyze 256×256 thumbnail upload
/// completes (orphan-zero strategy: thumbnail is only uploaded if analysis
/// succeeds, so until then the UI must show a gender-based fallback).
class FaceMetadata {
  final String uuid;
  final int age;
  // "male" | "female" — Python /analyze 응답에서 Flutter Gender enum name 으로
  // 정규화된 값. 그대로 `Gender.values.byName(...)` 로 매핑 가능.
  final String gender;
  // "eastAsian" | "caucasian" | "african" | "southeastAsian" | "hispanic" |
  // "middleEastern" — Python /analyze 응답에서 Flutter Ethnicity enum name 으로
  // 정규화된 값. 그대로 `Ethnicity.values.byName(...)` 로 매핑 가능.
  final String ethnicity;
  final String? thumbnailUrl;

  const FaceMetadata({
    required this.uuid,
    required this.age,
    required this.gender,
    required this.ethnicity,
    this.thumbnailUrl,
  });

  FaceMetadata copyWith({String? thumbnailUrl}) => FaceMetadata(
        uuid: uuid,
        age: age,
        gender: gender,
        ethnicity: ethnicity,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      );

  /// Python `/analyze` 응답엔 uuid 가 없다 (서버는 모름). 호출자가 client-side
  /// 에서 발급한 uuid 를 그대로 주입해야 한다.
  factory FaceMetadata.fromJson(
    Map<String, dynamic> j, {
    required String uuid,
  }) =>
      FaceMetadata(
        uuid: uuid,
        age: (j['age'] as num).toInt(),
        gender: j['gender'] as String,
        ethnicity: j['ethnicity'] as String,
      );

  Map<String, dynamic> toJson() => {
        'uuid': uuid,
        'age': age,
        'gender': gender,
        'ethnicity': ethnicity,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      };

  /// DeepFace `gender` 문자열을 [Gender] enum 으로. 알 수 없으면 null.
  Gender? get genderEnum {
    try {
      return Gender.values.byName(gender);
    } catch (_) {
      return null;
    }
  }

  /// DeepFace `ethnicity` 문자열을 [Ethnicity] enum 으로. 알 수 없으면 null.
  Ethnicity? get ethnicityEnum {
    try {
      return Ethnicity.values.byName(ethnicity);
    } catch (_) {
      return null;
    }
  }

  /// DeepFace `age` (int) 를 decade-banded [AgeGroup] 으로 매핑.
  /// 0~9 → teens, 10~19 → teens, 20~29 → twenties, … 90+ → nineties.
  AgeGroup get ageGroupEnum {
    if (age < 20) return AgeGroup.teens;
    if (age < 30) return AgeGroup.twenties;
    if (age < 40) return AgeGroup.thirties;
    if (age < 50) return AgeGroup.forties;
    if (age < 60) return AgeGroup.fifties;
    if (age < 70) return AgeGroup.sixties;
    if (age < 80) return AgeGroup.seventies;
    if (age < 90) return AgeGroup.eighties;
    return AgeGroup.nineties;
  }
}
