import 'package:flutter/material.dart';
import '../core/chat_api.dart';
import 'chat_screen.dart';

class ThreadsScreen extends StatefulWidget {
  static const route = '/threads';
  final ChatApi api;
  const ThreadsScreen({super.key, required this.api});

  @override
  State<ThreadsScreen> createState() => _ThreadsScreenState();
}

class _ThreadsScreenState extends State<ThreadsScreen> {
  late Future<List<Map<String, dynamic>>> _f;

  @override
  void initState() {
    super.initState();
    _f = widget.api.listThreads();
  }

  Future<void> _refresh() async {
    setState(() => _f = widget.api.listThreads());
    await _f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tus chats')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _f,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const [];
            if (items.isEmpty) {
              return const Center(child: Text('Aún no tienes conversaciones'));
            }
            return ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) {
                final t = items[i];
                final last = t['last_message'] as Map<String, dynamic>?;
                final subtitle = last == null
                    ? '—'
                    : (last['text'] as String?)?.trim().isNotEmpty == true
                        ? last['text'] as String
                        : '[imagen]';

                final unread = (t['unread'] as int?) ?? 0;
                final name = t['other_user_name'] ??
                    t['other_user']?['name'] ??
                    'Usuario #${t['other_user_id']}';

                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(name.toString()),
                  subtitle: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: unread > 0
                      ? CircleAvatar(
                          radius: 12,
                          backgroundColor: Colors.redAccent,
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white),
                          ),
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ChatScreen(api: widget.api, threadId: t['thread_id'] as int),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
