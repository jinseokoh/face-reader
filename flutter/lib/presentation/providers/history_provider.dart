import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'package:face_reader/core/hive/hive_setup.dart';
import 'package:face_reader/data/services/supabase_service.dart';
import 'package:face_engine/domain/models/face_reading_report.dart';

/// debugPrint 의 rate-limit 을 피하려 raw `print` + `dev.log` 이중 출력.
/// `print` 은 stdout(`flutter logs` 에 그대로), `dev.log` 은 DevTools 타임라인에 꽂힘.
/// 로그가 안 보이면 이 함수부터 의심할 것.
void _log(String msg) {
  // ignore: avoid_print
  print('[History] $msg');
  dev.log(msg, name: 'History');
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<FaceReadingReport>>(
  HistoryNotifier.new,
);

class HistoryNotifier extends Notifier<List<FaceReadingReport>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.history);

  @override
  List<FaceReadingReport> build() {
    _log('build() — initial load from Hive');
    return _loadFromHive();
  }

  Future<void> add(FaceReadingReport report) async {
    _log('add: supabaseId=${report.supabaseId} alias=${report.alias} '
        'faceShape=${report.faceShape.name} metrics=${report.metrics.length}');
    state = [report, ...state];
    await _saveToHive();
  }

  Future<void> remove(int index) async {
    final report = state[index];
    _log('remove index=$index supabaseId=${report.supabaseId}');
    state = [...state]..removeAt(index);
    await _saveToHive();
    final uuid = report.supabaseId;
    if (uuid != null) {
      SupabaseService().deleteMetrics(uuid).catchError((e) {
        _log('supabase delete error: $e');
      });
    }
  }

  Future<void> setMyFace(int index) async {
    final updated = <FaceReadingReport>[];
    for (int i = 0; i < state.length; i++) {
      final r = state[i];
      r.isMyFace = (i == index);
      updated.add(r);
    }
    state = [...updated];
    await _saveToHive();
  }

  Future<void> updateAlias(int index, String alias) async {
    final report = state[index];
    report.alias = alias.isEmpty ? null : alias;
    state = [...state];
    await _saveToHive();
    final uuid = report.supabaseId;
    if (uuid != null) {
      SupabaseService().updateAlias(uuid, alias).catchError((e) {
        _log('supabase alias update error: $e');
      });
    }
  }

  Future<void> updateHive() async {
    await _saveToHive();
  }

  /// Pull-to-refresh 재계산 파이프라인:
  ///   1. Hive 의 각 리포트를 load — `fromJsonString` 이 rawValue 에서 현재
  ///      reference·age adjustment·rule·quantile 로 완전 재계산.
  ///   2. parse 성공한 entry 만 slim capture (rawValue only) 로 Hive 덮어쓰기.
  ///      parse 실패 entry 는 raw 를 그대로 유지.
  ///   3. Supabase 의 metrics_json 도 성공 entry 에 한해 upsert.
  Future<void> reloadFromHive() async {
    final parsed = <FaceReadingReport>[];
    final nextJson = <String>[];
    int droppedExpired = 0;
    int droppedNull = 0;
    int failedCount = 0;
    final now = DateTime.now();
    final boxLen = _box.length;
    _log('reload START box.length=$boxLen state.length=${state.length} '
        'box.values.length=${_box.values.length} '
        'box.keys=${_box.keys.take(10).toList()}');
    for (int i = 0; i < boxLen; i++) {
      final json = _box.getAt(i);
      if (json == null) {
        droppedNull++;
        _log('reload SKIP entry $i: json==null');
        continue;
      }
      _log('reload entry $i: len=${json.length} '
          'head=${json.length > 160 ? json.substring(0, 160) : json}');
      try {
        final report = FaceReadingReport.fromJsonString(json);
        final alive = report.expiresAt.isAfter(now);
        _log('reload entry $i PARSED: expiresAt=${report.expiresAt} '
            'alive=$alive supabaseId=${report.supabaseId} alias=${report.alias}');
        if (!alive) {
          droppedExpired++;
          _log('reload DROP entry $i: expired (expiresAt=${report.expiresAt})');
          continue;
        }
        parsed.add(report);
        nextJson.add(report.toJsonString());
      } catch (e, st) {
        failedCount++;
        _log('reload FAIL entry $i: $e');
        _log('reload FAIL stacktrace:\n$st');
        _log('reload FAIL raw head: '
            '${json.length > 200 ? json.substring(0, 200) : json}');
        nextJson.add(json);
      }
    }
    _log('reload SUMMARY parsed=${parsed.length} expired=$droppedExpired '
        'null=$droppedNull failed=$failedCount nextJson=${nextJson.length}');

    // 방어: parsed 가 0 인데 기존 state 가 비어있지 않다면 box 재기록 금지.
    // Hive 가 async flush race 로 비어보이는 경우 전부 날려버리지 않도록.
    if (parsed.isEmpty && state.isNotEmpty && failedCount == 0) {
      _log('reload ABORT — box empty but state has ${state.length}. '
          'Hive async race 의심 — state/box 유지하고 return.');
      return;
    }

    state = parsed;
    final cleared = await _box.clear();
    _log('reload box.clear() done: cleared=$cleared');
    for (int i = 0; i < nextJson.length; i++) {
      final key = await _box.add(nextJson[i]);
      _log('reload box.add[$i] done: key=$key box.length=${_box.length}');
    }
    await _box.flush();
    _log('reload END state=${state.length} box=${_box.length} '
        'box.values.length=${_box.values.length}');
    for (final r in parsed) {
      if (r.supabaseId != null) {
        SupabaseService().upsertMetricsJson(r).catchError((e) {
          _log('supabase upsert error: $e');
        });
      }
    }
  }

  List<FaceReadingReport> _loadFromHive() {
    final reports = <FaceReadingReport>[];
    final survivorJson = <String>[];
    final now = DateTime.now();
    final boxLen = _box.length;
    int expiredCount = 0;
    int failCount = 0;
    int nullCount = 0;
    _log('load START box.length=$boxLen box.values.length=${_box.values.length}');
    for (int i = 0; i < boxLen; i++) {
      final json = _box.getAt(i);
      if (json == null) {
        nullCount++;
        _log('load SKIP entry $i: json==null');
        continue;
      }
      _log('load entry $i: len=${json.length} '
          'head=${json.length > 160 ? json.substring(0, 160) : json}');
      try {
        final report = FaceReadingReport.fromJsonString(json);
        final alive = report.expiresAt.isAfter(now);
        _log('load entry $i PARSED: expiresAt=${report.expiresAt} '
            'alive=$alive supabaseId=${report.supabaseId}');
        if (alive) {
          reports.add(report);
          survivorJson.add(json);
        } else {
          expiredCount++;
          _log('load DROP entry $i: expired');
        }
      } catch (e, st) {
        failCount++;
        _log('load FAIL entry $i: $e');
        _log('load FAIL stacktrace:\n$st');
        _log('load FAIL raw head: '
            '${json.length > 200 ? json.substring(0, 200) : json}');
        survivorJson.add(json);
      }
    }
    final anyExpired = expiredCount > 0;
    final anyParseError = failCount > 0;
    _log('load SUMMARY alive=${reports.length} expired=$expiredCount '
        'fail=$failCount null=$nullCount survivor=${survivorJson.length}');
    // build() 는 sync 이므로 compaction 은 fire-and-forget. log 로 추적.
    if (anyExpired && !anyParseError) {
      _log('load COMPACT scheduled (alive-only) n=${reports.length}');
      Future(() async {
        await _box.clear();
        for (final r in reports) {
          await _box.add(r.toJsonString());
        }
        await _box.flush();
        _log('load COMPACTED (alive-only) → box=${_box.length}');
      });
    } else if (anyExpired) {
      _log('load COMPACT scheduled (survivor) n=${survivorJson.length}');
      Future(() async {
        await _box.clear();
        for (final j in survivorJson) {
          await _box.add(j);
        }
        await _box.flush();
        _log('load COMPACTED (survivor) → box=${_box.length}');
      });
    } else {
      _log('load NO-COMPACT box unchanged=${_box.length}');
    }
    return reports;
  }

  Future<void> _saveToHive() async {
    _log('save START state=${state.length} prev_box=${_box.length} '
        'prev_values=${_box.values.length}');
    final cleared = await _box.clear();
    _log('save AFTER clear: cleared=$cleared box.length=${_box.length}');
    for (int i = 0; i < state.length; i++) {
      final key = await _box.add(state[i].toJsonString());
      _log('save AFTER add[$i] key=$key box.length=${_box.length}');
    }
    await _box.flush();
    _log('save END box=${_box.length} values=${_box.values.length}');
  }
}
