import 'package:flutter/material.dart';
import '../widgets/common.dart';
import '../core/auth_state.dart';
import '../core/chat_api.dart';
import 'booking_screen.dart';
import 'chat_screen.dart';
import 'artist_profile_screen.dart';

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
    final img = design['image_url'] ?? '';
    final artistId = design['artist_id'] as int;
    final artistName = (design['artist_name'] as String?)?.trim().isNotEmpty == true
        ? design['artist_name'] as String
        : 'Artista #$artistId';
    // Soporta dos posibles llaves para el avatar (por si el backend usa una u otra)
    final artistAvatar = ((design['artist_avatar_url'] ?? design['artist_avatar']) as String?) ?? '';
    final price = design['price'];

    return AppShell(
      title: design['title'] ?? 'Diseño',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Image.network(
              img,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const ColoredBox(color: Color(0x11000000)),
            ),
          ),
          const Gap(12),

          // === Bloque artista (avatar + nombre) ===
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ArtistProfileScreen(artistId: artistId)),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: (artistAvatar.isNotEmpty) ? NetworkImage(artistAvatar) : null,
                    child: (artistAvatar.isEmpty)
                        ? Text(
                            _initials(artistName),
                            style: const TextStyle(fontWeight: FontWeight.w700),
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
                  Icon(Icons.chevron_right, color: Colors.white.withOpacity(.7)),
                ],
              ),
            ),
          ),

          const Gap(8),
          Text(design['description'] ?? '—'),
          const Gap(16),

          Row(
            children: [
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => BookingScreen(
                      designId: design['id'],
                      artistId: artistId,
                    ),
                  ),
                ),
                child: const Text('Reservar'),
              ),
              const Spacer(),
              Text(
                price != null ? '\$$price' : '—',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              // Botón de chat
              IconButton(
                icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
                tooltip: 'Chatear con el artista',
                onPressed: () async {
                  final token = authState.token;
                  if (token == null || token.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Debes iniciar sesión')),
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
                        SnackBar(content: Text('Error al iniciar chat: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
