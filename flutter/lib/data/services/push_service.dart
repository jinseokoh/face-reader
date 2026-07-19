import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:facely/config/router.dart';
import 'package:facely/data/services/auth_service.dart';

/// FCM 푸시 — 매칭 응답 알림.
///
/// 발신은 서버가 한다: team_matches 의 consent 변경 trigger 가 Worker
/// (`/api/push/match`)를 호출해 상대 기기로 FCM 을 쏜다. 이 서비스는
/// 수신 측 배선만 담당:
/// - 로그인 세션마다 기기 token 을 push_tokens 에 upsert (기기당 1행)
/// - 백그라운드/종료: FCM notification 이 시스템 알림으로 자동 표시
/// - 포그라운드: FCM 은 자동 표시하지 않으므로 flutter_local_notifications
///   로 같은 시스템 알림을 직접 띄운다 (앞뒤 어디서든 동일한 알림 UX)
/// - 알림 탭: `/g/{teamId}` 딥링크 — 상세 페이지가 참가자를 리빌·매칭
///   카드로 자동 연결
/// - 로그아웃: token 행 삭제 — 로그아웃한 기기로 푸시가 가지 않게
class PushService {
  PushService._();
  static final PushService instance = PushService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  SupabaseClient get _client => Supabase.instance.client;
  String? _token;
  bool _inited = false;

  static const _channel = AndroidNotificationChannel(
    'match',
    '매칭 알림',
    description: '케미 매칭 수락·거절 알림',
    importance: Importance.high,
  );

  Future<void> initialize() async {
    if (_inited) return;
    _inited = true;
    // Android 13+ 알림 권한 — 거부해도 앱 동작에는 영향 없음.
    await _messaging.requestPermission();
    // 포그라운드 표시용 로컬 알림 — 탭 payload = team_id.
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (resp) => _open(resp.payload),
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_channel);
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(
      (m) => _open(m.data['team_id']),
    );
    // 종료 상태에서 알림 탭으로 시작된 경우.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _open(initial.data['team_id']);
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

  /// 포그라운드 수신 — FCM 은 자동 표시하지 않으므로 같은 내용의 시스템
  /// 알림을 로컬로 띄운다 (백그라운드 수신과 동일한 모양·탭 동작).
  void _onForeground(RemoteMessage m) {
    final n = m.notification;
    if (n == null) return;
    _local.show(
      m.messageId.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      payload: m.data['team_id'] as String?,
    );
  }

  void _open(Object? teamId) {
    if (teamId is String && teamId.isNotEmpty) router.push('/g/$teamId');
  }
}
