import 'package:flutter/foundation.dart';

/// Estado global de autenticación.
/// - Evita importar Pns aquí para no generar dependencias circulares.
/// - Exponemos un hook `setOnAccessTokenChanged` para que Pns se registre
///   y pueda llamar a su `refreshRegistration()` cada vez que cambie el token.
class AuthState extends ChangeNotifier implements ValueListenable<AuthState> {
  String? token;         // access token (JWT)
  String? refreshToken;  // refresh token
  String? role;          // 'client' | 'artist'
  String? name;
  int? userId;

  /// Hook opcional (lo registra Pns en el arranque).
  void Function(String accessToken)? _onAccessTokenChanged;

  bool get isLoggedIn => token != null && token!.isNotEmpty;
  bool get isArtist => role == 'artist';
  bool get isClient => role == 'client';

  /// Registrar callback para cuando haya/actualice access token.
  /// Suele usarse en Pns.init():
  ///   authState.setOnAccessTokenChanged((t) => Pns.refreshRegistration());
  void setOnAccessTokenChanged(void Function(String accessToken)? cb) {
    _onAccessTokenChanged = cb;
  }

  /// Set completo de sesión (login / refresh con datos de usuario).
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

    // Dispara hook (si está configurado) para que Pns registre el token FCM.
    final t = this.token;
    if (t != null && t.isNotEmpty) {
      try {
        _onAccessTokenChanged?.call(t);
      } catch (_) {}
    }

    notifyListeners();
  }

  /// Solo actualiza el access token (por refresh).
  void updateAccess(String token) {
    this.token = token;

    final t = this.token;
    if (t != null && t.isNotEmpty) {
      try {
        _onAccessTokenChanged?.call(t);
      } catch (_) {}
    }

    notifyListeners();
  }

  /// Limpia la sesión (logout).
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
