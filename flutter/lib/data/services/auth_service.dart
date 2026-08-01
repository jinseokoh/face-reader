import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:facely/core/hive/hive_setup.dart';
import 'package:facely/data/services/wallet_service.dart';
import 'package:facely/domain/models/coin_transaction.dart';

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

  /// 오늘의 관상 공개 opt-in (facely.kr 홈 그리드 노출) — users
  /// .daily_face_opted_since 미러. null = 비공개, not null = 현재 연속 공개의
  /// 시작 시각 (연속 7일 유지 보너스 claim_daily_face_bonus RPC 판정 기준).
  /// 전환은 set_daily_face_opt_in RPC 만.
  final DateTime? dailyFaceOptedSince;

  bool get dailyFaceOptedIn => dailyFaceOptedSince != null;

  const AuthUser({
    required this.id,
    required this.coins,
    this.kakaoUserId,
    this.nickname,
    this.profileImageUrl,
    this.signupBonusSkipped = false,
    this.provider,
    this.dailyFaceOptedSince,
  });

  /// [dailyFaceOptedSince] 는 null 이 유효값(비공개 전환)이라 "미지정 = 유지"
  /// 를 sentinel 로 구분한다.
  static const _unset = Object();

  AuthUser copyWith({
    int? coins,
    String? nickname,
    Object? dailyFaceOptedSince = _unset,
  }) =>
      AuthUser(
        id: id,
        kakaoUserId: kakaoUserId,
        nickname: nickname ?? this.nickname,
        profileImageUrl: profileImageUrl,
        coins: coins ?? this.coins,
        signupBonusSkipped: signupBonusSkipped,
        provider: provider,
        dailyFaceOptedSince: identical(dailyFaceOptedSince, _unset)
            ? this.dailyFaceOptedSince
            : dailyFaceOptedSince as DateTime?,
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
      // 연속 7일 공개 유지 보너스 lazy 지급 — 설정에 안 들어와도 앱 시작
      // 시점에 달성분이 들어오게. 기수령이면 RPC 가 no-op (fire-and-forget).
      final since = mapped.dailyFaceOptedSince;
      if (since != null &&
          DateTime.now().isAfter(since.add(const Duration(days: 7)))) {
        unawaited(claimDailyFaceBonus());
      }
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

  /// Apple Sign In (네이티브) — iOS/macOS 전용. sign_in_with_apple 로 Apple ID
  /// credential 을 받아 Supabase `signInWithIdToken` 으로 교환한다. Kakao 와
  /// 달리 브라우저 없이 네이티브 시트로 즉시 세션이 생성되므로 (ok, message)
  /// 반환. 사용자가 시트를 닫으면 (ok:false, message:null) — 에러 표시 없이 조용히.
  Future<({bool ok, String? message})> loginWithApple() async {
    debugPrint('[Auth] loginWithApple: requesting Apple ID credential');
    try {
      // replay 방어 nonce — raw 는 Supabase 로, sha256 해시는 Apple 로.
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        debugPrint('[Auth] loginWithApple: identityToken null');
        return (ok: false, message: 'Apple 인증 토큰을 받지 못했습니다');
      }

      await _client.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      debugPrint('[Auth] loginWithApple: signInWithIdToken OK');
      return (ok: true, message: null);
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        debugPrint('[Auth] loginWithApple: user canceled');
        return (ok: false, message: null);
      }
      debugPrint('[Auth] apple sign-in error: ${e.code} ${e.message}');
      return (ok: false, message: 'Apple 로그인에 실패했습니다');
    } catch (e, st) {
      debugPrint('[Auth] apple sign-in error: $e\n$st');
      return (ok: false, message: _humanizeAuthError(e));
    }
  }

  /// Apple nonce 용 cryptographically secure 랜덤 문자열.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
        length, (_) => charset[random.nextInt(charset.length)]).join();
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
        'same_password' => '이전과 다른 비밀번호를 사용하세요',
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

  /// 비밀번호 재설정 1/3 — 등록된 이메일로 6자리 recovery OTP 발송.
  /// user-enumeration 방어로 미가입 이메일에도 성공 응답이 온다 (메일만 안 감).
  Future<({bool ok, String? message})> requestPasswordReset(
      String email) async {
    debugPrint('[Auth.pwReset] start email=$email');
    try {
      await _client.auth.resetPasswordForEmail(email);
      debugPrint('[Auth.pwReset] OK');
      return (ok: true, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.pwReset] FAIL: $e ($msg)\n$st');
      return (ok: false, message: msg);
    }
  }

  /// 비밀번호 재설정 2/3 — recovery OTP 검증. 성공 시 세션이 생기고
  /// onAuthStateChange 가 발화한다 (이 세션으로 3/3 의 updateUser 가 가능).
  Future<({bool ok, String? message})> verifyRecoveryOtp(
      String email, String token) async {
    debugPrint('[Auth.pwReset.verify] start email=$email '
        'tokenLen=${token.length}');
    try {
      final res = await _client.auth.verifyOTP(
        type: OtpType.recovery,
        email: email,
        token: token,
      );
      debugPrint('[Auth.pwReset.verify] OK userId=${res.user?.id} '
          'session=${res.session != null}');
      return (ok: true, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.pwReset.verify] FAIL: $e ($msg)\n$st');
      return (ok: false, message: msg);
    }
  }

  /// 비밀번호 재설정 3/3 — recovery 세션 상태에서 새 비밀번호 저장.
  Future<({bool ok, String? message})> updatePassword(String password) async {
    debugPrint('[Auth.pwReset.update] start pwLen=${password.length}');
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
      debugPrint('[Auth.pwReset.update] OK');
      return (ok: true, message: null);
    } catch (e, st) {
      final msg = _humanizeAuthError(e);
      debugPrint('[Auth.pwReset.update] FAIL: $e ($msg)\n$st');
      return (ok: false, message: msg);
    }
  }

  Future<void> logout() async {
    await _client.auth.signOut();
    _setUser(null);
  }

  /// 회원 탈퇴 — Cloudflare Worker `/api/account/delete` 호출:
  ///   1) R2 thumbnail 일괄 삭제
  ///   2) public.metrics row 삭제
  ///   3) auth.users 삭제 (cascade 로 users/coins/compatibilities 자동 삭제)
  ///
  /// 성공 시 local Hive 비우고 signOut. 재가입 시 bonus_recipients 영구
  /// 테이블 덕분에 보너스 코인 자동으로 0 지급.
  Future<({bool ok, String? message})> deleteAccount() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      return (ok: false, message: '로그인 상태가 아닙니다.');
    }
    try {
      final res = await http.post(
        Uri.parse('https://facely.kr/api/account/delete'),
        headers: {
          'Authorization': 'Bearer ${session.accessToken}',
        },
      );
      if (res.statusCode != 200) {
        debugPrint('[Auth.deleteAccount] HTTP ${res.statusCode}: ${res.body}');
        return (
          ok: false,
          message: '탈퇴 처리 실패 (${res.statusCode}). 잠시 후 다시 시도해 주세요.',
        );
      }
      // local cleanup — 어차피 logout 으로 user 사라지지만 Hive 잔여 강제 정리.
      try {
        await Hive.box<String>(HiveBoxes.history).clear();
        await Hive.box<String>(HiveBoxes.auth).clear();
      } catch (e) {
        debugPrint('[Auth.deleteAccount] Hive clear error: $e');
      }
      await _client.auth.signOut();
      _setUser(null);
      return (ok: true, message: null);
    } catch (e, st) {
      debugPrint('[Auth.deleteAccount] error: $e\n$st');
      return (ok: false, message: '네트워크 오류. 잠시 후 다시 시도해 주세요.');
    }
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

  /// 프로필 이름 변경 — 카카오 로그인 시 받아온 기본 nickname 을 사용자가
  /// 직접 수정. RLS users_self_update 로 본인 row 만 갱신 가능.
  Future<bool> updateNickname(String nickname) async {
    final user = _currentUser;
    if (user == null) return false;
    try {
      await _client
          .from('users')
          .update({'nickname': nickname}).eq('id', user.id);
      _setUser(user.copyWith(nickname: nickname));
      return true;
    } catch (e) {
      debugPrint('[Auth] updateNickname error: $e');
      return false;
    }
  }

  /// 오늘의 관상 공개 전환 — set_daily_face_opt_in RPC (baseline §14).
  /// 잠금 없음 — 언제든 전환 가능. 보너스는 선지급이 아니라 연속 7일 유지
  /// 달성 시 [claimDailyFaceBonus] 가 지급한다.
  Future<({bool ok, String? message})> setDailyFaceOptIn(bool optIn) async {
    final user = _currentUser;
    if (user == null) {
      return (ok: false, message: '로그인이 필요합니다');
    }
    try {
      final res = await _client
          .rpc('set_daily_face_opt_in', params: {'p_opt_in': optIn});
      final map = (res as Map).cast<String, dynamic>();
      _setUser(user.copyWith(
        dailyFaceOptedSince:
            DateTime.tryParse(map['opted_since'] as String? ?? ''),
      ));
      return (ok: true, message: null);
    } catch (e) {
      debugPrint('[Auth] setDailyFaceOptIn error: $e');
      return (ok: false, message: '설정 변경에 실패했습니다. 잠시 후 다시 시도해 주세요');
    }
  }

  /// 연속 7일 공개 유지 보너스 판정·지급 — claim_daily_face_bonus RPC.
  /// 조건 미달·기수령이어도 에러 없이 상태만 반환한다. granted = 이번
  /// 호출에서 3코인 지급됨(잔액 반영), already = 수령 완료 상태(UI 는
  /// 보너스 안내를 숨긴다). 실패는 (false, false) — 다음 호출에서 재시도.
  Future<({bool granted, bool already})> claimDailyFaceBonus() async {
    final user = _currentUser;
    if (user == null) return (granted: false, already: false);
    try {
      final res = await _client.rpc('claim_daily_face_bonus');
      final map = (res as Map).cast<String, dynamic>();
      _setUser(user.copyWith(
        coins: map['balance'] as int?,
        dailyFaceOptedSince:
            DateTime.tryParse(map['opted_since'] as String? ?? ''),
      ));
      return (
        granted: map['granted'] == true,
        already: map['already'] == true,
      );
    } catch (e) {
      debugPrint('[Auth] claimDailyFaceBonus error: $e');
      return (granted: false, already: false);
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
      dailyFaceOptedSince:
          DateTime.tryParse(row['daily_face_opted_since'] as String? ?? ''),
    );
  }

  void dispose() {
    _sub?.cancel();
    _profileChanged.close();
    _signupBonusSkippedNotice.close();
  }
}
