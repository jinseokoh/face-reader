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
  /// `auth.users.app_metadata.provider` — 'kakao' / 'email' 등. settings
  /// 페이지에서 "카카오 계정으로 로그인됨" / "이메일로 로그인됨" 분기 표시.
  final String? provider;

  const AuthUser({
    required this.id,
    required this.coins,
    this.kakaoUserId,
    this.nickname,
    this.profileImageUrl,
    this.signupBonusSkipped = false,
    this.provider,
  });

  AuthUser copyWith({int? coins}) => AuthUser(
        id: id,
        kakaoUserId: kakaoUserId,
        nickname: nickname,
        profileImageUrl: profileImageUrl,
        coins: coins ?? this.coins,
        signupBonusSkipped: signupBonusSkipped,
        provider: provider,
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

  /// Supabase Auth 의 exception 을 사용자가 이해할 수 있는 한국어 메시지로.
  /// snackbar 에 그대로 띄울 수 있는 형태.
  String _humanizeAuthError(Object e) {
    if (e is AuthApiException) {
      // code 가 있는 명시적 에러는 case 별 매핑. 없으면 message 노출.
      return switch (e.code) {
        'over_email_send_rate_limit' =>
          '이메일 발송 한도 초과. 잠시 후 다시 시도해주세요',
        'over_request_rate_limit' =>
          '요청이 너무 많습니다. 잠시 후 다시 시도해주세요',
        'weak_password' => '비밀번호가 너무 짧거나 약합니다',
        'email_address_invalid' => '유효하지 않은 이메일 주소입니다',
        'user_already_exists' => '이미 가입된 이메일입니다',
        'invalid_credentials' => '이메일 또는 비밀번호가 잘못됐습니다',
        'email_not_confirmed' => '이메일 인증이 안 됐습니다. 인증 후 다시 시도',
        'otp_expired' => '코드가 만료됐습니다. 재전송 후 다시 시도',
        'invalid_otp' => '잘못된 인증 코드입니다',
        'signup_disabled' => '현재 가입이 제한돼 있습니다',
        _ => e.message,
      };
    }
    return e.toString();
  }

  /// Email + password sign in. (ok, message). message 는 실패 시 사용자 표시용.
  Future<({bool ok, String? message})> loginWithEmail(
      String email, String password) async {
    debugPrint('[Auth.signIn] start email=$email');
    try {
      await _client.auth
          .signInWithPassword(email: email, password: password);
      debugPrint('[Auth.signIn] OK');
      return (ok: true, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.signIn] FAIL: $e\n$st');
      return (ok: false, message: msg);
    }
  }

  /// Email + password sign up. Supabase user-enumeration 방어 때문에 이미
  /// confirmed 가입자 이메일이어도 throw 안 하고 가짜 success — `user.identities`
  /// 가 비어있어 구분. (outcome, message). message 는 error outcome 일 때만.
  Future<({SignUpOutcome outcome, String? message})> signUpWithEmail(
      String email, String password) async {
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
        return (outcome: SignUpOutcome.error, message: '가입 응답이 비정상입니다');
      }
      if (identCount == 0) {
        debugPrint('[Auth.signUp] OUTCOME=alreadyRegistered');
        return (outcome: SignUpOutcome.alreadyRegistered, message: null);
      }
      debugPrint('[Auth.signUp] OUTCOME=newAccount');
      return (outcome: SignUpOutcome.newAccount, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.signUp] OUTCOME=error exception=$e ($msg)');
      debugPrint('[Auth.signUp] stack=$st');
      return (outcome: SignUpOutcome.error, message: msg);
    }
  }

  /// 가입 후 발송된 6자리 OTP 를 검증. 성공 시 onAuthStateChange 가 발화.
  Future<({bool ok, String? message})> verifyEmailOtp(
      String email, String token) async {
    debugPrint('[Auth.verifyOtp] start email=$email tokenLen=${token.length}');
    try {
      final res = await _client.auth.verifyOTP(
        type: OtpType.signup,
        email: email,
        token: token,
      );
      debugPrint('[Auth.verifyOtp] OK userId=${res.user?.id} '
          'session=${res.session != null}');
      return (ok: true, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.verifyOtp] FAIL: $e ($msg)\n$st');
      return (ok: false, message: msg);
    }
  }

  /// 가입 OTP 이메일 재전송.
  Future<({bool ok, String? message})> resendEmailOtp(String email) async {
    debugPrint('[Auth.resendOtp] start email=$email');
    try {
      await _client.auth.resend(type: OtpType.signup, email: email);
      debugPrint('[Auth.resendOtp] OK');
      return (ok: true, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.resendOtp] FAIL: $e ($msg)\n$st');
      return (ok: false, message: msg);
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

  AuthUser _mapUser(Map<String, dynamic> row) {
    // Supabase auth.users 의 app_metadata.provider 가 'kakao' / 'email' /
    // 'google' 등. settings UI 에서 "어느 경로로 로그인됐는지" 표시 용도.
    final providerRaw =
        _client.auth.currentUser?.appMetadata['provider'] as String?;
    return AuthUser(
      id: row['id'] as String,
      kakaoUserId: row['kakao_user_id'] as String?,
      nickname: row['nickname'] as String?,
      profileImageUrl: row['profile_image_url'] as String?,
      coins: (row['coins'] as int?) ?? 0,
      signupBonusSkipped: (row['signup_bonus_skipped'] as bool?) ?? false,
      provider: providerRaw,
    );
  }

  void dispose() {
    _sub?.cancel();
    _profileChanged.close();
    _signupBonusSkippedNotice.close();
  }
}
