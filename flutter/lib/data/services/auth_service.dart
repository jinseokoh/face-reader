import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:face_reader/data/services/wallet_service.dart';
import 'package:face_reader/domain/models/coin_transaction.dart';

class AuthUser {
  final String id;                  // auth.uid()
  final String? kakaoUserId;
  final String? nickname;
  final String? profileImageUrl;
  final int coins;
  /// 가입 시 같은 email/kakao_user_id 가 이미 보너스를 받은 적 있어
  /// 보너스 3 코인이 dedup 으로 차단된 계정. 클라이언트는 이 flag 로 1회
  /// 안내 다이얼로그를 띄운다.
  final bool signupBonusSkipped;

  const AuthUser({
    required this.id,
    required this.coins,
    this.kakaoUserId,
    this.nickname,
    this.profileImageUrl,
    this.signupBonusSkipped = false,
  });

  AuthUser copyWith({int? coins}) => AuthUser(
        id: id,
        kakaoUserId: kakaoUserId,
        nickname: nickname,
        profileImageUrl: profileImageUrl,
        coins: coins ?? this.coins,
        signupBonusSkipped: signupBonusSkipped,
      );
}

/// signUpWithEmail 의 결과. Supabase 가 throw 안 하고도 "이미 가입된 계정"
/// 케이스를 반환하므로 bool 로는 부족 — 3 가지 분기.
enum SignUpOutcome {
  /// 신규 가입 — OTP 이메일 발송. UI 는 OTP sheet 띄움.
  newAccount,

  /// 이미 confirmed 가입자 (user-enumeration 방어). OTP 안 옴 — UI 는
  /// 로그인 모드로 자동 전환.
  alreadyRegistered,

  /// 예외 발생 (네트워크·rate-limit·invalid email 등).
  error,
}

