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

  /// Pull-to-refresh 재계산 파이프라인:
  ///   1. Hive 의 각 리포트를 load — `fromJsonString` 이 rawValue 에서 현재
  ///      reference·age adjustment·rule·quantile 로 완전 재계산.
  ///   2. parse 성공한 entry 만 slim capture (rawValue only) 로 Hive 덮어쓰기.
  ///      parse 실패 entry 는 raw 를 그대로 유지 — 일시적 파싱 오류로 기록이
  ///      사라지지 않도록 보호.
  ///   3. Supabase 의 metrics_json 도 성공 entry 에 한해 upsert — 서버 공유
  ///      링크·궁합 fetch 도 새 공식으로 동기화.
  void reloadFromHive() {
    final parsed = <FaceReadingReport>[];
    final nextJson = <String>[];
    final now = DateTime.now();
    for (int i = 0; i < _box.length; i++) {
      final json = _box.getAt(i);
      if (json == null) continue;
      try {
        final report = FaceReadingReport.fromJsonString(json);
        if (!report.expiresAt.isAfter(now)) continue; // expired → drop
        parsed.add(report);
        nextJson.add(report.toJsonString()); // slim 재직렬화
      } catch (e) {
        debugPrint('[History] reload: keep unparseable raw (entry $i): $e');
        nextJson.add(json); // 원본 raw 보존
      }
    }
    state = parsed;
    _box.clear();
    for (final j in nextJson) {
      _box.add(j);
    }
    for (final r in parsed) {
      if (r.supabaseId != null) {
        SupabaseService().upsertMetricsJson(r).catchError((e) {
          debugPrint('[History] supabase upsert error: $e');
        });
      }
    }
  }

  List<FaceReadingReport> _loadFromHive() {
    final reports = <FaceReadingReport>[];
    final survivorJson = <String>[];
    final now = DateTime.now();
    bool anyExpired = false;
    bool anyParseError = false;
    for (int i = 0; i < _box.length; i++) {
      final json = _box.getAt(i);
      if (json == null) continue;
      try {
        final report = FaceReadingReport.fromJsonString(json);
        if (report.expiresAt.isAfter(now)) {
          reports.add(report);
          survivorJson.add(json);
        } else {
          anyExpired = true;
        }
      } catch (e) {
        // Parse 실패는 엔진 전환 중 일시적으로 날 수 있다. raw JSON 은 절대
        // 건드리지 않고 이번 세션에만 skip. 다음 load 에서 다시 시도.
        debugPrint('[History] skip entry $i (parse error, raw kept): $e');
        anyParseError = true;
        survivorJson.add(json);
      }
    }
    // 실제 만료된 엔트리만 치워서 box 를 정리. parse 실패 entry 는 raw 유지.
    if (anyExpired && !anyParseError) {
      _box.clear();
      for (final report in reports) {
        _box.add(report.toJsonString());
      }
    } else if (anyExpired) {
      _box.clear();
      for (final j in survivorJson) {
        _box.add(j);
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
