import 'dart:async';
import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/auth_state.dart';
import '../widgets/common.dart';
import '../core/chat_api.dart';
import 'threads_screen.dart';
import 'design_detail_screen.dart';
import 'appointments_screen.dart';
import 'create_design_screen.dart';

class CatalogScreen extends StatefulWidget {
  static const route = '/catalog';
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  // ---- Unread badge ----
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _future = Api.getDesigns();
    _startUnreadPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // ---- Polling de no leídos ----
  void _startUnreadPolling() {
    _fetchUnread(); // primer fetch inmediato
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _fetchUnread());
  }

  Future<void> _fetchUnread() async {
    try {
      final t = authState.token;
      if (t == null || t.isEmpty) {
        if (mounted && _unread != 0) setState(() => _unread = 0);
        return;
      }
      final api = ChatApi(t);
      final threads = await api.listThreads();
      int total = 0;
      for (final th in threads) {
        final v = th['unread'];
        if (v is int) total += v;
        if (v is String) total += int.tryParse(v) ?? 0;
      }
      if (mounted && total != _unread) setState(() => _unread = total);
    } catch (_) {
      // Silenciar fallos intermitentes
    }
  }

  // ---- Acciones ----
  Future<void> _refresh() async {
    setState(() => _future = Api.getDesigns());
  }

  Future<void> _goCreateDesign() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CreateDesignScreen()),
    );
    if (mounted) _refresh();
  }

  void _goThreads() {
    final t = authState.token;
    if (t == null || t.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Debes iniciar sesión')));
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ThreadsScreen(api: ChatApi(t))),
    ).then((_) {
      // refresca contador al volver
      _fetchUnread();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Diseños',
      actions: [
        // ---- Botón de chats con badge rojo ----
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: _goThreads,
                icon: const Icon(Icons.chat_bubble_outline),
                tooltip: 'Mis chats',
              ),
              if (_unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.redAccent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.black, width: 1),
                    ),
                    constraints: const BoxConstraints(minWidth: 18),
                    child: Text(
                      _unread > 99 ? '99+' : '$_unread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),

        IconButton(
          onPressed: () => Navigator.pushNamed(context, AppointmentsScreen.route),
          icon: const Icon(Icons.calendar_month_outlined),
          tooltip: 'Mis reservas',
        ),
        IconButton(onPressed: () => Api.logout(), icon: const Icon(Icons.logout)),
      ],
      floatingActionButton: authState.role == 'artist'
          ? FloatingActionButton(
              onPressed: _goCreateDesign,
              child: const Icon(Icons.add),
              tooltip: 'Nuevo diseño',
            )
          : null,

      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _future,
        builder: (_, snap) {
          if (snap.connectionState != ConnectionState.done) return const Busy();
          if (snap.hasError) {
            debugPrint('[Catalog] ERROR: ${snap.error}');
            return Center(child: Text('Error: ${snap.error}'));
          }

          final items = snap.data ?? const <Map<String, dynamic>>[];
          debugPrint('[Catalog] diseños recibidos = ${items.length}');

          if (items.isEmpty) {
            return SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 180),
                    Center(child: Text('Sin diseños aún')),
                  ],
                ),
              ),
            );
          }

          return SafeArea(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: GridView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  // ↓ Más alto cada ítem para que quepa todo
                  childAspectRatio: .60,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final d = items[i];
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => Navigator.push(
                        _,
                        MaterialPageRoute(
                          builder: (__) => DesignDetailScreen(design: d),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: (d['image_url'] != null &&
                                    (d['image_url'] as String).isNotEmpty)
                                ? Image.network(
                                    d['image_url'],
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) =>
                                        const ColoredBox(color: Color(0x11000000)),
                                  )
                                : const ColoredBox(color: Color(0x11000000)),
                          ),
                          // Bloque inferior compacto
                          Expanded(
                            child: Padding(
                              // ↓ Paddings más chicos
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    d['title']?.toString() ?? '—',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    d['artist_name']?.toString() ?? '—',
                                    style: TextStyle(
                                      color: Colors.grey[700],
                                      fontSize: 12,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Row(
                                    children: [
                                      // Botón más compacto (alto ~32)
                                      FilledButton.tonal(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                DesignDetailScreen(design: d),
                                          ),
                                        ),
                                        style: FilledButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          minimumSize: const Size(0, 32),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                        child: const Text('Ver'),
                                      ),
                                      const Spacer(),
                                      Text(
                                        d['price'] != null ? '\$${d['price']}' : '—',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
