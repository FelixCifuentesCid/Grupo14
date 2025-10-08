import 'package:flutter/foundation.dart';

class AuthState extends ChangeNotifier implements ValueListenable<AuthState> {
  String? token;         // access token
  String? refreshToken;  // refresh token
  String? role;          // 'client'|'artist'
  String? name;
  int? userId;

  bool get isLoggedIn => token != null && token!.isNotEmpty;

  void set({
    required String token,
    required String? refreshToken,
    required String role,
    required String name,
    required int userId,
  }) {
    this.token = token;
    this.refreshToken = refreshToken;
    this.role = role;
    this.name = name;
    this.userId = userId;
    notifyListeners();
  }

  void updateAccess(String token) {
    this.token = token;
    notifyListeners();
  }

  void clear() {
    token = null;
    refreshToken = null;
    role = null;
    name = null;
    userId = null;
    notifyListeners();
  }

  @override
  AuthState get value => this;
}

final authState = AuthState();
