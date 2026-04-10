import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/data/services/supabase_service.dart';
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
    final report = state[index];
    state = [...state]..removeAt(index);
    _saveToHive();
    // Delete from Supabase in background
    final uuid = report.supabaseId;
    if (uuid != null) {
      SupabaseService().deleteMetrics(uuid).catchError((e) {
        debugPrint('[History] supabase delete error: $e');
      });
    }
  }

  void setMyFace(int index) {
    final updated = <FaceReadingReport>[];
    for (int i = 0; i < state.length; i++) {
      final r = state[i];
      r.isMyFace = (i == index);
      updated.add(r);
    }
    state = [...updated];
    _saveToHive();
  }

  void updateAlias(int index, String alias) {
    final report = state[index];
    report.alias = alias.isEmpty ? null : alias;
    state = [...state];
    _saveToHive();
    // Update Supabase in background
    final uuid = report.supabaseId;
    if (uuid != null) {
      SupabaseService().updateAlias(uuid, alias).catchError((e) {
        debugPrint('[History] supabase alias update error: $e');
      });
    }
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
