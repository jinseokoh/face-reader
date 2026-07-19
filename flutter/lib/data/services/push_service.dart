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

  static const _matchChannel = AndroidNotificationChannel(
    'match',
    '매칭 알림',
    description: '케미 매칭 수락·거절 알림',
    importance: Importance.high,
  );

  static const _chatChannel = AndroidNotificationChannel(
    'chat',
    '채팅 알림',
    description: '매칭 상대의 채팅 메시지 알림',
    importance: Importance.high,
  );

  /// 지금 보고 있는 채팅방 — 그 방의 메시지 알림은 배너를 생략한다
  /// (Realtime 이 말풍선을 즉시 그리므로 배너는 이중 소음).
  /// BattleChatScreen 이 진입/이탈 시 설정·해제.
  String? activeChatTeamId;

  Future<void> initialize() async {
    if (_inited) return;
    _inited = true;
    debugPrint('[Push] initialize start');
    // Android 13+ 알림 권한 — 거부해도 앱 동작에는 영향 없음.
    await _messaging.requestPermission();
    // 포그라운드 표시용 로컬 알림 — 탭 payload = team_id.
    await _local.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/launcher_icon'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (resp) =>
          _openFromPayload(resp.payload),
    );
    final android = _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.createNotificationChannel(_matchChannel);
    await android?.createNotificationChannel(_chatChannel);
    FirebaseMessaging.onMessage.listen(_onForeground);
    FirebaseMessaging.onMessageOpenedApp.listen(_openFromMessage);
    // 종료 상태에서 알림 탭으로 시작된 경우.
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _openFromMessage(initial);
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
    debugPrint('[Push] initialize done, token=${_token?.substring(0, 12)}…');
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
  /// 예외: 지금 보고 있는 채팅방의 메시지는 배너 생략.
  void _onForeground(RemoteMessage m) {
    debugPrint(
      '[Push] onMessage ${DateTime.now()} title=${m.notification?.title}',
    );
    final n = m.notification;
    if (n == null) return;
    final kind = m.data['kind'] as String?;
    final teamId = m.data['team_id'] as String?;
    if (kind == 'chat' && teamId != null && teamId == activeChatTeamId) return;
    final channel = kind == 'chat' ? _chatChannel : _matchChannel;
    _local.show(
      id: m.messageId.hashCode,
      title: n.title,
      body: n.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      // 로컬 알림 payload 는 문자열 하나 — "kind:teamId" 로 합쳐 싣는다.
      payload: teamId == null ? null : '${kind ?? 'match'}:$teamId',
    );
  }

  void _openFromMessage(RemoteMessage m) =>
      _open(m.data['kind'] as String?, m.data['team_id'] as String?);

  /// 로컬 알림 탭 payload("kind:teamId") 해석.
  void _openFromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return;
    final sep = payload.indexOf(':');
    if (sep < 0) return;
    _open(payload.substring(0, sep), payload.substring(sep + 1));
  }

  void _open(String? kind, String? teamId) {
    if (teamId == null || teamId.isEmpty) return;
    // 채팅 메시지는 채팅방 직행, 매칭 응답은 방 결과(매칭 카드)로.
    router.push(kind == 'chat' ? '/chat/$teamId' : '/g/$teamId');
  }
}
