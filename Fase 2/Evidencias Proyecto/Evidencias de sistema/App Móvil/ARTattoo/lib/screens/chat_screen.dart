import 'dart:async';
import 'package:flutter/material.dart';
import '../core/chat_api.dart';
import '../core/auth_state.dart';

class ChatScreen extends StatefulWidget {
  final ChatApi api;
  final int threadId;
  const ChatScreen({super.key, required this.api, required this.threadId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final Set<int> _seenIds = <int>{};              // <- para desduplicar
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  int? _lastId;
  StreamSubscription<Map<String, dynamic>>? _sseSub;
  Timer? _pollTimer;

  int? _meId;

  @override
  void initState() {
    super.initState();
    _meId = authState.userId;
    _bootstrap();
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    _sseSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  int? _msgId(Map<String, dynamic> m) {
    final v = m['id'];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  void _addMessage(Map<String, dynamic> m) {
    final id = _msgId(m);
    if (id == null) return;
    if (_seenIds.contains(id)) return;         // ya existe -> no duplicar
    _seenIds.add(id);
    _msgs.add(m);
    if (_lastId == null || id > _lastId!) {
      _lastId = id;
    }
  }

  void _addMany(List<Map<String, dynamic>> items) {
    for (final m in items) {
      _addMessage(m);
    }
  }

  Future<void> _bootstrap() async {
    try {
      final first = await widget.api.getMessages(widget.threadId, limit: 100);
      setState(() {
        _addMany(first);
        _loading = false;
      });

      _openRealtimeOrPoll();

      if (_lastId != null) {
        unawaited(widget.api.markRead(widget.threadId, _lastId!));
      }
      _jumpBottom();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando mensajes: $e')),
      );
      _startPolling();
    }
  }

  void _openRealtimeOrPoll() {
    _sseSub = widget.api.openSseStream(widget.threadId, lastId: _lastId).listen((msg) {
      setState(() {
        _addMessage(msg);                      // <- ya deduplica
      });
      _jumpBottom();
      if (_lastId != null) {
        unawaited(widget.api.markRead(widget.threadId, _lastId!));
      }
    }, onError: (e) {
      debugPrint('SSE error: $e');
      _startPolling();
    }, onDone: () {
      _startPolling();
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final news = await widget.api.getMessages(widget.threadId, afterId: _lastId, limit: 50);
        if (news.isNotEmpty) {
          setState(() {
            _addMany(news);                    // <- dedupe
          });
          _jumpBottom();
          if (_lastId != null) {
            unawaited(widget.api.markRead(widget.threadId, _lastId!));
          }
        }
      } catch (_) {
        // silenciar intermitencias de red
      }
    });
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent + 120);
    });
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();

    try {
      // 1) Enviar (no agregamos eco local)
      await widget.api.sendMessage(widget.threadId, text: text);

      // 2) Pull delta para traer el mensaje con su id real
      final delta = await widget.api.getMessages(widget.threadId, afterId: _lastId, limit: 10);
      if (delta.isNotEmpty) {
        setState(() {
          _addMany(delta);                     // <- dedupe
        });
        _jumpBottom();
        if (_lastId != null) {
          unawaited(widget.api.markRead(widget.threadId, _lastId!));
        }
      }
      // Si además llega por SSE/poll, _addMessage lo ignorará por duplicado.
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo enviar: $e')),
      );
    }
  }

  bool _isMine(Map<String, dynamic> m) {
    if (_meId == null) return false;
    final sid = m['sender_id'];
    if (sid is int) return sid == _meId;
    if (sid is String) return int.tryParse(sid) == _meId;
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) {
                      final m = _msgs[i];
                      final isMine = _isMine(m);
                      final text = (m['text'] as String?)?.trim();
                      final hasText = text != null && text.isNotEmpty;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          constraints: const BoxConstraints(maxWidth: 320),
                          decoration: BoxDecoration(
                            color: isMine ? Colors.blueAccent : Colors.grey.shade800,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: hasText
                              ? Text(text!, style: const TextStyle(color: Colors.white))
                              : const Text('[imagen]', style: TextStyle(color: Colors.white70)),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Row(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 6, 12),
                    child: TextField(
                      controller: _c,
                      decoration: InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                ),
                IconButton(icon: const Icon(Icons.send), onPressed: _send),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
