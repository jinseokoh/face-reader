import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:face_reader/data/constants/face_reference_data.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';

/// 라벨링된 리포트를 CSV로 내보내기.
///
/// `calibrationLabel != null`인 리포트만 포함. 1행 = 1리포트.
/// Python `calibrate_face_shape.py`에 직접 입력 가능한 형태.
class FaceCalibExport {
  /// 라벨링된 리포트 → CSV 문자열 생성 → 클립보드 복사. 복사된 행 수 반환.
  static Future<int> copyToClipboard(List<FaceReadingReport> allReports) async {
    final labeled =
        allReports.where((r) => r.calibrationLabel != null).toList();
    if (labeled.isEmpty) throw Exception('라벨링된 데이터가 없습니다');

    final csv = _buildCsv(labeled);
    await Clipboard.setData(ClipboardData(text: csv));

    debugPrint('[CalibExport] ${labeled.length} rows copied to clipboard');
    return labeled.length;
  }

  static String _buildCsv(List<FaceReadingReport> labeled) {
    final metricIds = metricInfoList.map((m) => m.id).toList();
    final buf = StringBuffer();

    // Header
    buf.writeln([
      'label',
      'alias',
      'timestamp',
      'gender',
      'ethnicity',
      'ageGroup',
      'source',
      ...metricIds,
    ].join(','));

    // Rows
    for (final r in labeled) {
      final cells = <String>[
        r.calibrationLabel!,
        _escape(r.alias ?? ''),
        r.timestamp.toIso8601String(),
        r.gender.name,
        r.ethnicity.name,
        r.ageGroup.name,
        r.source.name,
      ];
      for (final id in metricIds) {
        final mr = r.metrics[id];
        cells.add(mr != null ? mr.rawValue.toStringAsFixed(5) : '');
      }
      buf.writeln(cells.join(','));
    }
    return buf.toString();
  }

  /// 라벨링된 리포트 수.
  static int countLabeled(List<FaceReadingReport> allReports) =>
      allReports.where((r) => r.calibrationLabel != null).length;

  static String _escape(String s) =>
      s.replaceAll(',', ' ').replaceAll('"', '').replaceAll('\n', ' ');
}