/// Singleton auth service backed by Supabase Auth. Kakao OAuth + Email both
/// route through the same `auth.users` table; `public.users` row + signup
/// bonus are created by the `on_auth_user_created` DB trigger.
class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  static const _redirectUrl = 'facely://auth-callback';

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  StreamSubscription<AuthState>? _sub;
  final _profileChanged = StreamController<AuthUser?>.broadcast();
  final _signupBonusSkippedNotice = StreamController<void>.broadcast();
  // Per-session: 한 번 안내한 사용자 id 는 다시 띄우지 않는다.
  final Set<String> _signupBonusNoticeShown = <String>{};

  /// Stream that fires when the signed-in profile changes (login, logout,
  /// coin balance refresh). Used by providers to react.
  Stream<AuthUser?> get profileStream => _profileChanged.stream;

  /// 가입 시 dedup 으로 보너스가 차단된 계정이 처음 로드되었을 때 1회 emit.
  /// app.dart 에서 listen → 안내 다이얼로그.
  Stream<void> get signupBonusSkippedNotice =>
      _signupBonusSkippedNotice.stream;

  Future<void> initialize() async {
    debugPrint('[Auth] initialize start, currentSession=${_client.auth.currentSession != null}');
    _sub = _client.auth.onAuthStateChange.listen((state) async {
      final session = state.session;
      debugPrint('[Auth] onAuthStateChange event=${state.event} '
          'hasSession=${session != null} '
          'userId=${session?.user.id} '
          'email=${session?.user.email}');
      if (session == null) {
        _setUser(null);
      } else {
        await _loadProfile();
      }
    });

    if (_client.auth.currentSession != null) {
      await _loadProfile();
    }
  }

  Future<void> _loadProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) {
      debugPrint('[Auth] _loadProfile: no auth user');
      _setUser(null);
      return;
    }
    debugPrint('[Auth] _loadProfile start id=${authUser.id} email=${authUser.email}');
    try {
      final row = await _client
          .from('users')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();
      debugPrint('[Auth] _loadProfile users row keys=${row?.keys.toList()}');
      if (row == null) {
        debugPrint('[Auth] public.users row missing for ${authUser.id} '
            '— trigger may have failed');
        _setUser(null);
        return;
      }
      final mapped = _mapUser(row);
      _setUser(mapped);
      debugPrint('[Auth] profile loaded: nickname=${mapped.nickname} '
          'coins=${mapped.coins} signupBonusSkipped=${mapped.signupBonusSkipped}');
    } catch (e, st) {
      debugPrint('[Auth] profile load failed: $e\n$st');
    }
  }

  void _setUser(AuthUser? user) {
    _currentUser = user;
    _profileChanged.add(user);
    if (user != null &&
        user.signupBonusSkipped &&
        !_signupBonusNoticeShown.contains(user.id)) {
      _signupBonusNoticeShown.add(user.id);
      _signupBonusSkippedNotice.add(null);
    }
  }

  /// Kakao OAuth via Supabase. Opens a browser/webview; the actual session
  /// arrives asynchronously through `onAuthStateChange` once the deep link
  /// redirects back. Returns true if the browser was opened successfully.
  Future<bool> loginWithKakao() async {
    debugPrint('[Auth] loginWithKakao: invoking signInWithOAuth (redirect=$_redirectUrl)');
    try {
      final launched = await _client.auth.signInWithOAuth(
        OAuthProvider.kakao,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
      debugPrint('[Auth] loginWithKakao: browser launched=$launched');
      return launched;
    } catch (e, st) {
      debugPrint('[Auth] kakao oauth error: $e\n$st');
      return false;
    }
  }

  /// Email + password sign in. Returns true on success.
  Future<bool> loginWithEmail(String email, String password) async {
    try {
      await _client.auth
          .signInWithPassword(email: email, password: password);
      return true;
    } catch (e) {
      debugPrint('[Auth] email login error: $e');
      return false;
    }
  }

  /// Email + password sign up. Supabase user-enumeration 방어 때문에 이미
  /// confirmed 가입자 이메일이어도 throw 하지 않고 가짜 success 응답이 옴 —
  /// 다만 `user.identities` 가 비어있어 구분 가능. 호출자가 outcome 으로
  /// 분기.
  Future<SignUpOutcome> signUpWithEmail(String email, String password) async {
    debugPrint('[Auth.signUp] start email=$email pwLen=${password.length}');
    try {
      final res = await _client.auth.signUp(
        email: email,
        password: password,
        emailRedirectTo: _redirectUrl,
      );
      final user = res.user;
      final session = res.session;
      final identCount = user?.identities?.length ?? 0;
      debugPrint(
        '[Auth.signUp] response: userId=${user?.id} '
        'identities=$identCount session=${session != null} '
        'confirmedAt=${user?.emailConfirmedAt}',
      );
      if (user == null) {
        debugPrint('[Auth.signUp] OUTCOME=error (user null)');
        return SignUpOutcome.error;
      }
      // Supabase user-enumeration 방어 — 이미 confirmed 가입자에게도 200 OK
      // 같은 가짜 success. user.identities 가 비어있는 것이 신호 (v2.x SDK).
      if (identCount == 0) {
        debugPrint('[Auth.signUp] OUTCOME=alreadyRegistered '
            '(empty identities — user already exists)');
        return SignUpOutcome.alreadyRegistered;
      }
      debugPrint('[Auth.signUp] OUTCOME=newAccount — OTP 이메일 발송 예상');
      return SignUpOutcome.newAccount;
    } catch (e, st) {
      debugPrint('[Auth.signUp] OUTCOME=error exception=$e');
      debugPrint('[Auth.signUp] stack=$st');
      return SignUpOutcome.error;
    }
  }

  /// 가입 후 발송된 6자리 OTP 를 검증. 성공 시 Supabase 가 자동으로 session
  /// 을 만들고 onAuthStateChange 가 발화 → _loadProfile 이 실행됨.
  Future<bool> verifyEmailOtp(String email, String token) async {
    debugPrint('[Auth.verifyOtp] start email=$email tokenLen=${token.length}');
    try {
      final res = await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
      debugPrint('[Auth.verifyOtp] OK userId=${res.user?.id} '
          'session=${res.session != null}');
      return true;
    } catch (e, st) {
      debugPrint('[Auth.verifyOtp] FAIL exception=$e');
      debugPrint('[Auth.verifyOtp] stack=$st');
      return false;
    }
  }

  /// 가입 OTP 이메일 재전송. cooldown 관리는 호출자 책임 (UI 의 60초 timer).
  Future<bool> resendEmailOtp(String email) async {
    debugPrint('[Auth.resendOtp] start email=$email');
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email,
      );
      debugPrint('[Auth.resendOtp] OK — Supabase 가 새 OTP 메일 발송 (이미 '
          'confirmed 사용자면 무발송, rate-limit 시 throw 가능)');
      return true;
    } catch (e, st) {
      debugPrint('[Auth.resendOtp] FAIL exception=$e');
      debugPrint('[Auth.resendOtp] stack=$st');
      return false;
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
    _setUser(null);
  }

  Future<int> refreshCoins() async {
    if (_currentUser == null) return 0;
    try {
      final row = await _client
          .from('users')
          .select('coins')
          .eq('id', _currentUser!.id)
          .single();
      final coins = row['coins'] as int;
      _setUser(_currentUser!.copyWith(coins: coins));
      return coins;
    } catch (e) {
      debugPrint('[Auth] refreshCoins error: $e');
      return _currentUser?.coins ?? 0;
    }
  }

  /// Spend coins via RPC. Returns true on success, false if insufficient.
  Future<bool> deductCoins(
    int amount, {
    String? referenceId,
    String? description,
  }) async {
    if (_currentUser == null) return false;
    final balance = await WalletService().spend(
      amount: amount,
      referenceId: referenceId,
      description: description,
    );
    if (balance < 0) return false;
    _setUser(_currentUser!.copyWith(coins: balance));
    return true;
  }

  /// Credit coins via RPC (purchase / bonus / refund). Returns new balance.
  Future<int> addCoins(
    int amount, {
    CoinTxKind kind = CoinTxKind.purchase,
    String? productId,
    String? storeTransactionId,
    String? description,
  }) async {
    if (_currentUser == null) return 0;
    final balance = await WalletService().grant(
      amount: amount,
      kind: kind,
      productId: productId,
      storeTransactionId: storeTransactionId,
      description: description,
    );
    _setUser(_currentUser!.copyWith(coins: balance));
    return balance;
  }

  AuthUser _mapUser(Map<String, dynamic> row) => AuthUser(
        id: row['id'] as String,
        kakaoUserId: row['kakao_user_id'] as String?,
        nickname: row['nickname'] as String?,
        profileImageUrl: row['profile_image_url'] as String?,
        coins: (row['coins'] as int?) ?? 0,
        signupBonusSkipped: (row['signup_bonus_skipped'] as bool?) ?? false,
      );

  void dispose() {
    _sub?.cancel();
    _profileChanged.close();
    _signupBonusSkippedNotice.close();
  }
}
