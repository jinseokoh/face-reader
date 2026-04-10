import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:face_reader/data/services/auth_service.dart';

final authProvider = NotifierProvider<AuthNotifier, AuthUser?>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthUser?> {
  @override
  AuthUser? build() => AuthService().currentUser;

  Future<bool> login() async {
    try {
      final user = await AuthService().loginWithKakao();
      state = user;
      return true;
    } catch (e) {
      debugPrint('[AuthProvider] login error: $e');
      return false;
    }
  }

  Future<void> logout() async {
    await AuthService().logout();
    state = null;
  }

  Future<void> refreshCoins() async {
    await AuthService().refreshCoins();
    state = AuthService().currentUser;
  }

  Future<bool> deductCoins(int amount) async {
    final success = await AuthService().deductCoins(amount);
    if (success) {
      state = AuthService().currentUser;
    }
    return success;
  }

  Future<void> addCoins(int amount) async {
    await AuthService().addCoins(amount);
    state = AuthService().currentUser;
  }

  bool get isLoggedIn => state != null;
  int get coins => state?.coins ?? 0;
}
