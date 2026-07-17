import 'dart:async';
import 'dart:convert';
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
    // 내 관상 싱글톤 강제 — 불변식을 쓰기 시점에만 지키면, 과거 데이터·중단된
    // 저장으로 isMyFace 가 2개 이상 박힌 경우 영구히 남는다. 로드 때 정규화해
    // "나"가 항상 정확히 1개이게 한다 (궁합·케미가 live "나" 를 모호함 없이 resolve).
    if (_normalizeMyFace(reports)) {
      // build 중엔 state 미할당 — 다음 틱에 정규화 결과를 영속화.
      Future(() => _saveToHive());
    }
    _authSub = AuthService().profileStream.listen(_onAuthChanged);
    ref.onDispose(() => _authSub?.cancel());
    // 앱 시작 시 이미 로그인 상태면 즉시 1회 claim + rehydrate.
    final existing = AuthService().currentUser;
    if (existing != null) {
      _lastClaimedUid = existing.id;
      _claimAnonymousMetrics(reports);
      // build 중엔 state 재할당 금지 — 다음 틱에.
      Future(() => _rehydrateFromServer());
    }
    return reports;
  }

  /// 내 관상의 기본 별칭. 지정 시 별칭이 없으면 자동 부여, 해제 시 자동
  /// 부여분('나')만 되돌린다 — 사용자가 직접 지은 별칭은 건드리지 않는다.
  static const _kMyFaceAlias = '나';

  /// 내 관상 ↔ 별칭 '나' 동기화. 별칭이 바뀌었으면 true.
  bool _syncMyFaceAlias(FaceReadingReport r) {
    if (r.isMyFace && r.alias == null) {
      r.alias = _kMyFaceAlias;
      return true;
    }
    if (!r.isMyFace && r.alias == _kMyFaceAlias) {
      r.alias = null;
      return true;
    }
    return false;
  }

  /// 내 관상 싱글톤 정규화 — isMyFace=true 가 2개 이상이면 **첫 번째(최신, 리스트는
  /// newest-first)만 유지**하고 나머지는 false 로. 하나 이상 바꿨으면 true.
  bool _normalizeMyFace(List<FaceReadingReport> reports) {
    var seen = false;
    var changed = false;
    for (final r in reports) {
      if (r.isMyFace && seen) {
        r.isMyFace = false;
        changed = true;
      } else if (r.isMyFace) {
        seen = true;
      }
      if (_syncMyFaceAlias(r)) changed = true;
    }
    if (changed) _log('normalizeMyFace — 중복 내 관상/별칭 정리됨');
    return changed;
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
    // 로그인 rehydrate — 서버 소유 metrics 복원 (새 기기·웹 티저 capture).
    // claim 과 대상이 겹치지 않아 claim 과는 순서 의존 없음.
    unawaited(_rehydrateFromServer());
  }

  void _claimAnonymousMetrics(List<FaceReadingReport> reports) {
    final ids = reports.map((r) => r.supabaseId).whereType<String>().toList();
    if (ids.isEmpty) return;
    // 내 관상 row 는 claim 과 함께 alias 를 프로필 nickname 으로 backfill
    // (익명 촬영 → 로그인 시나리오. 서버 alias 가 이미 있으면 보존).
    String? myFaceId;
    for (final r in reports) {
      if (r.isMyFace) {
        myFaceId = r.supabaseId;
        break;
      }
    }
    SupabaseService()
        .claimAnonymousMetrics(
      ids,
      myFaceId: myFaceId,
      nickname: AuthService().currentUser?.nickname,
    )
        .catchError((Object e) {
      _log('claim anon metrics error: $e');
    });
  }

  /// 로그인 rehydrate — 본인 소유 metrics 를 서버에서 로컬 history 로 복원
  /// (ARCHITECTURE §로그인 rehydrate). 새 기기 로그인·웹 티저 capture 가 대상.
  /// 로컬이 이미 아는 uuid 는 skip, 이 기기에 내 관상이 있으면 서버 지정을
  /// 덮지 않는다 (로컬 우선). 실패는 무해 — 다음 로그인 전이에서 재시도.
  Future<void> _rehydrateFromServer() async {
    try {
      final rows = await SupabaseService().fetchMyMetrics();
      if (rows.isEmpty) return;
      final known = state.map((r) => r.supabaseId).whereType<String>().toSet();
      var hasMyFace = state.any((r) => r.isMyFace);
      final restored = <FaceReadingReport>[];
      for (final row in rows) {
        final id = row['id'] as String?;
        if (id == null || known.contains(id)) continue;
        final report = _reportFromRow(row);
        if (report == null) continue;
        if (report.isMyFace) {
          if (hasMyFace) {
            report.isMyFace = false; // 로컬 지정 우선 — 일반 카드로 강등.
          } else {
            hasMyFace = true;
            // 내 관상의 로컬 표기는 '나' — 서버 alias(nickname)는 서버 전용.
            report.alias = null;
          }
        }
        restored.add(report);
      }
      if (restored.isEmpty) return;
      _log('rehydrate: restored ${restored.length} rows from server');
      // 로컬 뒤에 붙이고 정규화 — _normalizeMyFace 는 첫 my-face 만 유지
      // (리스트 앞 = 로컬)이라 로컬 우선 규칙과 일치. 자동 별칭 '나' 부여 포함.
      final merged = [...state, ...restored];
      _normalizeMyFace(merged);
      state = merged;
      await _saveToHive();
    } catch (e) {
      _log('rehydrate error: $e');
    }
  }

  /// metrics row → FaceReadingReport. 공유받기(fetchByUuid)와 같은
  /// body-override 파싱이되, 소유자 관점이라 source·isMyFace·alias 를 살린다.
  /// thumbnailPath 는 이 기기에 파일이 없으므로 null — 리스트가 thumbnailKey
  /// 의 CDN URL 로 fallback (ThumbnailPaths.cdnUrl).
  FaceReadingReport? _reportFromRow(Map<String, dynamic> row) {
    final body = row['body'];
    if (body is! String || body.isEmpty) return null;
    try {
      final original = jsonDecode(body) as Map<String, dynamic>;
      final overridden = <String, dynamic>{
        ...original,
        'isMyFace': row['is_my_face'] == true,
        'alias': row['alias'],
        'thumbnailPath': null,
        'supabaseId': row['id'],
      };
      return FaceReadingReport.fromJsonString(jsonEncode(overridden));
    } catch (e) {
      _log('rehydrate parse failed id=${row['id']}: $e');
      return null;
    }
  }

  Future<void> add(FaceReadingReport report) async {
    _log('add: supabaseId=${report.supabaseId} alias=${report.alias} '
        'faceShape=${report.faceShape.name} metrics=${report.metrics.length} '
        'isMyFace=${report.isMyFace}');
    // 재촬영(고정 row) — 같은 supabaseId 의 옛 카드는 새 카드로 교체한다.
    // 내 관상 row id 가 영구 고정이라, 교체 없이는 같은 row 를 가리키는
    // 카드가 로컬에 2장 쌓인다.
    var rest = state;
    if (report.supabaseId != null) {
      rest = rest.where((r) => r.supabaseId != report.supabaseId).toList();
    }
    // 내 관상은 항상 1장 — isMyFace 로 들어오는 카드가 기존 지정을 대체.
    if (report.isMyFace) {
      for (final r in rest) {
        r.isMyFace = false;
        _syncMyFaceAlias(r); // 자동 별칭 '나' 회수
      }
    }
    _syncMyFaceAlias(report); // 지정 카드에 기본 별칭 '나'
    state = [report, ...rest];
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

    // 내 관상 싱글톤 정규화 — 실패 엔트리가 없으면 nextJson 이 parsed 와 1:1 이라
    // 정규화 후 재직렬화해 Hive 에도 반영. 실패가 있으면 index 가 어긋나므로
    // 건너뛰고 다음 실행의 build() 가 치유한다.
    if (failedCount == 0 && _normalizeMyFace(parsed)) {
      nextJson
        ..clear()
        ..addAll(parsed.map((r) => r.toJsonString()));
    }

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
