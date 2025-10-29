import 'package:flutter/material.dart';
import '../core/api.dart';
import '../core/auth_state.dart';
import '../widgets/common.dart';
import 'design_detail_screen.dart';
import '../core/chat_api.dart';
import 'chat_screen.dart';

class ArtistProfileScreen extends StatefulWidget {
  static const route = '/artist';
  final int artistId;
  final String? artistName;
  const ArtistProfileScreen({super.key, required this.artistId, this.artistName});

  @override
  State<ArtistProfileScreen> createState() => _ArtistProfileScreenState();
}

class _ArtistProfileScreenState extends State<ArtistProfileScreen> {
  late Future<Map<String, dynamic>> _fArtist;
  late Future<List<Map<String, dynamic>>> _fDesigns;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _fArtist = Api.getArtist(widget.artistId);
    _fDesigns = Api.getDesigns(artistId: widget.artistId);
  }

  Future<void> _refresh() async {
    setState(_load);
  }

  Future<void> _toggleFav(Map<String, dynamic> d) async {
    try {
      if ((d['is_favorited'] == true)) {
        await Api.removeFavorite(d['id']);
        d['is_favorited'] = false;
        d['likes_count'] = (d['likes_count'] ?? 1) - 1;
      } else {
        await Api.addFavorite(d['id']);
        d['is_favorited'] = true;
        d['likes_count'] = (d['likes_count'] ?? 0) + 1;
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(ko(e.toString()));
    }
  }

  Future<void> _startChat() async {
    final token = authState.token;
    if (token == null || token.isEmpty || authState.role != 'client') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko('Inicia sesión como cliente para chatear.'),
      );
      return;
    }
    try {
      final api = ChatApi(token);
      final threadId = await api.ensureThread(widget.artistId);
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(api: api, threadId: threadId)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        ko('No se pudo iniciar el chat: $e'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: widget.artistName ?? 'Artista #${widget.artistId}',
      actions: [
        if (authState.role == 'client')
          IconButton(
            tooltip: 'Chatear',
            onPressed: _startChat,
            icon: const Icon(Icons.chat_bubble_outline),
          ),
      ],
      child: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Encabezado artista
            FutureBuilder<Map<String, dynamic>>(
              future: _fArtist,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Busy();
                }
                if (snap.hasError) {
                  return Text('Error: ${snap.error}');
                }
                final a = snap.data ?? {};
                final name = a['name']?.toString() ?? (widget.artistName ?? 'Artista #${widget.artistId}');
                final designsCount = a['designs_count'] ?? 0;
                final likesTotal = a['likes_total'] ?? 0;

                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 28,
                          child: Icon(Icons.person_outline),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text('Diseños: $designsCount • ❤ $likesTotal'),
                              const SizedBox(height: 6),
                              const Text('Bio/estilos: — (pendiente)'),
                            ],
                          ),
                        ),
                        if (authState.role == 'client')
                          FilledButton.icon(
                            onPressed: _startChat,
                            icon: const Icon(Icons.chat_bubble_outline),
                            label: const Text('Chatear'),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const Gap(12),

            // Título grilla
            Text('Diseños del artista', style: Theme.of(context).textTheme.titleMedium),

            const Gap(8),
            // Grilla de diseños del artista
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _fDesigns,
              builder: (_, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Busy();
                }
                if (snap.hasError) {
                  return Text('Error: ${snap.error}');
                }
                final items = snap.data ?? const <Map<String, dynamic>>[];
                if (items.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: Text('Este artista aún no tiene diseños publicados')),
                  );
                }

                return GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
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
                          context,
                          MaterialPageRoute(builder: (_) => DesignDetailScreen(design: d)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            AspectRatio(
                              aspectRatio: 1,
                              child: (d['image_url'] != null && (d['image_url'] as String).isNotEmpty)
                                  ? Image.network(
                                      d['image_url'],
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0x11000000)),
                                    )
                                  : const ColoredBox(color: Color(0x11000000)),
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      d['title']?.toString() ?? '—',
                                      style: const TextStyle(fontWeight: FontWeight.w700),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      d['artist_name']?.toString() ?? '—',
                                      style: TextStyle(color: Colors.grey[700], fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Row(
                                      children: [
                                        FilledButton.tonal(
                                          onPressed: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(builder: (_) => DesignDetailScreen(design: d)),
                                          ),
                                          style: FilledButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            minimumSize: const Size(0, 32),
                                            visualDensity: VisualDensity.compact,
                                          ),
                                          child: const Text('Ver'),
                                        ),
                                        const Spacer(),
                                        // Likes + corazón
                                        Row(
                                          children: [
                                            Text('${d['likes_count'] ?? 0}'),
                                            IconButton(
                                              tooltip: (d['is_favorited'] == true)
                                                  ? 'Quitar de favoritos'
                                                  : 'Agregar a favoritos',
                                              onPressed: () async {
                                                if (authState.token == null || authState.token!.isEmpty) {
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    ko('Inicia sesión para agregar a favoritos'),
                                                  );
                                                  return;
                                                }
                                                await _toggleFav(d);
                                              },
                                              icon: Icon(
                                                (d['is_favorited'] == true)
                                                    ? Icons.favorite
                                                    : Icons.favorite_border,
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
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
