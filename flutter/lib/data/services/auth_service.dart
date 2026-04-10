import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:kakao_flutter_sdk/kakao_flutter_sdk.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import 'package:face_reader/core/hive/hive_setup.dart';

class AuthUser {
  final String id;
  final String kakaoUserId;
  final String? nickname;
  final String? profileImageUrl;
  final int coins;

  const AuthUser({
    required this.id,
    required this.kakaoUserId,
    this.nickname,
    this.profileImageUrl,
    required this.coins,
  });
}

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  Box<String> get _box => Hive.box<String>(HiveBoxes.auth);
  SupabaseClient get _client => Supabase.instance.client;

  AuthUser? _currentUser;
  AuthUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;

  /// Restore session from Hive on app start
  Future<void> restoreSession() async {
    final kakaoUserId = _box.get('kakao_user_id');
    if (kakaoUserId == null) return;

    try {
      final response = await _client
          .from('users')
          .select()
          .eq('kakao_user_id', kakaoUserId)
          .maybeSingle();

      if (response != null) {
        _currentUser = _mapUser(response);
        debugPrint('[Auth] session restored: ${_currentUser!.nickname}');
      } else {
        _box.clear();
      }
    } catch (e) {
      debugPrint('[Auth] restore failed: $e');
      // Offline — use cached data
      final nickname = _box.get('nickname');
      final coins = int.tryParse(_box.get('coins') ?? '') ?? 0;
      _currentUser = AuthUser(
        id: _box.get('user_id') ?? '',
        kakaoUserId: kakaoUserId,
        nickname: nickname,
        coins: coins,
      );
    }
  }

  /// Login with Kakao and create/get Supabase user
  Future<AuthUser> loginWithKakao() async {
    // Kakao login
    OAuthToken token;
    if (await isKakaoTalkInstalled()) {
      token = await UserApi.instance.loginWithKakaoTalk();
    } else {
      token = await UserApi.instance.loginWithKakaoAccount();
    }
    debugPrint('[Auth] kakao token: ${token.accessToken.substring(0, 10)}...');

    // Get Kakao user info
    final kakaoUser = await UserApi.instance.me();
    final kakaoUserId = kakaoUser.id.toString();
    final nickname = kakaoUser.kakaoAccount?.profile?.nickname;
    final profileImage = kakaoUser.kakaoAccount?.profile?.profileImageUrl;

    // Upsert to Supabase
    final existing = await _client
        .from('users')
        .select()
        .eq('kakao_user_id', kakaoUserId)
        .maybeSingle();

    Map<String, dynamic> userData;
    if (existing != null) {
      // Update nickname/profile if changed
      await _client.from('users').update({
        'nickname': nickname,
        'profile_image_url': profileImage,
      }).eq('kakao_user_id', kakaoUserId);
      userData = {
        ...existing,
        'nickname': nickname,
        'profile_image_url': profileImage,
      };
    } else {
      // New user — gets default 3 coins
      final result = await _client.from('users').insert({
        'kakao_user_id': kakaoUserId,
        'nickname': nickname,
        'profile_image_url': profileImage,
      }).select().single();
      userData = result;
    }

    _currentUser = _mapUser(userData);

    // Cache to Hive
    _box.put('kakao_user_id', kakaoUserId);
    _box.put('user_id', _currentUser!.id);
    _box.put('nickname', nickname ?? '');
    _box.put('coins', _currentUser!.coins.toString());

    // Link existing metrics to this user
    await _linkExistingMetrics();

    debugPrint('[Auth] logged in: $nickname, coins: ${_currentUser!.coins}');
    return _currentUser!;
  }

  /// Link existing Hive metrics (created before login) to this user in Supabase
  Future<void> _linkExistingMetrics() async {
    if (_currentUser == null) return;
    final historyBox = Hive.box<String>(HiveBoxes.history);
    final supabaseIds = <String>[];

    for (int i = 0; i < historyBox.length; i++) {
      final json = historyBox.getAt(i);
      if (json != null && json.contains('"supabaseId"')) {
        final match = RegExp(r'"supabaseId":"([^"]+)"').firstMatch(json);
        if (match != null) {
          supabaseIds.add(match.group(1)!);
        }
      }
    }

    if (supabaseIds.isEmpty) return;

    await _client
        .from('metrics')
        .update({'user_id': _currentUser!.id})
        .inFilter('id', supabaseIds)
        .isFilter('user_id', null);

    debugPrint('[Auth] linked ${supabaseIds.length} existing metrics to user');
  }

  /// Logout
  Future<void> logout() async {
    try {
      await UserApi.instance.logout();
    } catch (e) {
      debugPrint('[Auth] kakao logout error: $e');
    }
    _currentUser = null;
    _box.clear();
    debugPrint('[Auth] logged out');
  }

  /// Refresh coins from server
  Future<int> refreshCoins() async {
    if (_currentUser == null) return 0;
    final response = await _client
        .from('users')
        .select('coins')
        .eq('id', _currentUser!.id)
        .single();
    final coins = response['coins'] as int;
    _currentUser = AuthUser(
      id: _currentUser!.id,
      kakaoUserId: _currentUser!.kakaoUserId,
      nickname: _currentUser!.nickname,
      profileImageUrl: _currentUser!.profileImageUrl,
      coins: coins,
    );
    _box.put('coins', coins.toString());
    return coins;
  }

  /// Deduct coins (server-side)
  Future<bool> deductCoins(int amount) async {
    if (_currentUser == null) return false;
    final currentCoins = await refreshCoins();
    if (currentCoins < amount) return false;

    await _client
        .from('users')
        .update({'coins': currentCoins - amount})
        .eq('id', _currentUser!.id);

    _currentUser = AuthUser(
      id: _currentUser!.id,
      kakaoUserId: _currentUser!.kakaoUserId,
      nickname: _currentUser!.nickname,
      profileImageUrl: _currentUser!.profileImageUrl,
      coins: currentCoins - amount,
    );
    _box.put('coins', (currentCoins - amount).toString());
    return true;
  }

  /// Add coins (after purchase)
  Future<void> addCoins(int amount) async {
    if (_currentUser == null) return;
    final currentCoins = await refreshCoins();
    final newCoins = currentCoins + amount;

    await _client
        .from('users')
        .update({'coins': newCoins})
        .eq('id', _currentUser!.id);

    _currentUser = AuthUser(
      id: _currentUser!.id,
      kakaoUserId: _currentUser!.kakaoUserId,
      nickname: _currentUser!.nickname,
      profileImageUrl: _currentUser!.profileImageUrl,
      coins: newCoins,
    );
    _box.put('coins', newCoins.toString());
    debugPrint('[Auth] coins added: +$amount → $newCoins');
  }

  AuthUser _mapUser(Map<String, dynamic> data) => AuthUser(
        id: data['id'] as String,
        kakaoUserId: data['kakao_user_id'] as String,
        nickname: data['nickname'] as String?,
        profileImageUrl: data['profile_image_url'] as String?,
        coins: data['coins'] as int,
      );
}
