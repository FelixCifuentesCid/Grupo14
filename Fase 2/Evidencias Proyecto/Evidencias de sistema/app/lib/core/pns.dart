// lib/core/pns.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;

import 'auth_state.dart';

// ⚠️ AJUSTA ESTA URL A TU BACKEND
const String kBackendBaseUrl = 'http://167.114.145.34:8000';

// Canal Android para notificaciones con alta prioridad (foreground)
const AndroidNotificationChannel _channel = AndroidNotificationChannel(
  'high_importance',
  'Notificaciones',
  description: 'Canal para notificaciones importantes',
  importance: Importance.max,
  playSound: true,
  enableLights: true,
  enableVibration: true,
);

final FlutterLocalNotificationsPlugin _ln = FlutterLocalNotificationsPlugin();

class Pns {
  // 👉 Navigator global expuesto para main.dart y deep links
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static final FirebaseMessaging _fm = FirebaseMessaging.instance;
  static bool _inited = false;

  /// Inicialización principal (llamar una sola vez en app bootstrap).
  static Future<void> init() async {
    if (_inited) return;
    _inited = true;

    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp();
    } catch (_) {}

    // Android 13+: permiso en tiempo de ejecución para notificaciones
    if (Platform.isAndroid) {
      await _ln
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    // iOS: solicita permisos y cómo mostrar en foreground
    await _fm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
    );

