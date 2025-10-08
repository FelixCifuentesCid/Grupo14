import 'package:flutter/material.dart';
import '../core/api.dart';
import '../widgets/common.dart';

class BookingScreen extends StatefulWidget {
  final int designId; final int artistId; const BookingScreen({super.key, required this.designId, required this.artistId});
  @override State<BookingScreen> createState()=> _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _time = const TimeOfDay(hour: 15, minute: 0);
  int _duration = 60; bool _payNow=false; bool _busy=false;

  Future<void> _book() async {
    final start = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    setState(()=>_busy=true);
    try{
      final res = await Api.book(designId: widget.designId, artistId: widget.artistId, start: start, durationMin: _duration, payNow: _payNow);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ok('Reserva creada (#${res['appointment_id']})'));
      Navigator.pop(context);
    } catch(e){ if (!mounted) return; ScaffoldMessenger.of(context).showSnackBar(ko(e.toString())); }
    setState(()=>_busy=false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reservar')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        ListTile(title: const Text('Día'), subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2,'0')}-${_date.day.toString().padLeft(2,'0')}'), trailing: const Icon(Icons.edit_calendar_outlined), onTap: () async {
          final picked = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 90)), initialDate: _date);
          if (picked!=null) setState(()=> _date=picked);
        }),
        ListTile(title: const Text('Hora'), subtitle: Text(_time.format(context)), trailing: const Icon(Icons.schedule_outlined), onTap: () async {
          final picked = await showTimePicker(context: context, initialTime: _time);
          if (picked!=null) setState(()=> _time=picked);
        }),
        ListTile(title: const Text('Duración (min)'), subtitle: Text('$_duration'), trailing: DropdownButton<int>(value:_duration, items: const [60,90,120].map((e)=> DropdownMenuItem(value:e, child: Text('$e'))).toList(), onChanged: (v)=> setState(()=> _duration=v??60))),
        SwitchListTile(value:_payNow, onChanged:(v)=> setState(()=> _payNow=v), title: const Text('Pagar ahora')),
        const Gap(10),
        FilledButton(onPressed:_busy?null:_book, child: _busy? const SizedBox(height:18,width:18,child:CircularProgressIndicator(strokeWidth: 2)) : const Text('Confirmar')),
      ]),
    );
  }
}
