import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/data/services/auth_service.dart';

final authProvider = NotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthUser?> {
  StreamSubscription<AuthUser?>? _sub;

  @override
  AuthUser? build() {
    _sub = AuthService().profileStream.listen((user) {
      state = user;
    });
    ref.onDispose(() => _sub?.cancel());
    return AuthService().currentUser;
  }

  /// Kakao OAuth. Browser opens asynchronously; the actual profile arrives
  /// through `profileStream` once the deep link redirects back. Returns
  /// whether the browser was launched.
  Future<bool> loginWithKakao() async {
    try {
      return await AuthService().loginWithKakao();
    } catch (e) {
      debugPrint('[AuthProvider] kakao login error: $e');
      return false;
    }
  }

  Future<bool> loginWithEmail(String email, String password) async {
    return AuthService().loginWithEmail(email, password);
  }

  Future<bool> signUpWithEmail(String email, String password) async {
    return AuthService().signUpWithEmail(email, password);
  }

  Future<void> logout() async {
    await AuthService().logout();
  }

  Future<void> refreshCoins() async {
    await AuthService().refreshCoins();
  }

  Future<bool> deductCoins(int amount, {String? description}) async {
    return AuthService().deductCoins(amount, description: description);
  }

  Future<void> addCoins(int amount) async {
    await AuthService().addCoins(amount);
  }

  bool get isLoggedIn => state != null;
  int get coins => state?.coins ?? 0;
}