    await _fm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Inicializa flutter_local_notifications
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );

    await _ln.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (resp) {
        final payloadStr = resp.payload;
        if (payloadStr == null || payloadStr.isEmpty) return;
        try {
          final Map<String, dynamic> data = jsonDecode(payloadStr);
          _routeFromData(data);
        } catch (_) {}
      },
    );

    // Crea/asegura el canal Android
    await _ln
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_channel);

    // Handlers FCM
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onOpenedFromNotification);

    // Mensaje que abrió la app desde "terminada"
    await handleInitialMessage();

    // 👉 Cada vez que cambie el access token (login / refresh),
    // volvemos a registrar el token FCM en el backend.
    authState.setOnAccessTokenChanged((_) {
      refreshRegistration();
    });

    // Registro inicial del token en backend (si ya hay sesión cargada al iniciar)
    await _registerTokenIfLoggedIn();

    // Si FCM renueva token, volvemos a registrar
    _fm.onTokenRefresh.listen((_) => _registerTokenIfLoggedIn());
  }

  /// Para obtener el token FCM actual (útil para debug).
  static Future<String?> getToken() async => _fm.getToken();

  /// Llamado si la app estaba terminada y se abrió desde una notificación.
  static Future<void> handleInitialMessage() async {
    final msg = await _fm.getInitialMessage();
    if (msg != null) {
      await _handleMessageRouting(msg);
    }
  }

  /// Foreground: mostramos notificación local y preparamos tap.
  static Future<void> _onForegroundMessage(RemoteMessage m) async {
    await _showLocalFromMessage(m);
  }

  /// Se llama cuando el usuario toca la notificación del sistema (background->foreground).
  static Future<void> _onOpenedFromNotification(RemoteMessage m) async {
    await _handleMessageRouting(m);
  }

  /// Handler para background (registrado en main). Debe ser top-level (ver al final).
  static Future<void> onBackgroundMessage(RemoteMessage m) async {
    try {
      await Firebase.initializeApp();
    } catch (_) {}
    await _showLocalFromMessage(m);
  }

  /// Compone y muestra local_notification desde el RemoteMessage recibido
  static Future<void> _showLocalFromMessage(RemoteMessage m) async {
    final data = Map<String, dynamic>.from(m.data);

    // Normaliza tipos/keys para compatibilidad con backend
    _normalizeDataInPlace(data);

    final title = _titleFrom(m, data);
    final body = _bodyFrom(m, data);

    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        styleInformation: BigTextStyleInformation(''),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // Guardamos data en payload para usarla en el tap handler de local_notifications
    final payload = jsonEncode(data);

    await _ln.show(
      _notifIdFromData(data),
      title,
      body,
      details,
      payload: payload,
    );
  }

  // Para poder usar const en NotificationDetails ↑
  static const String _channelId = _channelIdConst;
  static const String _channelName = _channelNameConst;
  static const String _channelDesc = _channelDescConst;
  static const String _channelIdConst = 'high_importance';
  static const String _channelNameConst = 'Notificaciones';
  static const String _channelDescConst = 'Canal para notificaciones importantes';

  /// Determina a dónde navegar según "type" y llaves adicionales del data.
  static Future<void> _routeFromData(Map<String, dynamic> data) async {
    // Normaliza antes de rutear
    _normalizeDataInPlace(data);

    final type = (data['type'] ?? '').toString();
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {
      case 'chat_message':
        // Aquí podrías abrir el detalle si pasas threadId; vamos a la lista si no:
        nav.pushNamed('/threads'); // ajusta si tu ruta es diferente
        break;

      case 'booking_requested':
      case 'booking_canceled':
      case 'payment_received':
      case 'booking_confirmed':
      case 'booking_rejected':
        nav.pushNamed('/appointments'); // ajusta si tu ruta es diferente
        break;

      default:
        final route = data['route']?.toString();
        if (route != null && route.isNotEmpty) {
          nav.pushNamed(route);
        }
        break;
    }
  }

  /// Lógica común para abrir rutas desde RemoteMessage (tap del sistema).
  static Future<void> _handleMessageRouting(RemoteMessage m) async {
    final data = Map<String, dynamic>.from(m.data);
    await _routeFromData(data);
  }

  // ---------- Registro del token en backend ----------

  /// Registra el token FCM del usuario logueado en /pns/register_token
  static Future<void> _registerTokenIfLoggedIn() async {
    if (!authState.isLoggedIn) return;
    final access = authState.token; // <- tu AuthState usa 'token'
    final token = await _fm.getToken();
    if (access == null || access.isEmpty || token == null || token.isEmpty) return;

    final platform = Platform.isIOS ? 'ios' : 'android';

    try {
      final uri = Uri.parse('$kBackendBaseUrl/pns/register_token');
      await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $access',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'token': token, 'platform': platform}),
      );
    } catch (_) {
      // No romper UX si falla el registro
    }
  }

  /// Llama esto tras login/refresh de sesión para forzar el registro inmediato
  static Future<void> refreshRegistration() => _registerTokenIfLoggedIn();

  /// Alias para compatibilidad con tu código existente
  static Future<void> registerCurrentToken() => refreshRegistration();

  // ---------- Helpers ----------

  /// Normaliza claves/valores para aceptar variantes que puede mandar el backend.
  /// - type: booking_canceled|booking_cancelled -> booking_canceled
  /// - type: booking_paid -> payment_received
  /// - type: payment_received -> payment_received
  /// - ids: appointment_id|booking_id|id -> appointment_id
  static void _normalizeDataInPlace(Map<String, dynamic> data) {
    final rawType = (data['type'] ??
            data['notification_type'] ??
            data['event'] ??
            '')
        .toString();

    String type = rawType;
    if (rawType == 'booking_cancelled') type = 'booking_canceled';
    if (rawType == 'booking_paid') type = 'payment_received';
    if (rawType == 'payment_received') type = 'payment_received';

    data['type'] = type;

    // Normaliza IDs
    data['appointment_id'] = data['appointment_id'] ??
        data['booking_id'] ??
        data['id'] ??
        data['appointmentId'] ??
        data['bookingId'];

    data['thread_id'] = data['thread_id'] ?? data['threadId'];

    // Copia title/body si vienen solo en notification.*
    data['title'] = data['title'] ?? data['notification_title'];
    data['body'] = data['body'] ?? data['notification_body'];
  }

  static int _notifIdFromData(Map<String, dynamic> data) {
    final threadId = data['thread_id'];
    final appointmentId = data['appointment_id'];
    final base = (threadId ?? appointmentId ?? data['type'] ?? '0').toString();
    return base.hashCode & 0x7fffffff;
  }

  static String _titleFrom(RemoteMessage m, Map<String, dynamic> data) {
    final ntfTitle = m.notification?.title;
    if (ntfTitle != null && ntfTitle.isNotEmpty) return ntfTitle;

    final dTitle = data['title']?.toString();
    if (dTitle != null && dTitle.isNotEmpty) return dTitle;

    final type = (data['type'] ?? '').toString();
    switch (type) {
      case 'chat_message':
        final from = data['sender_name'] ?? 'Nuevo mensaje';
        return '$from te escribió';
      case 'booking_requested':
        return 'Nueva solicitud de hora';
      case 'booking_canceled':
        return 'Reserva cancelada';
      case 'payment_received':
        return 'Reserva pagada';
      case 'booking_confirmed':
        return 'Reserva confirmada';
      case 'booking_rejected':
        return 'Reserva rechazada';
      default:
        return 'Notificación';
    }
  }

  static String _bodyFrom(RemoteMessage m, Map<String, dynamic> data) {
    final ntfBody = m.notification?.body;
    if (ntfBody != null && ntfBody.isNotEmpty) return ntfBody;

    final dBody = data['body']?.toString();
    if (dBody != null && dBody.isNotEmpty) return dBody;

    final type = (data['type'] ?? '').toString();
    switch (type) {
      case 'chat_message':
        return (data['text'] ?? 'Tienes un nuevo mensaje').toString();
      case 'booking_requested':
      case 'booking_canceled':
      case 'payment_received':
      case 'booking_confirmed':
      case 'booking_rejected':
        final when = data['when']?.toString();
        if (when != null && when.isNotEmpty) return 'Para $when';
        return 'Actualización de tu reserva';
      default:
        return 'Toca para abrir';
    }
  }
}

/// Handler top-level para background.
/// En tu main.dart registra:
/// FirebaseMessaging.onBackgroundMessage(pnsFirebaseBackgroundHandler);
@pragma('vm:entry-point')
Future<void> pnsFirebaseBackgroundHandler(RemoteMessage message) async {
  await Pns.onBackgroundMessage(message);
}
