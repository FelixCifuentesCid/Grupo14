import 'package:flutter/material.dart';
import '../core/auth_state.dart';
import '../core/chat_api.dart';
import 'chat_screen.dart';

class ArtistProfileScreen extends StatelessWidget {
  static const route = '/artist';
  final int artistId;
  final String? artistName;
  const ArtistProfileScreen({super.key, required this.artistId, this.artistName});

  @override
  Widget build(BuildContext context) {
    final meRole = authState.role;
    final token = authState.token;

    return Scaffold(
      appBar: AppBar(title: Text(artistName ?? 'Artista #$artistId')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(artistName ?? 'Artista #$artistId', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text('Aquí podrías mostrar bio, estilos, portafolio, etc.'),
            const Spacer(),
            if (token != null && token.isNotEmpty && meRole == 'client')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('Chatear con este artista'),
                  onPressed: () async {
                    try {
                      final api = ChatApi(token);
                      final threadId = await api.ensureThread(artistId);
                      if (context.mounted) {
                        Navigator.push(context,
                          MaterialPageRoute(builder: (_) => ChatScreen(api: api, threadId: threadId)));
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('No se pudo iniciar el chat: $e')),
                        );
                      }
                    }
                  },
                ),
              )
            else
              const Text('Inicia sesión como cliente para chatear.'),
          ],
        ),
      ),
    );
  }
}
