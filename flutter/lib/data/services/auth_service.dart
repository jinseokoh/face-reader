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

/// Singleton auth service backed by Supabase Auth. Kakao OAuth + Email both
/// route through the same `auth.users` table; `public.users` row + signup
/// bonus are created by the `on_auth_user_created` DB trigger.
class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  static const _redirectUrl = 'face-reader://auth-callback';

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
    _sub = _client.auth.onAuthStateChange.listen((state) async {
      final session = state.session;
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
      _setUser(null);
      return;
    }
    try {
      final row = await _client
          .from('users')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();
      if (row == null) {
        debugPrint('[Auth] public.users row missing for ${authUser.id} '
            '— trigger may have failed');
        _setUser(null);
        return;
      }
      _setUser(_mapUser(row));
      debugPrint('[Auth] profile loaded: ${_currentUser!.nickname}');
    } catch (e) {
      debugPrint('[Auth] profile load failed: $e');
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
    try {
      return await _client.auth.signInWithOAuth(
        OAuthProvider.kakao,
        redirectTo: _redirectUrl,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('[Auth] kakao oauth error: $e');
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

  /// Email + password sign up. Depending on "Confirm email" setting in the
  /// dashboard, user may receive a confirmation mail first.
  Future<bool> signUpWithEmail(String email, String password) async {
    try {
      await _client.auth
          .signUp(email: email, password: password, emailRedirectTo: _redirectUrl);
      return true;
    } catch (e) {
      debugPrint('[Auth] email signup error: $e');
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
