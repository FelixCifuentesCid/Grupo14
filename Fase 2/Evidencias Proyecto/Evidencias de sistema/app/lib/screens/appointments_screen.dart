import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/api.dart';
import '../core/auth_state.dart';
import '../widgets/common.dart';
import 'design_detail_screen.dart';

class AppointmentsScreen extends StatefulWidget {
  static const route = '/apts';
  const AppointmentsScreen({super.key});

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with WidgetsBindingObserver {
  late Future<List<Map<String, dynamic>>> _future;

  // --------- Estado para generar schedule (solo artista) ---------
  DateTime _schedFrom = DateTime.now().add(const Duration(days: 1));
  DateTime _schedTo = DateTime.now().add(const Duration(days: 7));
  TimeOfDay _schedStart = const TimeOfDay(hour: 10, minute: 0);
  TimeOfDay _schedEnd = const TimeOfDay(hour: 20, minute: 0);
  // 0 = lunes ... 6 = domingo (DateTime.weekday - 1)
  final List<bool> _schedDow = List<bool>.filled(7, true);
  bool _schedBusy = false;

  // --------- Estado para ver y gestionar módulos de un día ---------
  DateTime _slotsDay = DateTime.now();
  bool _slotsLoading = false;
  List<Map<String, dynamic>> _slots = <Map<String, dynamic>>[];

  // --------- Mostrar / ocultar agenda (solo tatuador) ---------
  bool _showAgenda = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _future = Api.myAppointments();

    if (authState.role == 'artist') {
      _slotsDay = DateTime.now();
      _loadSlotsForDay();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _future = Api.myAppointments();
    });
    await _future;
    if (authState.role == 'artist') {
      await _loadSlotsForDay();
    }
  }

  // ================== Acciones sobre citas ==================

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
      final okLaunch = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!okLaunch) throw 'No se pudo abrir el checkout';
      await Future.delayed(const Duration(seconds: 2));
      if (mounted) _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko('Pago: $e'));
    }
  }

  Future<void> _confirm(int id) async {
    try {
      await Api.confirmAppointment(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ok('Cita aprobada'));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko(e.toString()));
    }
  }

  Future<void> _reject(int id) async {
    try {
      await Api.rejectAppointment(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ok('Cita rechazada'));
      _refresh();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko(e.toString()));
    }
  }

  // ================== Generador de schedule (slots) ==================

  Future<void> _pickSchedDate({required bool from}) async {
    final now = DateTime.now();
    final initial = from ? _schedFrom : _schedTo;
    final first = now;
    final last = now.add(const Duration(days: 365));

    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null) return;

    setState(() {
      if (from) {
        _schedFrom = DateTime(picked.year, picked.month, picked.day);
        if (_schedTo.isBefore(_schedFrom)) {
          _schedTo = _schedFrom;
        }
      } else {
        _schedTo = DateTime(picked.year, picked.month, picked.day);
        if (_schedTo.isBefore(_schedFrom)) {
          _schedFrom = _schedTo;
        }
      }
    });
  }

  Future<void> _pickSchedTime({required bool start}) async {
    final current = start ? _schedStart : _schedEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
    );
    if (picked == null) return;

    setState(() {
      if (start) {
        _schedStart = picked;
        if (_schedEnd.hour <= _schedStart.hour) {
          _schedEnd = TimeOfDay(hour: _schedStart.hour + 1, minute: 0);
        }
      } else {
        _schedEnd = picked;
        if (_schedEnd.hour <= _schedStart.hour) {
          _schedStart = TimeOfDay(hour: _schedEnd.hour - 1, minute: 0);
        }
      }
    });
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _generateSchedule() async {
    final selectedDays = <int>[];
    for (var i = 0; i < 7; i++) {
      if (_schedDow[i]) selectedDays.add(i);
    }
    if (selectedDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Selecciona al menos un día de la semana'),
      );
      return;
    }

    if (_schedEnd.hour <= _schedStart.hour) {
      ScaffoldMessenger.of(context).showSnackBar(
        ko('La hora de término debe ser mayor a la hora de inicio'),
      );
      return;
    }

    setState(() {
      _schedBusy = true;
    });

    try {
      final count = await Api.generateSlots(
        from: _schedFrom,
        to: _schedTo,
        startHour: _schedStart.hour,
        endHour: _schedEnd.hour,
        daysOfWeek: selectedDays,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ok('Agenda generada: $count módulos creados'),
      );
      await _loadSlotsForDay();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Error generando agenda: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _schedBusy = false;
        });
      }
    }
  }

  Widget _buildScheduleCard(bool isArtist) {
    if (!isArtist) return const SizedBox.shrink();

    const dowLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Agenda del tatuador',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Genera módulos de 1 hora en un rango de fechas.\n'
              'Luego el cliente sólo podrá reservar en esos módulos.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickSchedDate(from: true),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('Desde: ${_fmtDate(_schedFrom)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickSchedDate(from: false),
                    icon: const Icon(Icons.calendar_today, size: 18),
                    label: Text('Hasta: ${_fmtDate(_schedTo)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickSchedTime(start: true),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('Inicio: ${_fmtTime(_schedStart)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickSchedTime(start: false),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('Término: ${_fmtTime(_schedEnd)}'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Días de la semana',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: List<Widget>.generate(7, (i) {
                final selected = _schedDow[i];
                return FilterChip(
                  label: Text(dowLabels[i]),
                  selected: selected,
                  onSelected: (v) {
                    setState(() {
                      _schedDow[i] = v;
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _schedBusy ? null : _generateSchedule,
                icon: _schedBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_schedBusy ? 'Generando...' : 'Generar módulos'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================== Gestión de módulos por día ==================

  Future<void> _pickSlotsDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _slotsDay.isBefore(now) ? now : _slotsDay,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _slotsDay = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadSlotsForDay();
  }

  Future<void> _loadSlotsForDay() async {
    if (authState.userId == null) return;
    setState(() {
      _slotsLoading = true;
    });
    try {
      final list = await Api.getSlotsForDay(
        artistId: authState.userId!,
        day: _slotsDay,
      );
      if (!mounted) return;
      setState(() {
        _slots = list;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Error cargando módulos: $e'),
      );
    } finally {
      if (mounted) {
        setState(() {
          _slotsLoading = false;
        });
      }
    }
  }

  Future<void> _toggleSlot(Map<String, dynamic> slot) async {
    final idAny = slot['id'];
    final int? id = idAny is int ? idAny : int.tryParse('$idAny');
    if (id == null) return;

    final bool enabled = slot['enabled'] == true;
    final bool hasAppointment = slot['has_appointment'] == true;

    if (hasAppointment) {
      ScaffoldMessenger.of(context).showSnackBar(
        ko('No puedes deshabilitar un módulo que ya tiene reserva'),
      );
      return;
    }

    // Optimistic update
    setState(() {
      slot['enabled'] = !enabled;
    });

    try {
      if (enabled) {
        await Api.disableSlot(id);
      } else {
        await Api.enableSlot(id);
      }
    } catch (e) {
      // revert
      setState(() {
        slot['enabled'] = enabled;
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Error actualizando módulo: $e'),
      );
    }
  }

  Widget _buildSlotsCard(bool isArtist) {
    if (!isArtist) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Módulos del día',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'Toca un módulo para habilitarlo o deshabilitarlo.\n'
              'Los módulos con reserva no se pueden deshabilitar.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickSlotsDay,
                    icon: const Icon(Icons.event, size: 18),
                    label: Text('Fecha: ${_fmtDate(_slotsDay)}'),
                  ),
                ),
                IconButton(
                  tooltip: 'Refrescar',
                  onPressed: _loadSlotsForDay,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_slotsLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8.0),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_slots.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No hay módulos configurados para este día.',
                  style: TextStyle(fontSize: 12),
                ),
              )
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _slots.map((s) {
                  final bool enabled = s['enabled'] == true;
                  final bool hasAppointment = s['has_appointment'] == true;
                  final String startIso = (s['start_time'] ?? '') as String;
                  final dt = DateTime.tryParse(startIso);
                  final String hourLabel = (dt == null)
                      ? '??:??'
                      : '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                  Color bg;
                  Color fg;
                  String tooltip;

                  if (hasAppointment) {
                    bg = Colors.green.shade200;
                    fg = Colors.black87;
                    tooltip = 'Reservado';
                  } else if (enabled) {
                    bg = Colors.blue.shade400;
                    fg = Colors.white;
                    tooltip = 'Habilitado (tap para deshabilitar)';
                  } else {
                    bg = Colors.grey.shade300;
                    fg = Colors.black87;
                    tooltip = 'Deshabilitado (tap para habilitar)';
                  }

                  return Tooltip(
                    message: tooltip,
                    child: ChoiceChip(
                      label: Text(hourLabel),
                      selected: enabled || hasAppointment,
                      onSelected: hasAppointment
                          ? null
                          : (_) {
                              _toggleSlot(s);
                            },
                      backgroundColor: bg,
                      selectedColor: bg,
                      labelStyle: TextStyle(color: fg),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ================== UI de status ==================

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
        case 'confirmed':
          bg = Colors.greenAccent.shade700;
          break;
        case 'rejected':
          bg = Colors.red.shade700;
          break;
        case 'canceled':
          bg = Colors.redAccent;
          break;
        case 'done':
          bg = Colors.blueGrey;
          break;
        default:
          bg = Colors.grey;
      }
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Chip(
          label: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          backgroundColor: bg,
          labelStyle: TextStyle(color: fg),
        ),
      ),
    );
  }

  // ================== Item de la lista ==================

  Widget _buildItem(
    BuildContext context,
    Map<String, dynamic> a, {
    required bool isArtist,
  }) {
    // id robusto
    final dynamic rawId = a['id'];
    final int? id =
        (rawId is int) ? rawId : int.tryParse((rawId ?? '').toString());

    final String status = (a['status'] ?? '—').toString();
    final bool paid = a['paid'] == true;
    final bool payNow = a['pay_now'] == true;

    final String when = (a['start_time'] ?? '').toString();
    final dynamic price = a['price'];
    final String priceStr = (price != null) ? '\$${price}' : '';

    // -------- diseño y artista (desde appointments/me enriquecido) --------
    final Map<String, dynamic>? design =
        (a['design'] is Map) ? Map<String, dynamic>.from(a['design']) : null;
    final Map<String, dynamic>? artist =
        (a['artist'] is Map) ? Map<String, dynamic>.from(a['artist']) : null;

    final dynamic _tmpDesignId = design?['id'] ?? a['design_id'];
    final int? designId = (_tmpDesignId is int)
        ? _tmpDesignId
        : int.tryParse((_tmpDesignId ?? '').toString());

    final int artistId = (() {
      final raw = a['artist_id'];
      if (raw is int) return raw;
      return int.tryParse((raw ?? '').toString()) ??
          (design?['artist_id'] ?? 0);
    })();

    final String artistName = (artist?['name'] ??
            design?['artist_name'] ??
            (artistId != 0 ? 'Artista #$artistId' : 'Artista'))
        .toString();

    final String artistAvatar = (artist?['avatar_url'] ??
            artist?['avatar'] ??
            design?['artist_avatar_url'] ??
            design?['artist_avatar'] ??
            '')
        .toString();

    final String designTitle =
        (design?['title'] ?? a['design_title'] ?? 'Diseño').toString();

    final String designDesc = (design?['description'] ?? '').toString();

    final String designThumb = (design?['image_url'] ??
            design?['thumb'] ??
            design?['thumbnail'] ??
            design?['image'] ??
            a['design_thumb'] ??
            a['design_thumbnail'] ??
            a['design_image'] ??
            a['thumbnail'] ??
            a['image'] ??
            a['photo'] ??
            a['photo_url'] ??
            a['preview'] ??
            a['preview_url'] ??
            a['cover'] ??
            a['cover_url'] ??
            '')
        .toString();

    // ======================= ITEM =======================
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MINIATURA → navega al detalle
          InkWell(
            onTap: () {
              if (!mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => DesignDetailScreen(
                    design: {
                      'id': designId ?? 0,
                      'title': designTitle,
                      'description': designDesc,
                      'price': price,
                      'image_url': designThumb,
                      'artist_id': artistId,
                      'artist_name': artistName,
                      'artist_avatar_url': artistAvatar,
                    },
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: (designThumb.isNotEmpty)
                  ? Image.network(
                      designThumb,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.image_not_supported),
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: const Icon(Icons.image_outlined),
                    ),
            ),
          ),

          const SizedBox(width: 12),

          // CONTENIDO
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Cita #${id ?? '—'}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(when),
                if (priceStr.isNotEmpty) Text('Monto: $priceStr'),
                Text('paid: $paid • pay_now: $payNow'),
                const SizedBox(height: 8),
                _statusChip(status, paid),
              ],
            ),
          ),

          const SizedBox(width: 12),

          // BOTONES
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (id != null)
                ..._buildActionsForRole(
                  id: id,
                  status: status,
                  paid: paid,
                  payNow: payNow,
                  isArtist: isArtist,
                ),
            ],
          ),
        ],
      ),
    );
  }

  List<Widget> _buildActionsForRole({
    required int id,
    required String status,
    required bool paid,
    required bool payNow,
    required bool isArtist,
  }) {
    final List<Widget> out = [];

    if (isArtist) {
      // Tatuador: aprobar/rechazar solicitudes y cancelar
      if (status == 'booked') {
        out.add(
          FilledButton(
            onPressed: () => _confirm(id),
            child: const Text('Aprobar'),
          ),
        );
        out.add(const SizedBox(height: 6));
        out.add(
          OutlinedButton(
            onPressed: () => _reject(id),
            child: const Text('Rechazar'),
          ),
        );
      }
      if (status == 'confirmed' || status == 'booked') {
        if (out.isNotEmpty) out.add(const SizedBox(height: 6));
        out.add(
          TextButton(
            onPressed: () => _cancel(id),
            child: const Text('Cancelar cita'),
          ),
        );
      }
    } else {
      // Cliente: cancelar / pagar (siempre pasarela)
      if (status == 'booked') {
        out.add(
          OutlinedButton(
            onPressed: () => _cancel(id),
            child: const Text('Cancelar'),
          ),
        );
        if (!paid) {
          out.add(const SizedBox(height: 8));
          out.add(
            FilledButton(
              onPressed: () => _payNow(id),
              child: const Text('Pagar'),
            ),
          );
        }
      }
    }

    return out;
  }

  // ================== BUILD ==================

  @override
  Widget build(BuildContext context) {
    final isArtist = authState.role == 'artist';

    return Scaffold(
      appBar: AppBar(
        title: Text(isArtist ? 'Agenda y reservas' : 'Mis reservas'),
        actions: [
          if (isArtist)
            IconButton(
              onPressed: () {
                setState(() {
                  _showAgenda = !_showAgenda;
                });
              },
              tooltip: _showAgenda ? 'Ocultar agenda' : 'Mostrar agenda',
              icon: Icon(
                _showAgenda
                    ? Icons.calendar_month
                    : Icons.calendar_month_outlined,
              ),
            ),
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Busy();
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final items = snap.data ?? const <Map<String, dynamic>>[];

          if (!isArtist) {
            // --------- Vista cliente (simplificada) ---------
            if (items.isEmpty) {
              return const Center(child: Text('No tienes reservas'));
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) =>
                    _buildItem(context, items[i], isArtist: false),
              ),
            );
          }

          // --------- Vista artista: agenda (opcional) + reservas ---------
          return Column(
            children: [
              if (_showAgenda) ...[
                _buildScheduleCard(true),
                _buildSlotsCard(true),
              ],
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _refresh,
                  child: items.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 16),
                            Center(
                              child: Text(
                                'No tienes reservas por ahora',
                                style: TextStyle(fontSize: 14),
                              ),
                            ),
                            SizedBox(height: 16),
                          ],
                        )
                      : ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (context, i) =>
                              _buildItem(context, items[i], isArtist: true),
                        ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
