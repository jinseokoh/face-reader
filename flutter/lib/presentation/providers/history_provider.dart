import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:sentry/sentry.dart';

import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/core/storage/thumbnail_paths.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/data/services/r2_uploader.dart';
import 'package:facely/data/services/supabase_service.dart';
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

  StreamSubscription<AuthUser?>? _authSub;
  // 같은 uid 로 중복 claim 방지 (profileStream 은 코인 갱신에도 발화).
  String? _lastClaimedUid;

  @override
  List<FaceReadingReport> build() {
    _log('build() — initial load from Hive');
    final reports = _loadFromHive();
    _authSub = AuthService().profileStream.listen(_onAuthChanged);
    ref.onDispose(() => _authSub?.cancel());
    // 앱 시작 시 이미 로그인 상태면 즉시 1회 claim.
    final existing = AuthService().currentUser;
    if (existing != null) {
      _lastClaimedUid = existing.id;
      _claimAnonymousMetrics(reports);
    }
    return reports;
  }

  /// 로그인 전이 시 — 로컬 history 가 보유한 supabaseId 들의 익명 metrics row 를
  /// 현재 사용자 소유로 일괄 귀속. logout/코인갱신/같은 uid 재발화는 skip.
  void _onAuthChanged(AuthUser? user) {
    final uid = user?.id;
    if (uid == null) {
      _lastClaimedUid = null;
      return;
    }
    if (uid == _lastClaimedUid) return;
    _lastClaimedUid = uid;
    _claimAnonymousMetrics(state);
  }

  void _claimAnonymousMetrics(List<FaceReadingReport> reports) {
    final ids = reports.map((r) => r.supabaseId).whereType<String>().toList();
    if (ids.isEmpty) return;
    SupabaseService().claimAnonymousMetrics(ids).catchError((Object e) {
      _log('claim anon metrics error: $e');
    });
  }

  Future<void> add(FaceReadingReport report) async {
    _log('add: supabaseId=${report.supabaseId} alias=${report.alias} '
        'faceShape=${report.faceShape.name} metrics=${report.metrics.length} '
        'isMyFace=${report.isMyFace}');
    // 내 관상은 항상 1장 — isMyFace 로 들어오는 카드가 기존 지정을 대체.
    if (report.isMyFace) {
      for (final r in state) {
        r.isMyFace = false;
      }
    }
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

  Future<void> clearMyFace() async {
    final updated = <FaceReadingReport>[];
    for (final r in state) {
      r.isMyFace = false;
      updated.add(r);
    }
    state = [...updated];
    await _saveToHive();
  }

  /// supabaseId 로 별칭 갱신 — 팀 스캔 루프(이름 붙이기)용.
  Future<void> updateAliasById(String supabaseId, String alias) async {
    final idx = state.indexWhere((r) => r.supabaseId == supabaseId);
    if (idx < 0) return;
    await updateAlias(idx, alias);
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

  /// lazy 자가치유 — thumbnailKey 가 비었지만 로컬 thumbnail 파일이 아직 있으면
  /// R2 에 재업로드하고 key 를 채워 Hive·Supabase 에 영속화한다. 분석 당시
  /// 썸네일 업로드가 일시 실패해 thumbnailKey 가 비었던 카드를, 재설치로 로컬
  /// 파일이 소멸하기 전에 복구한다(재설치 후엔 소스가 없어 복구 불가 → Sentry
  /// 가 그 빈도를 알려준다). 받은 카드·복원 파트너는 로컬 파일이 없어 자동 skip.
  Future<void> backfillThumbnailIfMissing(FaceReadingReport report) async {
    if (report.thumbnailKey != null) return;
    final uuid = report.supabaseId;
    if (uuid == null) return;
    final idx = state.indexWhere((r) => r.supabaseId == uuid);
    if (idx < 0) return; // 로컬 history 카드에 한함
    final file = await ThumbnailPaths.resolveFile(report.thumbnailPath);
    if (file == null || !await file.exists()) return;
    try {
      final bytes = await file.readAsBytes();
      final up = await R2Uploader()
          .upload(prefix: 'thumbnails', uuid: uuid, bytes: bytes);
      state[idx].thumbnailKey = up.key;
      state = [...state];
      await _saveToHive();
      await SupabaseService().upsertMetricsBody(state[idx]).catchError((e, st) {
        _log('backfill supabase upsert error: $e');
        Sentry.captureException(e, stackTrace: st);
      });
      _log('backfilled thumbnailKey uuid=$uuid → ${up.key}');
    } catch (e, st) {
      _log('backfill failed uuid=$uuid: $e');
      await Sentry.captureException(e, stackTrace: st, withScope: (s) {
        s.setTag('op', 'thumbnail_backfill');
        s.setTag('uuid', uuid);
      });
    }
  }

  /// Pull-to-refresh 재계산 파이프라인:
  ///   1. Hive 의 각 리포트를 load — `fromJsonString` 이 rawValue 에서 현재
  ///      reference·age adjustment·rule·quantile 로 완전 재계산.
  ///   2. parse 성공한 entry 만 slim capture (rawValue only) 로 Hive 덮어쓰기.
  ///      parse 실패 entry 는 raw 를 그대로 유지.
  Future<void> reloadFromHive() async {
    final parsed = <FaceReadingReport>[];
    final nextJson = <String>[];
    int droppedNull = 0;
    int failedCount = 0;
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
        _log('reload entry $i PARSED: supabaseId=${report.supabaseId} alias=${report.alias}');
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
    _log('reload SUMMARY parsed=${parsed.length} '
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
  }

  List<FaceReadingReport> _loadFromHive() {
    final reports = <FaceReadingReport>[];
    final boxLen = _box.length;
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
        _log('load entry $i PARSED: supabaseId=${report.supabaseId}');
        reports.add(report);
      } catch (e, st) {
        failCount++;
        _log('load FAIL entry $i: $e');
        _log('load FAIL stacktrace:\n$st');
        _log('load FAIL raw head: '
            '${json.length > 200 ? json.substring(0, 200) : json}');
      }
    }
    _log('load SUMMARY loaded=${reports.length} '
        'fail=$failCount null=$nullCount');
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
