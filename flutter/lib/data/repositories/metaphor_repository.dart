import 'dart:convert';
import 'package:crypto/crypto.dart';

import 'package:face_reader/data/datasources/local/metaphor_local_datasource.dart';
import 'package:face_reader/data/datasources/remote/metaphor_remote_datasource.dart';
import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';
import 'package:face_reader/domain/services/report_assembler.dart';

class MetaphorRepository {
  final MetaphorRemoteDataSource remoteDataSource;
  final MetaphorLocalDataSource localDataSource;

  MetaphorRepository({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  String _cacheKey(FaceReadingReport report) {
    final parts = report.metrics.entries
        .map((e) => '${e.key}:${e.value.zScore.toStringAsFixed(2)}')
        .join('|');
    final raw =
        '${report.ethnicity.name}|${report.gender.name}|${report.ageGroup.name}|$parts';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  Future<String> getMetaphor(FaceReadingReport report) async {
    final key = _cacheKey(report);

    final cached = localDataSource.get(key);
    if (cached != null) return cached;

    final assembled = assembleReport(report);

    final dto = {
      // ─── 대상 정보 ───
      'gender': report.gender.name,
      'genderKo': report.gender.labelKo,
      'ageGroup': report.ageGroup.name,
      'ageGroupKo': report.ageGroup.labelKo,
      'isOver50': report.ageGroup.isOver50,
      'ethnicity': report.ethnicity.name,
      'ethnicityKo': report.ethnicity.labelKo,

      // ─── Archetype ───
      'archetype': {
        'primary': report.archetype.primaryLabel,
        'secondary': report.archetype.secondaryLabel,
        'special': report.archetype.specialArchetype,
      },

      // ─── 조립된 분석 블록 (LLM 래핑 핵심 입력) ───
      'assembledBlocks': assembled.assembledText,

      // ─── 15 Metrics (raw + z + adjusted + score) ───
      'metrics': report.metrics.entries
          .map((e) => {
                'id': e.key,
                'rawValue': e.value.rawValue,
                'zScore': e.value.zScore,
                'zAdjusted': e.value.zAdjusted,
                'metricScore': e.value.metricScore,
              })
          .toList(),

      // ─── 10 Attribute Scores (0~10) ───
      'attributeScores':
          report.attributeScores.map((k, v) => MapEntry(k.name, v)),

      // ─── 발동된 Rules ───
      'triggeredRules': report.triggeredRules
          .map((r) => {
                'id': r.id,
                'effects':
                    r.effects.map((k, v) => MapEntry(k.name, v)),
              })
          .toList(),
    };

    final text = await remoteDataSource.fetchMetaphor(dto);
    await localDataSource.save(key, text);
    return text;
  }
}
