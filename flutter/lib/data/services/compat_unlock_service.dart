import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:face_engine/domain/models/face_reading_report.dart';

/// 구매한 궁합 쌍 1건 — unlocks 행의 양쪽을 결제 시점 스냅샷으로 복원한 것.
class UnlockedPair {
  final String aId;
  final String bId;
  final FaceReadingReport a;
  final FaceReadingReport b;
  final DateTime createdAt;
  const UnlockedPair({
    required this.aId,
    required this.bId,
    required this.a,
    required this.b,
    required this.createdAt,
  });

  String get key => '$aId~$bId';
  bool contains(String id) {
    final lo = id.toLowerCase();
    return aId == lo || bId == lo;
  }
}

/// unlocks 테이블 + unlock_compat RPC 래퍼.
///
/// 키 = (구매자, a_id<b_id 정규화 쌍) — 내 쌍이든 케미 배틀의 제3자 쌍이든
/// 동일 규칙 ("1코인 = 두 사람의 궁합 풀이, 구매자에게 영구").
/// RLS 가 user_id = auth.uid() 로 SELECT 를 제한 → 조회는 자동으로 현
/// 사용자 것만 반환. INSERT 정책은 없고 `unlock_compat` RPC (SECURITY DEFINER)
/// 만 쓰기를 수행해 코인 차감과 unlock 삽입을 한 트랜잭션으로 묶는다.
class CompatUnlockService {
  static final CompatUnlockService _instance = CompatUnlockService._();
  factory CompatUnlockService() => _instance;
  CompatUnlockService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// 현 사용자의 unlock 된 쌍 키(`lo~hi`) 집합. 비로그인이면 빈 set.
  Future<Set<String>> list() async {
    if (_client.auth.currentUser == null) return const {};
    try {
      final rows = await _client.from('unlocks').select('a_id, b_id');
      return {for (final r in rows) '${r['a_id']}~${r['b_id']}'};
    } catch (e) {
      debugPrint('[CompatUnlock] list error: $e');
      return const {};
    }
  }

  /// unlocks 의 결제 시점 상대 스냅샷을 [FaceReadingReport] 로 복원.
  /// **내 쌍만** — a/b 중 하나가 [myFaceId] 인 행에서 상대 쪽을 뽑는다
  /// (배틀 제3자 쌍은 내 궁합 목록·지갑에 섞지 않는다).
  Future<List<FaceReadingReport>> reconstructUnlockedPartners({
    required String? myFaceId,
  }) async {
    return (await partnerSnapshotsByPartnerId(
      myFaceId: myFaceId,
    )).values.toList();
  }

  /// `상대 id → 결제 시점 상대 스냅샷(FaceReadingReport)` 맵 — 내 쌍만.
  ///
  /// body 는 `toBodyJson()` 출력이라 supabaseId 가 빠져 있으므로 상대 id 를
  /// supabaseId 로 주입하고, source/isMyFace/alias/thumbnailPath 를 override 한
  /// 뒤 parse. metrics row·로컬 history 에 의존하지 않는 self-contained 복원 —
  /// ledger(코인 사용내역)·확인 리스트가 기기·재설치·eviction 무관하게 항상
  /// 상대 사진/인적정보를 띄우는 source of truth. 이름은 body 가 아니라
  /// alias 컬럼 스냅샷(결제 시점 동결)에서 주입.
  Future<Map<String, FaceReadingReport>> partnerSnapshotsByPartnerId({
    required String? myFaceId,
  }) async {
    if (_client.auth.currentUser == null || myFaceId == null) return const {};
    final my = myFaceId.toLowerCase();
    final List<dynamic> rows;
    try {
      rows = await _client
          .from('unlocks')
          .select('a_id, b_id, a_body, b_body, a_alias, b_alias')
          .or('a_id.eq.$my,b_id.eq.$my');
    } catch (e) {
      debugPrint('[CompatUnlock] partner snapshot fetch error: $e');
      return const {};
    }
    final map = <String, FaceReadingReport>{};
    for (final r in rows) {
      // 내가 a 면 상대는 b, 내가 b 면 상대는 a.
      final meIsA = (r['a_id'] as String?)?.toLowerCase() == my;
      final partnerId = (meIsA ? r['b_id'] : r['a_id']) as String?;
      final body = (meIsA ? r['b_body'] : r['a_body']) as String?;
      final alias = meIsA ? r['b_alias'] : r['a_alias'];
      if (partnerId == null || body == null || body.isEmpty) continue;
      try {
        final original = jsonDecode(body) as Map<String, dynamic>;
        final overridden = <String, dynamic>{
          ...original,
          'supabaseId': partnerId,
          'source': AnalysisSource.received.name,
          'isMyFace': false,
          'alias': alias,
          'thumbnailPath': null,
        };
        map[partnerId] = FaceReadingReport.fromJsonString(
          jsonEncode(overridden),
        );
      } catch (e) {
        debugPrint(
          '[CompatUnlock] partner snapshot decode failed partnerId=$partnerId: $e',
        );
      }
    }
    return map;
  }

