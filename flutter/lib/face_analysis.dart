import 'package:mediapipe_face_mesh/mediapipe_face_mesh.dart';

import 'face_metrics.dart';
import 'face_reference_data.dart';

class MetricAnalysis {
  final String id;
  final String nameKo;
  final String nameEn;
  final String category;
  final double value;
  final double refMean;
  final double refSd;
  final double zScore;
  final String verdict;
  final String higherLabel;
  final String lowerLabel;

  MetricAnalysis({
    required this.id,
    required this.nameKo,
    required this.nameEn,
    required this.category,
    required this.value,
    required this.refMean,
    required this.refSd,
    required this.zScore,
    required this.verdict,
    required this.higherLabel,
    required this.lowerLabel,
  });
}

class FaceAnalysisReport {
  final List<MetricAnalysis> metrics;
  final Ethnicity ethnicity;
  final DateTime timestamp;

  FaceAnalysisReport({
    required this.metrics,
    required this.ethnicity,
    required this.timestamp,
  });

  List<MetricAnalysis> byCategory(String category) =>
      metrics.where((m) => m.category == category).toList();
}

String _verdict(double z, String higherLabel, String lowerLabel) {
  final abs = z.abs();
  if (abs < 0.5) return '평균';
  final direction = z > 0 ? higherLabel : lowerLabel;
  if (abs < 1.0) return '약간 $direction';
  if (abs < 2.0) return direction;
  return '매우 $direction';
}

FaceAnalysisReport analyzeface({
  required List<FaceMeshLandmark> landmarks,
  required Ethnicity ethnicity,
}) {
  final metrics = FaceMetrics(landmarks);
  final measured = metrics.computeAll();
  final refs = referenceData[ethnicity]!;

  final results = <MetricAnalysis>[];
  for (final info in metricInfoList) {
    final value = measured[info.id]!;
    final ref = refs[info.id]!;
    final z = (value - ref.mean) / ref.sd;

    results.add(MetricAnalysis(
      id: info.id,
      nameKo: info.nameKo,
      nameEn: info.nameEn,
      category: info.category,
      value: value,
      refMean: ref.mean,
      refSd: ref.sd,
      zScore: z,
      verdict: _verdict(z, info.higherLabel, info.lowerLabel),
      higherLabel: info.higherLabel,
      lowerLabel: info.lowerLabel,
    ));
  }

  return FaceAnalysisReport(
    metrics: results,
    ethnicity: ethnicity,
    timestamp: DateTime.now(),
  );
}

// Average multiple landmark sets to reduce noise
List<FaceMeshLandmark> averageLandmarks(List<List<FaceMeshLandmark>> samples) {
  if (samples.length == 1) return samples.first;

  final count = samples.first.length;
  final n = samples.length.toDouble();

  return List.generate(count, (i) {
    double sumX = 0, sumY = 0, sumZ = 0;
    for (final sample in samples) {
      sumX += sample[i].x;
      sumY += sample[i].y;
      sumZ += sample[i].z;
    }
    return FaceMeshLandmark(x: sumX / n, y: sumY / n, z: sumZ / n);
  });
}
