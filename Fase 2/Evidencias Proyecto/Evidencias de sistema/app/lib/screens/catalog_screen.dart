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
import 'favorites_screen.dart';
import 'artist_profile_screen.dart';

class CatalogScreen extends StatefulWidget {
  static const route = '/catalog';
  const CatalogScreen({super.key});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  late Future<List<Map<String, dynamic>>> _future;

  // ---- Search ----
  final _qCtrl = TextEditingController();
  String? _currentQ;
  Timer? _debounce;

  // ---- Unread badge ----
  int _unread = 0;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _future = Api.getDesigns();
    // Refresca UI del buscador mientras escribes (icono clear, etc.)
    _qCtrl.addListener(() {
      if (mounted) setState(() {});
    });
    _startUnreadPolling();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _debounce?.cancel();
    _qCtrl.dispose();
    super.dispose();
  }

  // ---- Polling de no leídos ----
  void _startUnreadPolling() {
    _fetchUnread();
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
    } catch (_) {}
  }

  // ---- Búsqueda ----
  void _onSearchChanged(String value) {
    final raw = value.trim();
  
    // cancelar cualquier debounce en curso
    _debounce?.cancel();
  
    if (raw.isEmpty) {
      // mostrar TODO inmediatamente (sin esperar 250 ms)
      _currentQ = null;
      setState(() => _future = Api.getDesigns());
      return;
    }
  
    // redibuja altiro (para el ícono clear) y aplica debounce para búsquedas no vacías
    if (mounted) setState(() {});
    _debounce = Timer(const Duration(milliseconds: 250), _applySearch);
  }


  void _applySearch() {
    final raw = _qCtrl.text.trim();
    String? q;
    if (raw.isEmpty) {
      q = null;
    } else if (raw.startsWith('@')) {
      q = raw; // preserva @
    } else {
      if ((raw.startsWith('"') && raw.endsWith('"')) ||
          (raw.startsWith('“') && raw.endsWith('”'))) {
        q = raw.substring(1, raw.length - 1);
      } else {
        q = raw;
      }
    }
    _currentQ = q;
    setState(() => _future = Api.getDesigns(q: q));
  }

  Future<void> _clearSearch() async {
    _qCtrl.clear();
    _currentQ = null;
    setState(() => _future = Api.getDesigns());
  }

  // ---- Acciones ----
  Future<void> _refresh() async {
    setState(() => _future = Api.getDesigns(q: _currentQ));
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
    ).then((_) => _fetchUnread());
  }

  void _goFavorites() {
    final t = authState.token;
    if (t == null || t.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Inicia sesión para ver favoritos')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => const FavoritesScreen()))
        .then((_) => _refresh());
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: 'Diseños',
      actions: [
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
          onPressed: _goFavorites,
          icon: const Icon(Icons.favorite_outline),
          tooltip: 'Mis favoritos',
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
      child: Column(
        children: [
          // ---- Buscador ----
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _qCtrl,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _applySearch(),
              decoration: InputDecoration(
                hintText: 'Buscar @artista o texto (puedes usar "comillas")',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _qCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Limpiar',
                        onPressed: _clearSearch,
                      ),
              ),
            ),
          ),

          // ---- Lista / Grid ----
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _future,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) return const Busy();
                if (snap.hasError) {
                  debugPrint('[Catalog] ERROR: ${snap.error}');
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final items = snap.data ?? const <Map<String, dynamic>>[];

                if (items.isEmpty) {
                  return SafeArea(
                    child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              _currentQ == null || _currentQ!.isEmpty
                                  ? 'Sin diseños aún'
                                  : 'Sin resultados para "${_currentQ!}"',
                            ),
                          ),
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
                        childAspectRatio: .60,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final d = items[i];

                        int likes = 0;
                        final rawLikes = d['likes_count'];
                        if (rawLikes is num) likes = rawLikes.toInt();
                        else likes = int.tryParse('$rawLikes') ?? 0;
                        final isFav = d['is_favorited'] == true;

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
                                // Imagen
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

                                // Contenido anclado abajo (sin “aire” inferior)
                                Expanded(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Título
                                          Text(
                                            d['title']?.toString() ?? '—',
                                            style: const TextStyle(fontWeight: FontWeight.w700),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          // Artista -> perfil
                                          GestureDetector(
                                            onTap: () {
                                              final aid = d['artist_id'] as int?;
                                              if (aid != null) {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ArtistProfileScreen(artistId: aid),
                                                  ),
                                                );
                                              }
                                            },
                                            child: Text(
                                              d['artist_name']?.toString() ?? '—',
                                              style: TextStyle(
                                                color: Colors.grey[700],
                                                fontSize: 12,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(height: 4),

                                          // Fila: Ver | corazón + número (sin precio)
                                          Row(
                                            children: [
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
                                                  minimumSize: const Size(0, 30),
                                                  visualDensity: VisualDensity.compact,
                                                ),
                                                child: const Text('Ver'),
                                              ),
                                              const Spacer(),
                                              // Corazón + numerito pegado
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  IconButton(
                                                    tooltip: isFav
                                                        ? 'Quitar de favoritos'
                                                        : 'Agregar a favoritos',
                                                    padding: EdgeInsets.zero,
                                                    constraints: const BoxConstraints(
                                                      minWidth: 28, minHeight: 28,
                                                    ),
                                                    iconSize: 18,
                                                    splashRadius: 18,
                                                    onPressed: () async {
                                                      if (authState.token == null ||
                                                          authState.token!.isEmpty) {
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context)
                                                              .showSnackBar(
                                                            const SnackBar(
                                                              content: Text(
                                                                'Inicia sesión para usar favoritos',
                                                              ),
                                                            ),
                                                          );
                                                        }
                                                        return;
                                                      }
                                                      try {
                                                        int currentLikes =
                                                            (d['likes_count'] is num)
                                                                ? (d['likes_count'] as num).toInt()
                                                                : int.tryParse(
                                                                        '${d['likes_count']}') ??
                                                                    likes;

                                                        if (isFav) {
                                                          await Api.removeFavorite(d['id'] as int);
                                                          d['is_favorited'] = false;
                                                          d['likes_count'] =
                                                              (currentLikes - 1).clamp(0, 1 << 31);
                                                        } else {
                                                          await Api.addFavorite(d['id'] as int);
                                                          d['is_favorited'] = true;
                                                          d['likes_count'] = currentLikes + 1;
                                                        }
                                                        if (mounted) setState(() {});
                                                      } catch (e) {
                                                        if (mounted) {
                                                          ScaffoldMessenger.of(context)
                                                              .showSnackBar(ko(e.toString()));
                                                        }
                                                      }
                                                    },
                                                    icon: Icon(
                                                      isFav
                                                          ? Icons.favorite
                                                          : Icons.favorite_border,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 2),
                                                  ConstrainedBox(
                                                    constraints: const BoxConstraints(minWidth: 14),
                                                    child: Text(
                                                      '${d['likes_count'] ?? likes}',
                                                      style: const TextStyle(
                                                        fontSize: 12,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      textAlign: TextAlign.left,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
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
          ),
        ],
      ),
    );
  }
}