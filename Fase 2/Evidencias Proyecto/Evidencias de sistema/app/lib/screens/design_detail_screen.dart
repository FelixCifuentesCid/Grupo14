import 'package:flutter/material.dart';
import '../widgets/common.dart';
import '../core/api.dart';
import '../core/auth_state.dart';
import '../core/chat_api.dart';
import 'booking_screen.dart';
import 'chat_screen.dart';
import 'artist_profile_screen.dart';
import 'create_design_screen.dart';
import 'ar_screen.dart';

class DesignDetailScreen extends StatelessWidget {
  final Map<String, dynamic> design;
  const DesignDetailScreen({super.key, required this.design});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return 'A';
    String i1 = parts.first.isNotEmpty ? parts.first[0] : '';
    String i2 = parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '';
    final s = (i1 + i2).toUpperCase();
    return s.isEmpty ? 'A' : s;
  }

  @override
  Widget build(BuildContext context) {
    final img = (design['image_url'] as String?) ?? '';
    final artistId = design['artist_id'] as int;
    final artistName =
        (design['artist_name'] as String?)?.trim().isNotEmpty == true
            ? design['artist_name'] as String
            : 'Artista #$artistId';

    // soporta artist_avatar_url o artist_avatar
    final artistAvatar =
        ((design['artist_avatar_url'] ?? design['artist_avatar']) as String?) ??
            '';

    final price = design['price'];
    final description = (design['description'] as String?) ?? '—';

    // ¿el usuario logueado es el artista?
    final bool isOwner = authState.userId == artistId;

    return AppShell(
      title: design['title'] ?? 'Diseño',
      actions: [
        // menú de editar / eliminar SOLO si es el artista dueño del diseño
        if (authState.role == 'artist' && isOwner)
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'edit') {
                final changed = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CreateDesignScreen(design: design),
                  ),
                );
                if (changed == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    ok('Diseño actualizado'),
                  );
                }
              } else if (value == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Eliminar diseño'),
                    content: const Text(
                      '¿Seguro que quieres eliminar este diseño? '
                      'Esta acción no se puede deshacer.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Eliminar'),
                      ),
                    ],
                  ),
                );

                if (confirm == true) {
                  try {
                    final int? id = design['id'] as int?;
                    if (id != null) {
                      // IMPORTANTE: Api SIN argumentos, es estático
                      await Api.deleteDesign(id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          ok('Diseño eliminado'),
                        );
                        Navigator.pop(context, true);
                      }
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        ko('No se pudo eliminar: $e'),
                      );
                    }
                  }
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: Text('Editar diseño'),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text('Eliminar diseño'),
              ),
            ],
          ),
      ],
      // OJO: AppShell usa `child`, NO `body`
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Imagen principal
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: img.isNotEmpty
                  ? Image.network(
                      img,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const ColoredBox(color: Color(0x11000000)),
                    )
                  : const ColoredBox(
                      color: Color(0x11000000),
                      child: Center(
                        child: Icon(Icons.image_outlined),
                      ),
                    ),
            ),
          ),

          const Gap(12),

          // === Bloque artista (avatar + nombre) ===
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ArtistProfileScreen(artistId: artistId),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: artistAvatar.isNotEmpty
                        ? NetworkImage(artistAvatar)
                        : null,
                    child: artistAvatar.isEmpty
                        ? Text(
                            _initials(artistName),
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      artistName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Colors.white.withOpacity(.7),
                  ),
                ],
              ),
            ),
          ),

          const Gap(12),

          Text(
            'Descripción',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(description),

          const Gap(20),

          // === Fila precio + acciones ===
          Row(
            children: [
              // Botón Reservar SOLO si NO es el dueño del diseño
              if (!isOwner)
                FilledButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BookingScreen(
                          designId: design['id'],
                          artistId: artistId,
                        ),
                      ),
                    );
                  },
                  child: const Text('Reservar'),
                ),

              const Spacer(),

              // El precio SIEMPRE visible, incluso para el artista
              Text(
                price != null ? '\$$price' : '—',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),

              // Botones AR + chat SOLO si NO es el dueño
              if (!isOwner) ...[
                const SizedBox(width: 8),
                // BOTÓN AR
                IconButton(
                  icon: const Icon(
                    Icons.view_in_ar,
                    color: Colors.white,
                  ),
                  tooltip: 'Ver tatuaje en AR',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const TattooCylApp(),
                      ),
                    );
                  },
                ),

                const SizedBox(width: 8),

                // BOTÓN CHAT
                IconButton(
                  icon: const Icon(
                    Icons.chat_bubble_outline,
                    color: Colors.white,
                  ),
                  tooltip: 'Chatear con el artista',
                  onPressed: () async {
                    final token = authState.token;
                    if (token == null || token.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Debes iniciar sesión'),
                        ),
                      );
                      return;
                    }
                    try {
                      final api = ChatApi(token);
                      final threadId = await api.ensureThread(artistId);
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              api: api,
                              threadId: threadId,
                            ),
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Error al iniciar chat: $e'),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
