import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/domain/models/face_reading_report.dart';

final historyProvider = NotifierProvider<HistoryNotifier, List<FaceReadingReport>>(
  HistoryNotifier.new,
);

class HistoryNotifier extends Notifier<List<FaceReadingReport>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.history);

  @override
  List<FaceReadingReport> build() {
    return _loadFromHive();
  }

  void add(FaceReadingReport report) {
    state = [report, ...state];
    _saveToHive();
  }

  void remove(int index) {
    state = [...state]..removeAt(index);
    _saveToHive();
  }

  void updateHive() {
    _saveToHive();
  }

  List<FaceReadingReport> _loadFromHive() {
    final reports = <FaceReadingReport>[];
    final now = DateTime.now();
    bool hasExpired = false;
    for (int i = 0; i < _box.length; i++) {
      final json = _box.getAt(i);
      if (json != null) {
        try {
          final report = FaceReadingReport.fromJsonString(json);
          if (report.expiresAt.isAfter(now)) {
            reports.add(report);
          } else {
            hasExpired = true;
          }
        } catch (e) {
          debugPrint('[History] failed to parse entry $i: $e');
          hasExpired = true;
        }
      }
    }
    if (hasExpired) {
      // Clean up expired entries from Hive
      _box.clear();
      for (final report in reports) {
        _box.add(report.toJsonString());
      }
    }
    return reports;
  }

  void _saveToHive() {
    _box.clear();
    for (final report in state) {
      _box.add(report.toJsonString());
    }
  }
}
