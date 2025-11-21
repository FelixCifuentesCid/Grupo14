// lib/core/api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_state.dart';

class Api {
  // Usa SIEMPRE el mismo host que valida los JWT (backend Flask)
  static const String base = 'http://167.114.145.34:8000';
  // Servidor de pagos (Node / Mercado Pago)
  static const String paymentsBase = 'http://167.114.145.34:8001';

  static SharedPreferences? _prefs;

  // -------------------- Bootstrap --------------------
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();

    final t  = _prefs?.getString('token');
    final rt = _prefs?.getString('refresh_token');
    final r  = _prefs?.getString('role');
    final n  = _prefs?.getString('name');
    final id = _prefs?.getInt('uid');

    if (t != null && r != null && n != null && id != null) {
      authState.set(
        token: t,
        refreshToken: rt,
        role: r,
        name: n,
        userId: id,
      );
    } else {
      authState.clear();
    }
  }

  // -------------------- Storage --------------------
  static Future<void> _save(Map data) async {
    final access  = data['access_token'] as String?;
    final refresh = data['refresh_token'] as String?;
    final role    = data['role'] as String?;
    final name    = data['name'] as String?;
    final uidAny  = data['user_id'];

    final uid = uidAny is int ? uidAny : int.tryParse('$uidAny');

    if (access != null) await _prefs?.setString('token', access);
    if (refresh != null) await _prefs?.setString('refresh_token', refresh);
    if (role != null) await _prefs?.setString('role', role);
    if (name != null) await _prefs?.setString('name', name);
    if (uid != null) await _prefs?.setInt('uid', uid);

    if (access != null && role != null && name != null && uid != null) {
      authState.set(
        token: access,
        refreshToken: refresh,
        role: role,
        name: name,
        userId: uid,
      );
    }
  }

  static Future<void> logout() async {
    await _prefs?.clear();
    authState.clear();
  }

  static Future<void> registerPushToken(String token, {String platform = 'android'}) async {
    try {
      final uri = Uri.parse('$base/push/register');
      await authedPost(uri, body: jsonEncode({'token': token, 'platform': platform}));
    } catch (_) {}
  }

  // -------------------- Headers --------------------
  static Map<String, String> _headers({bool withAuth = true, String? tokenOverride}) {
    final h = {'Content-Type': 'application/json'};
    if (withAuth) {
      final t = tokenOverride ?? authState.token;
      if (t != null && t.isNotEmpty) {
        h['Authorization'] = 'Bearer $t';
      }
    }
    return h;
  }

  // Para servidor de pagos (Node): no enviamos Authorization
  static Map<String, String> _headersNode({bool json = true}) {
    return { if (json) 'Content-Type': 'application/json' };
  }

  // -------------------- JWT (exp / refresh) --------------------
  static int? _jwtExp(String jwt) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = utf8.decode(base64Url.decode(base64Url.normalize(parts[1])));
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is int) return exp;
      if (exp is String) return int.tryParse(exp);
    } catch (_) {}
    return null;
  }

  static bool _isExpiringSoon(String jwt, {int seconds = 60}) {
    final exp = _jwtExp(jwt);
    if (exp == null) return false;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return (exp - now) <= seconds;
  }

  static Future<String?> _refreshAccessToken() async {
    final rt = authState.refreshToken;
    if (rt == null || rt.isEmpty) return null;

    final r = await http.post(
      Uri.parse('$base/auth/refresh'),
      headers: _headers(tokenOverride: rt),
    );
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      final newTok = data['access_token'] as String?;
      if (newTok != null) {
        await _prefs?.setString('token', newTok);
        authState.updateAccess(newTok);
      }
      return newTok;
    }
    return null;
  }

  static Future<String?> ensureValidToken() async {
    final tok = authState.token;
    if (tok == null || tok.isEmpty) return null;
    if (_isExpiringSoon(tok)) {
      return await _refreshAccessToken() ?? tok;
    }
    return tok;
  }

  // -------------------- Requests con retry 401 --------------------
  static Future<http.Response> authedGet(Uri uri) async {
    await ensureValidToken();
    var resp = await http.get(uri, headers: _headers());
    if (resp.statusCode == 401) {
      final newTok = await _refreshAccessToken();
      if (newTok != null) {
        resp = await http.get(uri, headers: _headers());
      }
    }
    return resp;
  }

  static Future<http.Response> authedPost(Uri uri, {Object? body}) async {
    await ensureValidToken();
    var resp = await http.post(uri, headers: _headers(), body: body);
    if (resp.statusCode == 401) {
      final newTok = await _refreshAccessToken();
      if (newTok != null) {
        resp = await http.post(uri, headers: _headers(), body: body);
      }
    }
    return resp;
  }

  static Future<http.Response> authedPut(Uri uri, {Object? body}) async {
    await ensureValidToken();
    var resp = await http.put(uri, headers: _headers(), body: body);
    if (resp.statusCode == 401) {
      final newTok = await _refreshAccessToken();
      if (newTok != null) {
        resp = await http.put(uri, headers: _headers(), body: body);
      }
    }
    return resp;
  }

  static Future<http.Response> authedDelete(Uri uri) async {
    await ensureValidToken();
    var resp = await http.delete(uri, headers: _headers());
    if (resp.statusCode == 401) {
      final newTok = await _refreshAccessToken();
      if (newTok != null) {
        resp = await http.delete(uri, headers: _headers());
      }
    }
    return resp;
  }

  // -------------------- Auth --------------------
  static Future<String?> login(String email, String pass) async {
    final r = await http.post(
      Uri.parse('$base/auth/login'),
      headers: _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': pass}),
    );
    if (r.statusCode == 200) {
      final data = jsonDecode(r.body) as Map<String, dynamic>;
      await _save(data);
      return null;
    }
    try {
      return (jsonDecode(r.body) as Map)['msg'] as String?;
    } catch (_) {
      return 'Error de login';
    }
  }

  static Future<String?> register({
    required String email,
    required String pass,
    required String name,
    required String role,
  }) async {
    final r = await http.post(
      Uri.parse('$base/auth/register'),
      headers: _headers(withAuth: false),
      body: jsonEncode({'email': email, 'password': pass, 'role': role, 'name': name}),
    );
    if (r.statusCode == 201) {
      final err = await login(email, pass);
      return err; // null si ok
    }
    try {
      return (jsonDecode(r.body) as Map)['msg'] as String?;
    } catch (_) {
      return 'Error de registro';
    }
  }

  // -------------------- Designs --------------------
  /// Soporta filtro por artista y búsqueda:
  /// - q.startsWith('@') => por nombre/email de artista
  /// - q normal          => por título/descr
  /// Si hay token, usa GET autenticado para obtener `is_favorited`.
  static Future<List<Map<String, dynamic>>> getDesigns({int? artistId, String? q, bool bustCache = false}) async {
    final params = <String, String>{};
    if (artistId != null) params['artist_id'] = '$artistId';
    if (q != null && q.trim().isNotEmpty) params['q'] = q.trim();
    if (bustCache) params['_ts'] = DateTime.now().microsecondsSinceEpoch.toString();

    final uri = Uri.parse('$base/designs')
        .replace(queryParameters: params.isEmpty ? null : params);

    final t = authState.token;
    final r = (t == null || t.isEmpty)
        ? await http.get(uri, headers: {'Cache-Control': 'no-cache'})
        : await authedGet(uri);

    if (r.statusCode != 200) throw Exception('No se pudo cargar el catálogo');
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  static Future<Map?> createDesign({
    required String title,
    String? description,
    String? imageUrl,
    int? price,
  }) async {
    final r = await authedPost(
      Uri.parse('$base/designs'),
      body: jsonEncode({
        'title': title,
        'description': description,
        'image_url': imageUrl,
        'price': price,
      }),
    );
    if (r.statusCode != 201) {
      throw Exception(_safeMsg(r.body) ?? 'Error creando diseño');
    }
    return jsonDecode(r.body);
  }

  static Future<Map?> updateDesign({
    required int id,
    required String title,
    String? description,
    String? imageUrl,
    int? price,
  }) async {
    final r = await authedPut(
      Uri.parse('$base/designs/$id'),
      body: jsonEncode({
        'title': title,
        'description': description,
        'image_url': imageUrl,
        'price': price,
      }),
    );
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'Error actualizando diseño');
    }
    return jsonDecode(r.body);
  }

  static Future<void> deleteDesign(int id) async {
    final r = await authedDelete(Uri.parse('$base/designs/$id'));
    if (r.statusCode != 200 && r.statusCode != 204) {
      throw Exception(_safeMsg(r.body) ?? 'Error al eliminar diseño');
    }
  }

  // -------------------- Favoritos --------------------
  static Future<void> addFavorite(int designId) async {
    final r = await authedPost(Uri.parse('$base/designs/$designId/favorite'));
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'Error al agregar a favoritos');
    }
  }

  static Future<void> removeFavorite(int designId) async {
    final r = await authedDelete(Uri.parse('$base/designs/$designId/favorite'));
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'Error al quitar de favoritos');
    }
  }

  static Future<List<Map<String,dynamic>>> myFavorites() async {
    final r = await authedGet(Uri.parse('$base/favorites/me'));
    if (r.statusCode != 200) throw Exception('Error al cargar favoritos');
    return List<Map<String,dynamic>>.from(jsonDecode(r.body));
  }

  // -------------------- Artista --------------------
  static Future<Map<String,dynamic>> getArtist(int id) async {
    final r = await http.get(Uri.parse('$base/artists/$id'));
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'Artista no encontrado');
    }
    return Map<String,dynamic>.from(jsonDecode(r.body));
  }

  // -------------------- Appointments --------------------
  /// MODO ANTIGUO (libre): reservar pasando start y duración.
  /// Idealmente dejar de usar y migrar a bookFromSlot().
  static Future<Map> book({
    required int designId,
    required int artistId,
    required DateTime start,
    int durationMin = 60,
    bool payNow = false,
  }) async {
    final r = await authedPost(
      Uri.parse('$base/appointments'),
      body: jsonEncode({
        'design_id': designId,
        'artist_id': artistId,
        'start_time': start.toIso8601String(),
        'duration_minutes': durationMin,
        'pay_now': payNow,
      }),
    );
    if (r.statusCode >= 400) {
      throw Exception(_safeMsg(r.body) ?? 'Error al reservar');
    }
    return jsonDecode(r.body);
  }

  /// NUEVO: reserva basada en módulo (TimeSlot).
  /// El pago ocurre después de la aprobación del tatuador, así que usa payNow=false.
  static Future<Map<String, dynamic>> bookFromSlot({
    required int designId,
    required int slotId,
    bool payNow = false,
  }) async {
    final r = await authedPost(
      Uri.parse('$base/appointments/from_slot'),
      body: jsonEncode({
        'design_id': designId,
        'slot_id': slotId,
        'pay_now': payNow,
      }),
    );
    if (r.statusCode >= 400) {
      throw Exception(_safeMsg(r.body) ?? 'Error al reservar');
    }
    return Map<String, dynamic>.from(jsonDecode(r.body));
  }

  /// Obtener los módulos de 1 hora para un artista en un día.
  static Future<List<Map<String, dynamic>>> getSlotsForDay({
    required int artistId,
    required DateTime day,
  }) async {
    final dateStr =
        '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';

    final uri = Uri.parse('$base/artists/$artistId/slots')
        .replace(queryParameters: {'date': dateStr});

    final r = await authedGet(uri);
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No se pudieron cargar los horarios');
    }
    final data = jsonDecode(r.body);
    return List<Map<String, dynamic>>.from(data as List);
  }

  /// El tatuador acepta una reserva (status => confirmed).
  static Future<void> confirmAppointment(int id) async {
    final r = await authedPost(Uri.parse('$base/appointments/$id/confirm'));
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No se pudo confirmar la reserva');
    }
  }

  /// El tatuador rechaza una reserva (status => rejected) y libera el módulo.
  static Future<void> rejectAppointment(int id) async {
    final r = await authedPost(Uri.parse('$base/appointments/$id/reject'));
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No se pudo rechazar la reserva');
    }
  }

  static Future<List<Map<String, dynamic>>> myAppointments() async {
    final r = await authedGet(Uri.parse('$base/appointments/me'));
    if (r.statusCode != 200) throw Exception('Error al cargar reservas');
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  static Future<void> markPaid(int id) async {
    final r = await authedPost(Uri.parse('$base/appointments/$id/pay'));
    if (r.statusCode != 200) throw Exception('No se pudo marcar pago');
  }

  static Future<void> cancel(int id) async {
    final r = await authedPost(Uri.parse('$base/appointments/$id/cancel'));
    if (r.statusCode != 200) throw Exception('No se pudo cancelar');
  }

  /// Genera módulos de 1 hora para el tatuador autenticado.
  /// Devuelve la cantidad de slots creados.
  static Future<int> generateSlots({
    required DateTime from,
    required DateTime to,
    required int startHour,
    required int endHour,
    required List<int> daysOfWeek, // 0=lunes ... 6=domingo
  }) async {
    String _fmt(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    final body = {
      'from_date': _fmt(from),
      'to_date': _fmt(to),
      'start_hour': startHour,
      'end_hour': endHour,
      'days_of_week': daysOfWeek,
    };

    final r = await authedPost(
      Uri.parse('$base/artist/slots/generate'),
      body: jsonEncode(body),
    );

    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No se pudo generar la agenda');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['count'] as int?) ?? 0;
  }

  /// Habilita un módulo (slot) del tatuador autenticado.
  static Future<void> enableSlot(int slotId) async {
    final r = await authedPost(
      Uri.parse('$base/artist/slots/$slotId/enable'),
    );
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No se pudo habilitar el módulo');
    }
  }

  /// Deshabilita un módulo (slot) del tatuador autenticado.
  static Future<void> disableSlot(int slotId) async {
    final r = await authedPost(
      Uri.parse('$base/artist/slots/$slotId/disable'),
    );
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No se pudo deshabilitar el módulo');
    }
  }

  // -------------------- Pagos (confirmación bajo demanda) --------------------
  /// Crea el checkout y devuelve la URL (init_point).
  static Future<String> createCheckout(int appointmentId) async {
    // Endpoint en el servidor de pagos (Node)
    final uri = Uri.parse('$paymentsBase/payments/create');

    final r = await http.post(
      uri,
      headers: _headersNode(),
      body: jsonEncode({'appointment_id': appointmentId}),
    );

    if (r.statusCode == 404) {
      throw Exception('Endpoint /payments/create no disponible en el servidor de pagos');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw Exception(_safeMsg(r.body) ?? 'Error al crear pago');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return (data['sandbox_init_point'] as String?) ?? (data['init_point'] as String);
  }

  /// Confirma contra Node si hay pago approved para esa cita.
  /// Node, si ve approved, notifica al backend Flask y SOLO entonces responde paid:true.
  static Future<bool> confirmPayment(int appointmentId, {String? paymentId}) async {
    final uri = Uri.parse('$paymentsBase/payments/confirm');
    final payload = <String, dynamic>{'appointment_id': appointmentId};
    if (paymentId != null && paymentId.isNotEmpty) payload['payment_id'] = paymentId;

    final r = await http.post(
      uri,
      headers: _headersNode(),
      body: jsonEncode(payload),
    );

    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No fue posible confirmar pago');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return data['paid'] == true;
  }

  static Future<String> mpLinkUrl() async {
    final uri = Uri.parse('$base/mp/link');
    final r = await authedGet(uri);
    if (r.statusCode == 404) {
      throw Exception('Endpoint /mp/link no disponible en el backend');
    }
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'No fue posible obtener el link de Mercado Pago');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final url = data['auth_url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Respuesta inválida desde /mp/link');
    }
    return url;
  }

  // -------------------- Upload (imágenes para chat) --------------------
  static Future<String> uploadImageBase64(String b64) async {
    final r = await authedPost(
      Uri.parse('$base/upload/image'),
      body: jsonEncode({"base64": b64}),
    );
    if (r.statusCode != 200) {
      throw Exception(_safeMsg(r.body) ?? 'Error subiendo imagen');
    }
    final m = jsonDecode(r.body) as Map<String, dynamic>;
    final url = m['url'] as String?;
    if (url == null || url.isEmpty) throw Exception('Respuesta inválida al subir imagen');
    return url;
  }

  // -------------------- Utils --------------------
  static String? _safeMsg(String body) {
    try {
      final m = jsonDecode(body);
      if (m is Map && m['msg'] is String) return m['msg'] as String;
    } catch (_) {}
    return null;
  }
}
