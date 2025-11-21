// lib/core/deeplinks.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';

import '../core/api.dart';
import '../core/auth_state.dart';
import '../screens/appointments_screen.dart';

/// Gestor de deep links de la app.
/// Soporta:
///  - artattoo://pay-result?apt=<ID>&status=<approved|pending|failure>&payment_id=<opcional>
///  - https://<tu-dominio>/pay-result?apt=<ID>&status=<approved|pending|failure>&payment_id=<opcional>
class DeepLinks {
  static AppLinks? _links;
  static StreamSubscription<Uri>? _sub;

  // Para evitar manejar el mismo URI dos veces
  static String? _lastHandled;

  /// Inicializa escucha de deep links.
  /// Llamar una sola vez, idealmente en main() después de Api.init().
  static Future<void> init(GlobalKey<NavigatorState> navKey) async {
    // Instancia (idempotente)
    _links ??= AppLinks();

    // Si la app se abrió por un link (arranque en frío)
    try {
      final Uri? initial = await _links!.getInitialLink();
      if (initial != null) {
        // ignore: unawaited_futures
        _handleUri(initial, navKey);
      }
    } catch (_) {}

    // Suscripción a links recibidos con la app en foreground/background
    await _sub?.cancel();
    _sub = _links!.uriLinkStream.listen(
      (uri) {
        // ignore: unawaited_futures
        _handleUri(uri, navKey);
      },
      onError: (_) {},
      cancelOnError: false,
    );
  }

  /// Detiene la suscripción (opcional, por ejemplo al cerrar sesión).
  static Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _links = null;
    _lastHandled = null;
  }

  /// Lógica de ruteo y side-effects por deep link.
  static Future<void> _handleUri(Uri uri, GlobalKey<NavigatorState> navKey) async {
    final uriStr = uri.toString();
    if (_lastHandled == uriStr) return; // evita doble handling
    _lastHandled = uriStr;

    // artattoo://pay-result?... → host == "pay-result"
    if (uri.scheme.toLowerCase() == 'artattoo' && uri.host == 'pay-result') {
      await _handlePayResult(uri, navKey);
      return;
    }

    // https://<dominio>/pay-result?... → path termina en /pay-result
    if (uri.scheme.toLowerCase() == 'https' && uri.pathSegments.isNotEmpty) {
      if (uri.pathSegments.last == 'pay-result') {
        await _handlePayResult(uri, navKey);
        return;
      }
    }

    // Extiende aquí si agregas nuevos hosts o paths de deep links
  }

  /// Manejo de resultado de pago.
  /// - Si viene status=approved y apt (o appointment_id), intenta marcar pagado en backend.
  /// - Luego navega a Mis Citas y muestra un SnackBar con el resultado.
  static Future<void> _handlePayResult(Uri uri, GlobalKey<NavigatorState> navKey) async {
    final nav = navKey.currentState;
    if (nav == null) return;

    final qs = uri.queryParameters;
    final statusRaw = (qs['status'] ?? '').toLowerCase();
    final status = _normalizeStatus(statusRaw);

    // Aceptamos varias llaves de ID por compatibilidad
    final aptStr = qs['apt'] ?? qs['appointment_id'] ?? qs['booking_id'] ?? qs['id'];
    final apt = int.tryParse((aptStr ?? '').trim());

    // Acción principal a ejecutar (puede diferirse si no hay sesión)
    Future<void> run() async {
      bool forced = false;

      if (status == 'approved' && apt != null) {
        try {
          await Api.markPaid(apt); // POST /appointments/<id>/pay
          forced = true;
        } catch (_) {
          forced = false;
        }
      }

      // Ir a Mis Citas (su initState hace fetch y refleja el estado real)
      nav.pushNamedAndRemoveUntil(AppointmentsScreen.route, (r) => r.isFirst);

      // Aviso al usuario
      final ctx = navKey.currentContext;
      if (ctx != null) {
        final txt = forced
            ? 'Pago marcado para cita #$aptStr'
            : (status == 'pending')
                ? 'Pago pendiente para cita #$aptStr'
                : (status == 'failure')
                    ? 'Pago rechazado/cancelado para cita #$aptStr'
                    : 'Volviste desde pago';
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(txt)));
      }
    }

    // Si no hay sesión aún, difiere la ejecución hasta que el usuario inicie sesión.
    if (!authState.isLoggedIn) {
      _runWhenLoggedIn(run);
    } else {
      await run();
    }
  }

  /// Diferir una acción hasta que haya sesión; se ejecuta una sola vez.
  static void _runWhenLoggedIn(Future<void> Function() action) {
    if (authState.isLoggedIn) {
      // Ya logueado: ejecutar ahora
      // ignore: discarded_futures
      action();
      return;
    }
    // Escucha 1-shot
    void listener() {
      if (authState.isLoggedIn) {
        authState.removeListener(listener);
        // ignore: discarded_futures
        action();
      }
    }
    authState.addListener(listener);
  }

  /// Normaliza el status del pago
  /// - approved: "approved", "success", "authorized"
  /// - pending : "pending", "in_process", "inprocess"
  /// - failure : "failure", "failed", "rejected", "canceled", "cancelled", "denied"
  static String _normalizeStatus(String s) {
    switch (s) {
      case 'approved':
      case 'success':
      case 'authorized':
        return 'approved';
      case 'pending':
      case 'in_process':
      case 'inprocess':
        return 'pending';
      case 'failure':
      case 'failed':
      case 'rejected':
      case 'canceled':
      case 'cancelled':
      case 'denied':
        return 'failure';
      default:
        return s;
    }
  }
}
