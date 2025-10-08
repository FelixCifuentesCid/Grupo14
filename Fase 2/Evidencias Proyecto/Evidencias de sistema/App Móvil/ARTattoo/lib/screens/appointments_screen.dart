import 'package:flutter/material.dart';
import '../core/api.dart';
import '../widgets/common.dart';

class AppointmentsScreen extends StatefulWidget { 
  static const route='/apts'; 
  const AppointmentsScreen({super.key}); 
  @override State<AppointmentsScreen> createState()=> _AppointmentsScreenState(); 
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  late Future<List<Map<String,dynamic>>> _future;
  @override void initState(){ super.initState(); _future = Api.myAppointments(); }
  Future<void> _refresh() async { setState(()=> _future = Api.myAppointments()); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mis reservas')),
      body: FutureBuilder(
        future: _future,
        builder: (_, snap){
          if (!snap.hasData) return const Busy();
          final items = snap.data as List<Map<String,dynamic>>;
          if (items.isEmpty) return const Center(child: Text('No tienes reservas'));
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __)=> const Divider(height: 1),
              itemBuilder: (_, i){
                final a = items[i];
                return ListTile(
                  title: Text('Cita #${a['id']} • ${a['status']}'),
                  subtitle: Text('${a['start_time']} • paid: ${a['paid']} • pay_now: ${a['pay_now']}'),
                  trailing: Wrap(spacing: 8, children: [
                    if (a['status']=='booked') OutlinedButton(onPressed: () async { 
                      try{ await Api.cancel(a['id']); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(ok('Cita cancelada')); _refresh(); } 
                      catch(e){ ScaffoldMessenger.of(context).showSnackBar(ko(e.toString())); } 
                    }, child: const Text('Cancelar')),
                    if (!a['paid']) FilledButton.tonal(onPressed: () async {
                      try{ await Api.markPaid(a['id']); if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(ok('Pago registrado')); _refresh(); } 
                      catch(e){ ScaffoldMessenger.of(context).showSnackBar(ko(e.toString())); } 
                    }, child: const Text('Marcar pago')),
                  ]),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
