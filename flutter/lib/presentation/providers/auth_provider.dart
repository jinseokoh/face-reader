import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facely/data/services/auth_service.dart';

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

  /// Apple Sign In (네이티브, iOS/macOS). 즉시 세션이 생성되므로 (ok, message).
  Future<({bool ok, String? message})> loginWithApple() async {
    return AuthService().loginWithApple();
  }

  Future<({bool ok, String? message})> loginWithEmail(
      String email, String password) async {
    return AuthService().loginWithEmail(email, password);
  }

  Future<({SignUpOutcome outcome, String? message})> signUpWithEmail(
      String email, String password) async {
    return AuthService().signUpWithEmail(email, password);
  }

  Future<({bool ok, String? message})> verifyEmailOtp(
      String email, String token) async {
    return AuthService().verifyEmailOtp(email, token);
  }

  Future<({bool ok, String? message})> resendEmailOtp(String email) async {
    return AuthService().resendEmailOtp(email);
  }

  Future<void> logout() async {
    await AuthService().logout();
  }

  Future<({bool ok, String? message})> deleteAccount() async {
    return AuthService().deleteAccount();
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
