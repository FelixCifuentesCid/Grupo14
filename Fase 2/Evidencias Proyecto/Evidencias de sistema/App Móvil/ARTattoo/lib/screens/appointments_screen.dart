import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../widgets/common.dart';

class AppointmentsScreen extends StatefulWidget {
  static const route = '/apts';
  const AppointmentsScreen({super.key});
  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  @override
  void initState() {
    super.initState();
    _future = Api.myAppointments();
  }

  Future<void> _refresh() async {
    setState(() => _future = Api.myAppointments());
    await _future;
  }

  Future<void> _cancel(int id) async {
    try {
      await Api.cancel(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ok('Cita cancelada'));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko(e.toString()));
    }
  }

  Future<void> _markPaid(int id) async {
    try {
      await Api.markPaid(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ok('Pago registrado'));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko(e.toString()));
    }
  }

  Future<void> _payNow(int appointmentId) async {
    try {
      final url = await Api.createCheckout(appointmentId);
      final launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!launched) throw 'No se pudo abrir el checkout';

      // Pequeño delay y refresh al volver de la app de pago
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko('Pago: $e'));
    }
  }

  Widget _statusChip(String status, bool paid) {
    Color bg;
    Color fg = Colors.white;
    String label = status;
    if (paid) {
      bg = Colors.green;
      label = '$status • PAGADO';
    } else {
      switch (status) {
        case 'booked':
          bg = Colors.orange;
          break;
        case 'cancelled':
          bg = Colors.redAccent;
          break;
        case 'done':
          bg = Colors.blueGrey;
          break;
        default:
          bg = Colors.grey;
      }
    }
    return Chip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reservas')),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return const Busy();
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final items = snap.data ?? const <Map<String, dynamic>>[];
          if (items.isEmpty) {
            return const Center(child: Text('No tienes reservas'));
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final a = items[i];
                final id = a['id'] as int;
                final status = (a['status'] ?? '—').toString();
                final paid = a['paid'] == true;
                final payNow = a['pay_now'] == true;

                final when = (a['start_time'] ?? '').toString();
                final price = a['price']; // si tu backend lo envía junto a la cita
                final priceStr = price != null ? '\$${price}' : '';

                return ListTile(
                  isThreeLine: true,
                  title: Row(
                    children: [
                      Text('Cita #$id', style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(width: 8),
                      _statusChip(status, paid),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 6),
                      Text(when),
                      if (priceStr.isNotEmpty) Text('Monto: $priceStr'),
                      Text('paid: $paid • pay_now: $payNow'),
                    ],
                  ),
                  trailing: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      if (status == 'booked')
                        OutlinedButton(
                          onPressed: () => _cancel(id),
                          child: const Text('Cancelar'),
                        ),
                      if (!paid && status == 'booked' && payNow != true)
                        FilledButton.tonal(
                          onPressed: () => _markPaid(id),
                          child: const Text('Marcar pago'),
                        ),
                      if (!paid && status == 'booked' && payNow == true)
                        FilledButton(
                          onPressed: () => _payNow(id),
                          child: const Text('Pagar ahora'),
                        ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