  /// 구매한 쌍 전체 — 내 쌍·배틀 제3자 쌍 모두. 확인 리스트의 source of
  /// truth (양쪽 body·alias 를 결제 시점 스냅샷에서 복원, 로컬 무의존).
  Future<List<UnlockedPair>> unlockedPairs() async {
    if (_client.auth.currentUser == null) return const [];
    final List<dynamic> rows;
    try {
      rows = await _client
          .from('unlocks')
          .select('a_id, b_id, a_body, b_body, a_alias, b_alias, created_at')
          .order('created_at', ascending: false);
    } catch (e) {
      debugPrint('[CompatUnlock] pairs fetch error: $e');
      return const [];
    }
    final pairs = <UnlockedPair>[];
    for (final r in rows) {
      final a = _decodeSide(r['a_id'], r['a_body'], r['a_alias']);
      final b = _decodeSide(r['b_id'], r['b_body'], r['b_alias']);
      if (a == null || b == null) continue;
      pairs.add(
        UnlockedPair(
          aId: (r['a_id'] as String).toLowerCase(),
          bId: (r['b_id'] as String).toLowerCase(),
          a: a,
          b: b,
          createdAt:
              DateTime.tryParse(r['created_at'] as String? ?? '') ??
              DateTime.now(),
        ),
      );
    }
    return pairs;
  }

  FaceReadingReport? _decodeSide(dynamic id, dynamic body, dynamic alias) {
    if (id is! String || body is! String || body.isEmpty) return null;
    try {
      final original = jsonDecode(body) as Map<String, dynamic>;
      return FaceReadingReport.fromJsonString(
        jsonEncode({
          ...original,
          'supabaseId': id.toLowerCase(),
          'source': AnalysisSource.received.name,
          'isMyFace': false,
          'alias': alias,
          'thumbnailPath': null,
        }),
      );
    } catch (e) {
      debugPrint('[CompatUnlock] pair side decode failed id=$id: $e');
      return null;
    }
  }

  /// unlock_compat RPC 호출 — [aId] < [bId] 정규화된 쌍과 그 순서에 맞춘
  /// body·alias 를 결제 시점 스냅샷으로 동결.
  ///
  /// 반환:
  ///   - `>= 0` : 새 잔액 (이미 해제된 경우는 차감 없이 현재 잔액)
  ///   - `-1`   : 잔액 부족
  ///
  /// RPC 자체가 실패하면 [Exception] 을 그대로 throw — 호출부에서 try/catch
  /// 로 감싸 사용자 피드백을 띄울 것.
  Future<int> unlock({
    required String aId,
    required String bId,
    required String aBody,
    required String bBody,
    String? aAlias,
    String? bAlias,
    double? totalScore,
  }) async {
    final result = await _client.rpc(
      'unlock_compat',
      params: {
        'p_a_id': aId,
        'p_b_id': bId,
        'p_total_score': ?totalScore,
        'p_a_body': aBody,
        'p_b_body': bBody,
        'p_a_alias': ?aAlias,
        'p_b_alias': ?bAlias,
      },
    );
    debugPrint(
      '[CompatUnlock] unlock $aId~$bId → $result (${result.runtimeType})',
    );
    if (result is int) return result;
    if (result is num) return result.toInt();
    if (result is String) return int.parse(result);
    throw StateError(
      'unlock_compat returned unexpected type: ${result.runtimeType} ($result)',
    );
  }

  /// 확인 리스트에서 "내 목록에서 제거" — 정확히 해당 쌍의 내 행만 삭제.
  /// RLS(`unlocks_self_delete`)가 user_id 로 스코프. 코인 환불 없음.
  Future<void> deleteUnlockPair(String aId, String bId) async {
    await _client
        .from('unlocks')
        .delete()
        .eq('a_id', aId.toLowerCase())
        .eq('b_id', bId.toLowerCase());
  }
}
