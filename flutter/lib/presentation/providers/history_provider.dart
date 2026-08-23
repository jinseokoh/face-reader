import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
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
      'supabaseId': row['id'],
    };
    return FaceReadingReport.fromJsonString(jsonEncode(overridden));
  } catch (e) {
    _log('rehydrate parse failed id=${row['id']}: $e');
    return null;
  }
}

final historyProvider =
    NotifierProvider<HistoryNotifier, List<FaceReadingReport>>(
  HistoryNotifier.new,
);

class HistoryNotifier extends Notifier<List<FaceReadingReport>> {
  Box<String> get _box => Hive.box<String>(HiveBoxes.history);
  Box<String> get _prefs => Hive.box<String>(HiveBoxes.prefs);

  /// 이 기기 history 의 소유 계정 uid. 키가 없으면 익명(로그인 전 촬영분)
  /// 이라 다음 로그인이 claim 해 간다. 값이 박혀 있으면 그 계정 전용이다.
  static const String _kOwnerUidKey = 'history_owner_uid';

  /// 사진 필드가 `thumbnailKey` 하나가 되기 전에 저장된 카드의 로컬 파일명.
  /// 그 시절 파일명은 분석 uuid 라 키에서 파생되지 않는다 — Hive JSON 에만 남은
  /// 이름을 건져 두었다가 [retryPendingUploads] 가 파일을 해시해 키로 바꾼다.
  /// 이 회수가 없으면 아직 업로드 못 한 사진이 이름을 잃어 사라진다.
  static const String _kFilesToAdoptKey = 'thumbnail_files_to_adopt';

  /// R2 업로드가 아직 안 끝난 썸네일 키 목록. 카드의 필드가 아니라 별도
  /// 대기열이다 — 사진의 진실은 `thumbnailKey` 하나이고, 여기 있는 것은
  /// "아직 서버가 모르는 사진" 이라는 진행 상태일 뿐이다.
  static const String _kPendingUploadsKey = 'pending_thumbnail_uploads';

  StreamSubscription<AuthUser?>? _authSub;
  // 같은 uid 로 중복 claim 방지 (profileStream 은 코인 갱신에도 발화).
  String? _lastClaimedUid;

