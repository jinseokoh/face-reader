import 'package:face_reader/data/enums/age_group.dart';
import 'package:face_reader/data/enums/attribute.dart';
import 'package:face_reader/data/enums/ethnicity.dart';
import 'package:face_reader/data/enums/gender.dart';
import 'package:face_reader/domain/services/archetype.dart';
import 'package:face_reader/domain/services/attribute_engine.dart';

class MetricResult {
  final String id;
  final double rawValue;
  final double zScore;
  final double zAdjusted;
  final int metricScore;

  const MetricResult({
    required this.id,
    required this.rawValue,
    required this.zScore,
    required this.zAdjusted,
    required this.metricScore,
  });
}

enum AnalysisSource { camera, album }

class FaceReadingReport {
  final Ethnicity ethnicity;
  final Gender gender;
  final AgeGroup ageGroup;
  final DateTime timestamp;
  final AnalysisSource source;

  /// 17 metric results
  final Map<String, MetricResult> metrics;

  /// 10 attribute scores (0~10)
  final Map<Attribute, double> attributeScores;

  /// Archetype classification
  final ArchetypeResult archetype;

  /// Rules that were triggered
  final List<TriggeredRule> triggeredRules;

  const FaceReadingReport({
    required this.ethnicity,
    required this.gender,
    required this.ageGroup,
    required this.timestamp,
    required this.source,
    required this.metrics,
    required this.attributeScores,
    required this.archetype,
    required this.triggeredRules,
  });
}
