import 'package:flutter/material.dart';
import '../core/api.dart';
import '../widgets/common.dart';

class BookingScreen extends StatefulWidget {
  final int designId;
  final int artistId;

  const BookingScreen({
    super.key,
    required this.designId,
    required this.artistId,
  });

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  bool _busy = false;

  bool _loadingSlots = false;
  List<Map<String, dynamic>> _slots = <Map<String, dynamic>>[];
  int? _selectedSlotId;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loadingSlots = true;
      _slots = [];
      _selectedSlotId = null;
    });

    try {
      final slots = await Api.getSlotsForDay(
        artistId: widget.artistId,
        day: _date,
      );
      if (!mounted) return;
      setState(() {
        _slots = slots;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Error al cargar horarios: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loadingSlots = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(now) ? _date : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked != null) {
      setState(() {
        _date = DateTime(picked.year, picked.month, picked.day);
      });
      await _loadSlots();
    }
  }

  String _formatHourLabel(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Widget _buildSlotsGrid() {
    if (_loadingSlots) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_slots.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16.0),
        child: Text(
          'No hay módulos configurados para este día.\n'
          'Prueba con otra fecha.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _slots.map((s) {
        final int id = (s['id'] as int);
        final bool enabled = s['enabled'] == true;
        final bool hasAppointment = s['has_appointment'] == true;
        final String label = _formatHourLabel(s['start_time'] as String);

        final bool selectable = enabled && !hasAppointment;
        final bool selected = _selectedSlotId == id;

        Color? chipColor;
        if (!enabled) {
          chipColor = Colors.grey.shade300;
        } else if (hasAppointment) {
          chipColor = Colors.red.shade200;
        } else if (selected) {
          chipColor = Theme.of(context).colorScheme.primary;
        }

        Color? textColor;
        if (selected && selectable) {
          textColor = Colors.white;
        } else if (!enabled || hasAppointment) {
          textColor = Colors.grey.shade700;
        }

        String tooltip;
        if (!enabled) {
          tooltip = 'Módulo deshabilitado por el tatuador';
        } else if (hasAppointment) {
          tooltip = 'Módulo ya reservado';
        } else {
          tooltip = 'Disponible';
        }

        return Tooltip(
          message: tooltip,
          child: ChoiceChip(
            label: Text(label),
            selected: selected,
            onSelected: selectable
                ? (v) {
                    setState(() {
                      _selectedSlotId = v ? id : null;
                    });
                  }
                : null,
            selectedColor: chipColor,
            backgroundColor: chipColor,
            labelStyle: TextStyle(color: textColor),
          ),
        );
      }).toList(),
    );
  }

  Future<void> _book() async {
    if (_selectedSlotId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Selecciona un horario antes de continuar'),
      );
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await Api.bookFromSlot(
        designId: widget.designId,
        slotId: _selectedSlotId!,
        // IMPORTANTE: ahora el pago va después de la aprobación,
        // así que deja siempre payNow = false aquí.
        payNow: false,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        ok('Reserva enviada. El tatuador debe aprobarla antes del pago.'),
      );

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko(e.toString()),
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        '${_date.day.toString().padLeft(2, '0')}/${_date.month.toString().padLeft(2, '0')}/${_date.year}';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reservar cita'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '1) Elige el día',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(dateLabel),
              subtitle: const Text('Toca para cambiar la fecha'),
              trailing: const Icon(Icons.calendar_month_outlined),
              onTap: _pickDate,
            ),
            const Gap(12),
            const Text(
              '2) Elige un módulo de 1 hora',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildSlotsGrid(),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _book,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Solicitar reserva'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
