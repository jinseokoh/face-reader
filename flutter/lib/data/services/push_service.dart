import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:top_snackbar_flutter/top_snack_bar.dart';

import 'package:facely/config/router.dart';
import 'package:facely/data/services/auth_service.dart';
import 'package:facely/presentation/widgets/compact_snack_bar.dart';

/// FCM 푸시 — 매칭 응답 알림.
///
/// 발신은 서버가 한다: team_matches 의 consent 변경 trigger 가 Worker
/// (`/api/push/match`)를 호출해 상대 기기로 FCM 을 쏜다. 이 서비스는
/// 수신 측 배선만 담당:
/// - 로그인 세션마다 기기 token 을 push_tokens 에 upsert (기기당 1행)
/// - 포그라운드: 시스템 알림 대신 인앱 top snackbar — 탭하면 해당 방으로
/// - 백그라운드/종료: 시스템 알림 자동 표시 — 탭하면 `/g/{teamId}` 로 이동
///   (상세 페이지가 참가자를 리빌·매칭 카드로 자동 연결)
/// - 로그아웃: token 행 삭제 — 로그아웃한 기기로 푸시가 가지 않게
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  SupabaseClient get _client => Supabase.instance.client;
  String? _token;
  bool _inited = false;

  Future<void> initialize() async {
    if (_inited) return;
    _inited = true;
    // Android 13+ 알림 권한 — 거부해도 앱 동작에는 영향 없음.
    await _messaging.requestPermission();
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_onTap);
    // 종료 상태에서 알림 탭으로 시작된 경우.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _onTap(initial);
    _messaging.onTokenRefresh.listen((t) {
      _token = t;
      unawaited(_register());
    });
    _token = await _messaging.getToken();
    await _register();
    // 세션 로그인(콜드 스타트 복원 포함)마다 재등록 — 계정 전환 반영.
    AuthService().profileStream.listen((u) {
      if (u != null) unawaited(_register());
    });
  }

  Future<void> _register() async {
    final t = _token;
    final uid = _client.auth.currentUser?.id;
    if (t == null || uid == null) return;
    try {
      await _client.from('push_tokens').upsert({
        'user_id': uid,
        'token': t,
        'platform': defaultTargetPlatform.name,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
    } catch (_) {}
  }

  /// 로그아웃 직전 호출 — 세션이 살아 있어야 RLS(본인 행)를 통과한다.
  Future<void> unregister() async {
    final t = _token;
    if (t == null) return;
    try {
      await _client.from('push_tokens').delete().eq('token', t);
    } catch (_) {}
  }

  void _onForeground(RemoteMessage m) {
    final title = m.notification?.title;
    if (title == null) return;
    final teamId = m.data['team_id'] as String?;
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null) return;
    showTopSnackBar(
      Overlay.of(ctx),
      CompactSnackBar.info(message: title),
      onTap: teamId == null ? null : () => router.push('/g/$teamId'),
    );
  }

  void _onTap(RemoteMessage m) {
    final teamId = m.data['team_id'] as String?;
    if (teamId != null && teamId.isNotEmpty) router.push('/g/$teamId');
  }
}
