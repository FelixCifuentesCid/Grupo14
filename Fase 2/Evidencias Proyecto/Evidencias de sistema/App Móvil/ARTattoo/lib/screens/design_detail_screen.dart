import 'package:flutter/material.dart';
import '../widgets/common.dart';
import '../core/auth_state.dart';
import '../core/chat_api.dart';
import 'booking_screen.dart';
import 'chat_screen.dart';

class DesignDetailScreen extends StatelessWidget {
  final Map<String, dynamic> design;
  const DesignDetailScreen({super.key, required this.design});

  @override
  Widget build(BuildContext context) {
    final img = design['image_url'] ?? '';
    final artistId = design['artist_id'] as int;
    final artistName = design['artist_name'] ?? 'Artista #$artistId';
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
          const Gap(16),
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