  @override
  List<FaceReadingReport> build() {
    _log('build() — initial load from Hive');
    var reports = _loadFromHive();
    // 계정 각인 검사는 claim·정규화보다 먼저. 남의 목록을 들고 claim 에
    // 들어가면 서버의 my-face 플래그까지 망가진다.
    if (_enforceOwner()) reports = <FaceReadingReport>[];
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
      _writeOwner(existing.id);
      _claimAnonymousMetrics(reports);
      Future(() => _rekeyAnonThumbnails(existing.id));
      // build 중엔 state 재할당 금지 — 다음 틱에.
      Future(() => _rehydrateFromServer());
    }
    // 지난 실행에서 못 올린 사진 재시도 — 로그인 여부와 무관 (익명 업로드 허용).
    // 입양(이름 옮기기)이 끝난 뒤에 캐시를 쓸어야 살아있는 파일을 안 지운다.
    Future(() async {
      await retryPendingUploads();
      await _sweepCacheFiles();
    });
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
      // 세션까지 사라진 경우(로그아웃·만료·다른 기기 로그아웃)만 폐기.
      // users row 조회 실패로 프로필만 null 이 된 경우는 세션이 살아 있어
      // _enforceOwner 가 각인과 일치를 확인하고 그냥 지나간다.
      if (_enforceOwner()) state = <FaceReadingReport>[];
      return;
    }
    if (_enforceOwner()) state = <FaceReadingReport>[];
    if (uid == _lastClaimedUid) return;
    _lastClaimedUid = uid;
    _writeOwner(uid);
    _claimAnonymousMetrics(state);
    // 익명 시절 사진은 anon-{id}/ 에 있다 — 내 폴더로 옮기지 않으면 90일
    // 정리에 걸린다.
    unawaited(_rekeyAnonThumbnails(uid));
    // 로그인 rehydrate — 서버 소유 metrics 복원 (새 기기·웹 티저 capture).
    // claim 과 대상이 겹치지 않아 claim 과는 순서 의존 없음.
    unawaited(_rehydrateFromServer());
  }

  String? _readOwner() {
    try {
      return _prefs.get(_kOwnerUidKey);
    } catch (e) {
      _log('owner read unavailable: $e');
      return null;
    }
  }

  void _writeOwner(String? uid) {
    try {
      if (uid == null) {
        _prefs.delete(_kOwnerUidKey);
      } else {
        _prefs.put(_kOwnerUidKey, uid);
      }
    } catch (e) {
      _log('owner write skipped: $e');
    }
  }

  /// 계정 각인 검사 — 각인이 세션 uid 와 어긋나면 로컬 history 를 통째로
  /// 버리고 true. 훅(로그아웃 버튼)이 아니라 불변식으로 두는 이유: 세션은
  /// 토큰 갱신 실패·만료·다른 기기 로그아웃으로도 끊기고 그 경로들은
  /// AuthService.signOut() 을 거치지 않는다. 로그아웃 도중 강제종료도 같다.
  /// 각인을 로드마다 대조하면 어느 경로로 끊겼든 다음 로드에서 잡힌다.
  ///
  /// 판정 기준은 프로필이 아니라 **세션**([AuthService.sessionUserId]) —
  /// 오프라인 cold start 는 세션이 살아 있어도 프로필 조회가 실패해
  /// currentUser 가 null 이라, 프로필로 판정하면 본인 데이터를 지운다.
  ///
  /// 각인이 없으면(익명) 버리지 않는다 — 로그인 전 촬영분을 다음 로그인이
  /// claim 해 가는 설계된 흐름이다.
  bool _enforceOwner() {
    final owner = _readOwner();
    if (owner == null) return false;
    if (owner == AuthService().sessionUserId) return false;
    _log('owner mismatch — 로컬 history 폐기 (owner=$owner)');
    unawaited(_box.clear());
    _writeOwner(null);
    return true;
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

  /// Pull-to-refresh 서버 동기화 — 서버 metrics 가 진실. 알려진 uuid 는 서버
  /// 내용으로 교체, 서버에만 있는 row 는 복원, 서버에서 사라진 소유 row 는
  /// 로컬에서도 제거한다 (다른 기기·웹에서의 삭제 반영). 받은 카드
  /// (source=received, 남의 row 라 fetchMyMetrics 에 안 나옴)와 supabaseId
  /// 없는 로컬 전용 카드는 대상 아님. 비로그인·네트워크 실패는 무해 —
  /// 로컬 그대로 두고 다음 당김에서 재시도.
  Future<void> syncFromServer() async {
    final user = AuthService().currentUser;
    if (user == null) return;
    try {
      // 미귀속 익명 row 를 먼저 귀속 — 아래에서 fetchMyMetrics 부재 = 서버
      // 삭제로 판정하므로, claim 없이 fetch 하면 아직 user_id 가 null 인
      // 익명 카드가 삭제로 오판된다. (claim 은 id 범위·is-null 필터라 멱등.)
      final ids = state.map((r) => r.supabaseId).whereType<String>().toList();
      if (ids.isNotEmpty) {
        String? myFaceId;
        for (final r in state) {
          if (r.isMyFace) {
            myFaceId = r.supabaseId;
            break;
          }
        }
        await SupabaseService().claimAnonymousMetrics(
          ids,
          myFaceId: myFaceId,
          nickname: user.nickname,
        );
      }
      final rows = await SupabaseService().fetchMyMetrics();
      final ownedLocally = state.any(
        (r) => r.supabaseId != null && r.source != AnalysisSource.received,
      );
      // 방어: 소유 카드가 로컬에 있는데 서버가 0행이면 동기화 중단 — auth
      // 상태 불일치(세션 만료 등)로 빈 응답이 온 경우 전량 삭제를 막는다.
      if (rows.isEmpty && ownedLocally) {
        _log('sync ABORT — server 0 rows but local has owned cards. '
            'auth 불일치 의심 — 로컬 유지.');
        return;
      }
      final byId = {
        for (final row in rows)
          if (row['id'] is String) row['id'] as String: row,
      };
      final next = <FaceReadingReport>[];
      var replaced = 0;
      var removed = 0;
      for (final r in state) {
        final id = r.supabaseId;
        if (id == null || r.source == AnalysisSource.received) {
          next.add(r);
          continue;
        }
        final row = byId.remove(id);
        if (row == null) {
          removed++; // 다른 기기에서 삭제된 row — 로컬에서도 제거.
          continue;
        }
        final fresh = _reportFromRow(row);
        if (fresh == null) {
          next.add(r); // 서버 body 파싱 실패 — 로컬 유지.
          continue;
        }
        // 내 관상의 로컬 표기는 '나' — 서버 alias(nickname)는 서버 전용.
        if (fresh.isMyFace) fresh.alias = null;
        next.add(fresh);
        replaced++;
      }
      // 남은 서버 row = 로컬 미보유 — 새 기기·웹 티저 capture 복원.
      var restored = 0;
      for (final row in byId.values) {
        final report = _reportFromRow(row);
        if (report == null) continue;
        if (report.isMyFace) report.alias = null;
        next.add(report);
        restored++;
      }
      _log('sync: replaced=$replaced removed=$removed restored=$restored');
      _normalizeMyFace(next);
      state = next;
      await _saveToHive();
    } catch (e) {
      _log('sync error: $e');
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

  /// 썸네일 업로드 — 저장을 마친 카드의 사진을 R2 에 올린다. 실패하면 대기열에
  /// 남겨 다음 실행이 재시도한다. 키가 내용 주소라 재시도가 멱등하다
  /// (서버 409 = 같은 바이트가 이미 있음 = 성공).
  Future<void> uploadThumbnail(String key, Uint8List bytes) async {
    final hash = ThumbnailPaths.hashFromKey(key);
    if (hash == null) return;
    try {
      final p = await R2Uploader().upload(
        prefix: 'thumbnails',
        hash: hash,
        scope: ThumbnailPaths.anonScopeOfKey(key),
        accessToken: AuthService().accessToken,
        bytes: bytes,
      );
      await _dropPendingUpload(key);
      // 소유자를 서버가 JWT 에서 정하므로 응답의 key 가 최종 진실이다.
      if (p.key != key) await _adoptServerKey(key, p.key);
      _log('thumbnail uploaded ${p.key}');
    } catch (e, st) {
      await _addPendingUpload(key);
      _log('thumbnail upload 대기열로 $key: $e');
      await Sentry.captureException(e, stackTrace: st, withScope: (sc) {
        sc.setTag('op', 'thumbnail_upload');
      });
    }
  }

  /// 서버가 조립한 키로 카드를 맞춘다. 로컬 캐시 파일명은 해시라 두 키가
  /// 같은 파일을 가리키므로 파일은 건드릴 필요가 없다.
  Future<void> _adoptServerKey(String localKey, String serverKey) async {
    final changed = <FaceReadingReport>[];
    for (final r in state) {
      if (r.thumbnailKey != localKey) continue;
      r.thumbnailKey = serverKey;
      changed.add(r);
    }
    if (changed.isEmpty) return;
    _log('서버 키 채택 $localKey → $serverKey (${changed.length}장)');
    state = [...state];
    await _saveToHive();
    for (final r in changed) {
      if (r.supabaseId == null) continue;
      await SupabaseService().upsertMetricsBody(r).catchError((e, st) {
        _log('서버 키 upsert 실패: $e');
        Sentry.captureException(e, stackTrace: st);
      });
    }
  }

  /// 익명 촬영분의 사진을 내 폴더로 옮긴다. 계정 귀속(claim)은 **행만** 옮기고
  /// 사진은 `anon-{id}/` 에 남는데, 그 폴더는 90일 정리의 대상이다 — 옮기지
  /// 않으면 로그인한 사용자의 사진이 어느 날 사라진다.
  ///
  /// 로컬 캐시 파일명이 해시라 파일은 그대로 쓰이고, 업로드만 다시 하면 된다.
  Future<void> _rekeyAnonThumbnails(String uid) async {
    final changed = <FaceReadingReport>[];
    for (final r in state) {
      final key = r.thumbnailKey;
      if (key == null || ThumbnailPaths.anonScopeOfKey(key) == null) continue;
      final hash = ThumbnailPaths.hashFromKey(key);
      if (hash == null) continue;
      r.thumbnailKey = ThumbnailPaths.keyFor(hash, uid);
      await _addPendingUpload(r.thumbnailKey!);
      changed.add(r);
    }
    if (changed.isEmpty) return;
    _log('익명 사진 ${changed.length}장을 내 폴더로 재지정');
    state = [...state];
    await _saveToHive();
    for (final r in changed) {
      if (r.supabaseId == null) continue;
      await SupabaseService().upsertMetricsBody(r).catchError((e, st) {
        _log('익명 재지정 upsert 실패: $e');
        Sentry.captureException(e, stackTrace: st);
      });
    }
    await retryPendingUploads();
  }

  /// 아직 R2 에 없는 사진을 올린다. 두 갈래를 함께 처리한다:
  ///   1. 업로드가 실패해 대기열에 남은 키 — 로컬 캐시 파일로 재시도
  ///   2. 키가 없고 로컬 파일만 있는 카드 — 파일에서 키를 계산해 올리고 영속화
  ///
  /// 2번이 이 기기에만 있던 사진을 서버가 아는 사진으로 바꾼다. 재설치로 로컬
  /// 파일이 사라지기 전에 해두지 않으면 그 얼굴은 어디서도 복구할 수 없다.
  Future<void> retryPendingUploads() async {
    for (final key in List<String>.from(_readPendingUploads())) {
      final file = await ThumbnailPaths.resolveFile(
        ThumbnailPaths.fileNameForKey(key),
      );
      if (file == null || !await file.exists()) {
        await _dropPendingUpload(key); // 캐시가 사라졌다 — 올릴 원본이 없다.
        continue;
      }
      await uploadThumbnail(key, await file.readAsBytes());
    }

    final adopt = _readFilesToAdopt();
    if (adopt.isEmpty) return;
    for (final entry in adopt.entries.toList()) {
      final idx = state.indexWhere((r) => r.supabaseId == entry.key);
      if (idx < 0) {
        // 아직 이 카드가 로컬에 없다 — 로그인 rehydrate 전이거나 계정 각인이
        // 방금 목록을 비웠다. 여기서 지우면 파일명이 영영 사라지므로 다음
        // 실행으로 미룬다. 근거가 없을 때의 정답은 삭제가 아니라 대기다.
        continue;
      }
      final r = state[idx];
      if (r.thumbnailKey != null || r.source == AnalysisSource.received) {
        adopt.remove(entry.key);
        continue;
      }
      final file = await ThumbnailPaths.resolveFile(entry.value);
      if (file == null || !await file.exists()) {
        adopt.remove(entry.key); // 파일이 사라졌다 — 되살릴 원본이 없다.
        continue;
      }
      final bytes = await file.readAsBytes();
      final owner = ThumbnailPaths.owner(
        userId: AuthService().sessionUserId,
        metricsId: r.supabaseId,
      );
      if (owner == null) continue;
      final key = ThumbnailPaths.contentKey(bytes, owner: owner);
      // 파일명을 키에 맞춰 옮긴다 — 그래야 업로드 전에도 화면이 사진을 찾는다.
      final renamed = await ThumbnailPaths.cacheFile(key);
      if (renamed != null && !await renamed.exists()) {
        await file.rename(renamed.path).catchError((Object e) {
          _log('캐시 파일 이름 변경 실패: $e');
          return file;
        });
      }
      r.thumbnailKey = key;
      state = [...state];
      await _saveToHive();
      await SupabaseService().upsertMetricsBody(r).catchError((e, st) {
        _log('thumbnail key upsert error: $e');
        Sentry.captureException(e, stackTrace: st);
      });
      await uploadThumbnail(key, bytes);
      adopt.remove(entry.key);
    }
    await _prefs.put(_kFilesToAdoptKey, jsonEncode(adopt));
  }

  /// 키가 없는 카드의 옛 파일명을 raw JSON 에서 건진다. 키가 있으면 파일명이
  /// 키에서 파생되므로 할 일이 없다.
  void _rememberFileToAdopt(FaceReadingReport report, String rawJson) {
    if (report.thumbnailKey != null || report.supabaseId == null) return;
    try {
      final j = jsonDecode(rawJson) as Map<String, dynamic>;
      final name = j['thumbnailPath'] as String?;
      if (name == null || name.isEmpty) return;
      final map = _readFilesToAdopt();
      if (map[report.supabaseId] == name) return;
      map[report.supabaseId!] = name;
      _prefs.put(_kFilesToAdoptKey, jsonEncode(map));
    } catch (e) {
      _log('adopt 대상 기록 실패: $e');
    }
  }

  Map<String, String> _readFilesToAdopt() {
    try {
      final raw = _prefs.get(_kFilesToAdoptKey);
      if (raw == null || raw.isEmpty) return {};
      return (jsonDecode(raw) as Map<String, dynamic>).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  /// 어떤 카드의 키와도 이름이 맞지 않는 캐시 파일 정리.
  ///
  /// 로컬 파일은 서버 원본의 캐시라 지워도 대개 손실이 없다. 예외가 하나 있다 —
  /// **아직 못 올린 사진.** 그건 이 기기의 파일이 유일한 사본이다. 대기열과
  /// 입양 목록을 keep 에 넣지 않으면, 로그아웃이 Hive 를 비운 직후 스윕이 그
  /// 유일한 사본을 지우고 다음 재시도가 "원본이 없다" 며 키를 버린다.
  Future<void> _sweepCacheFiles() async {
    final keep = ThumbnailPaths.cacheKeepSet(
      cardKeys: state.map((r) => r.thumbnailKey),
      pendingKeys: _readPendingUploads(),
      adoptFileNames: _readFilesToAdopt().values,
    );
    if (keep == null) {
      _log('캐시 스윕 건너뜀 — 지킬 목록이 비어 판단 근거가 없다');
      return;
    }
    final removed = await ThumbnailPaths.sweepCache(keep);
    if (removed > 0) _log('캐시 파일 $removed개 정리');
  }

  List<String> _readPendingUploads() {
    try {
      final raw = _prefs.get(_kPendingUploadsKey);
      if (raw == null || raw.isEmpty) return const [];
      return (jsonDecode(raw) as List).cast<String>();
    } catch (e) {
      _log('pending uploads read 실패: $e');
      return const [];
    }
  }

  Future<void> _writePendingUploads(List<String> keys) async {
    try {
      await _prefs.put(_kPendingUploadsKey, jsonEncode(keys));
    } catch (e) {
      _log('pending uploads write 실패: $e');
    }
  }

  Future<void> _addPendingUpload(String key) async {
    final keys = List<String>.from(_readPendingUploads());
    if (keys.contains(key)) return;
    keys.add(key);
    await _writePendingUploads(keys);
  }

  Future<void> _dropPendingUpload(String key) async {
    final keys = List<String>.from(_readPendingUploads());
    if (!keys.remove(key)) return;
    await _writePendingUploads(keys);
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
        _rememberFileToAdopt(report, json);
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
