// 동기화가 사진을 잃지 않는다 — 회귀 테스트.
//
// 예전에는 카드가 사진을 두 곳(로컬 파일 경로 / R2 키)으로 가리켰고, 당김
// 동기화가 서버 카드로 교체할 때 "둘 중 뭐가 진실이냐" 를 키 비교로 판정했다.
// 그 판정이 어긋나면 로컬 경로가 지워져 아바타가 아이콘으로 떨어졌다.
//
// 지금 사진의 필드는 thumbnailKey 하나이고 로컬 캐시 파일명은 그 키에서
// 파생된다. 서버 body 가 키를 싣고 다니므로, 카드를 서버 것으로 통째 교체해도
// 같은 파일을 찾는다 — 그것을 여기서 못박는다.

import 'dart:convert';
import 'dart:typed_data';

import 'package:face_engine/data/constants/face_reference_data.dart';
import 'package:face_engine/data/enums/age_group.dart';
import 'package:face_engine/data/enums/attribute.dart';
import 'package:face_engine/data/enums/ethnicity.dart';
import 'package:face_engine/data/enums/face_shape.dart';
import 'package:face_engine/data/enums/gender.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';
import 'package:face_engine/domain/services/archetype.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/data/services/supabase_service.dart';
import 'package:flutter_test/flutter_test.dart';

FaceReadingReport _report({String? thumbnailKey}) {
  final refs = referenceData[Ethnicity.eastAsian]![Gender.female]!;
  final metrics = <String, MetricResult>{};
  for (final info in metricInfoList) {
    final ref = refs[info.id]!;
    metrics[info.id] = MetricResult(
      id: info.id,
      rawValue: ref.mean,
      zScore: 0.0,
      zAdjusted: 0.0,
      metricScore: 0,
    );
  }
  return FaceReadingReport(
    ethnicity: Ethnicity.eastAsian,
    gender: Gender.female,
    ageGroup: AgeGroup.thirties,
    metrics: metrics,
    nodeScores: const {},
    attributes: const {},
    rules: const [],
    archetype: const ArchetypeResult(
      primary: Attribute.wealth,
      secondary: Attribute.leadership,
      primaryLabel: '사업가형',
      secondaryLabel: '리더형',
    ),
    faceShape: FaceShape.oval,
    timestamp: DateTime(2026, 8, 22),
    source: AnalysisSource.camera,
    supabaseId: 'row-1',
    thumbnailKey: thumbnailKey,
  );
}

void main() {
  group('서버 카드로 교체돼도 사진을 잃지 않는다', () {
    test('body 왕복 후에도 같은 캐시 파일을 가리킨다', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final key = ThumbnailPaths.contentKey(bytes, owner: 'u1');
      final local = _report(thumbnailKey: key);

      // 서버가 들고 있는 것은 body 뿐이고, 당김 동기화는 그 body 로 카드를
      // 다시 만든다 (history_provider._reportFromRow 와 같은 경로).
      final fresh = FaceReadingReport.fromJsonString(local.toBodyJson());

      expect(fresh.thumbnailKey, key);
      expect(
        ThumbnailPaths.fileNameForKey(fresh.thumbnailKey!),
        ThumbnailPaths.fileNameForKey(key),
      );
    });

    test('Hive 왕복도 키를 보존한다', () {
      final key = ThumbnailPaths.contentKey(Uint8List.fromList([4, 5, 6]), owner: 'u1');
      final again = FaceReadingReport.fromJsonString(
        _report(thumbnailKey: key).toJsonString(),
      );

      expect(again.thumbnailKey, key);
    });

    test('키가 없으면 볼 캐시도 없다 — 폴백 아이콘이 정상 동작', () {
      expect(ThumbnailPaths.cacheFileSync(null), isNull);
    });
  });

  group('saveMetrics 가 서버에 실을 body', () {
    test('썸네일 키를 옛 키로 갈아끼워도 report 는 그대로다', () {
      final report = _report();
      final body = jsonDecode(
        SupabaseService.bodyWithThumbnailKey(report, 'thumbnails/ab/old.jpg'),
      ) as Map<String, dynamic>;

      expect(body['thumbnailKey'], 'thumbnails/ab/old.jpg');
      // Hive 에 이미 저장된 객체 — 여기서 바뀌면 메모리와 Hive 가 갈린다.
      expect(report.thumbnailKey, isNull);
    });

    test('키가 그대로면 body 도 그대로다', () {
      const key = 'thumbnails/ab/abc.jpg';
      final body = jsonDecode(
        SupabaseService.bodyWithThumbnailKey(_report(thumbnailKey: key), key),
      ) as Map<String, dynamic>;

      expect(body['thumbnailKey'], key);
    });
  });
}
