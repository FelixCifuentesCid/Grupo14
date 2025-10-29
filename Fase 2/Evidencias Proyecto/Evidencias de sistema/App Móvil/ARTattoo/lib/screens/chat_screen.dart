import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/chat_api.dart';
import '../core/auth_state.dart';
import '../core/api.dart';

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
  final Set<int> _seenIds = <int>{}; // desduplicar
  final _picker = ImagePicker();

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
    if (_seenIds.contains(id)) return; // ya existe -> no duplicar
    _seenIds.add(id);
    _msgs.add(m);
    if (_lastId == null || id > _lastId!) _lastId = id;
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
    _sseSub = widget.api
        .openSseStream(widget.threadId, lastId: _lastId)
        .listen((msg) {
      setState(() {
        _addMessage(msg); // dedupe
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
        final news = await widget.api
            .getMessages(widget.threadId, afterId: _lastId, limit: 50);
        if (news.isNotEmpty) {
          setState(() {
            _addMany(news); // dedupe
          });
          _jumpBottom();
          if (_lastId != null) {
            unawaited(widget.api.markRead(widget.threadId, _lastId!));
          }
        }
      } catch (_) {
        // ignorar intermitencias
      }
    });
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent + 160);
    });
  }

  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();

    try {
      // 1) Enviar (sin eco local)
      await widget.api.sendMessage(widget.threadId, text: text);

      // 2) Pull delta (trae id real)
      final delta = await widget.api
          .getMessages(widget.threadId, afterId: _lastId, limit: 10);
      if (delta.isNotEmpty) {
        setState(() {
          _addMany(delta); // dedupe
        });
        _jumpBottom();
        if (_lastId != null) {
          unawaited(widget.api.markRead(widget.threadId, _lastId!));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
    }
  }

  Future<void> _pickAndSendImage() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 92,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      final ext = x.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      final b64 = 'data:image/$ext;base64,${base64Encode(bytes)}';

      // 1) Subir para obtener URL pública
      final url = await Api.uploadImageBase64(b64);

      // 2) Enviar mensaje con image_url
      await widget.api.sendMessage(widget.threadId, imageUrl: url);

      // 3) Pull delta
      final delta = await widget.api
          .getMessages(widget.threadId, afterId: _lastId, limit: 10);
      if (delta.isNotEmpty) {
        setState(() {
          _addMany(delta);
        });
        _jumpBottom();
        if (_lastId != null) {
          unawaited(widget.api.markRead(widget.threadId, _lastId!));
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo adjuntar: $e')));
    }
  }

  bool _isMine(Map<String, dynamic> m) {
    if (_meId == null) return false;
    final sid = m['sender_id'];
    if (sid is int) return sid == _meId;
    if (sid is String) return int.tryParse(sid) == _meId;
    return false;
  }

  Widget _bubble(Map<String, dynamic> m) {
    final isMine = _isMine(m);
    final text = (m['text'] as String?)?.trim();
    final img = (m['image_url'] as String?)?.trim();
    final hasText = text != null && text.isNotEmpty;
    final hasImg = img != null && img.isNotEmpty;

    final bg = isMine ? Colors.blueAccent : Colors.grey.shade800;

    Widget content;
    if (hasText && hasImg) {
      content = Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(text!,
              style: const TextStyle(color: Colors.white), textAlign: TextAlign.left),
          const SizedBox(height: 8),
          _imageThumb(img!),
        ],
      );
    } else if (hasImg) {
      content = _imageThumb(img!);
    } else if (hasText) {
      content = Text(text!, style: const TextStyle(color: Colors.white));
    } else {
      content = const Text('[mensaje vacío]',
          style: TextStyle(color: Colors.white70));
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: hasImg
            ? const EdgeInsets.all(6)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 320),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: content,
      ),
    );
  }

  Widget _imageThumb(String url) {
    return GestureDetector(
      onTap: () => _openImage(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const SizedBox(height: 120, child: Center(child: Text('[imagen]'))),
          ),
        ),
      ),
    );
  }

  void _openImage(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = 'Escribe un mensaje… (menciona @tink para el asistente)';
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _bubble(_msgs[i]),
                  ),
          ),
          SafeArea(
            child: Row(
              children: [
                // Adjuntar imagen
                IconButton(
                  tooltip: 'Adjuntar imagen',
                  icon: const Icon(Icons.image),
                  onPressed: _pickAndSendImage,
                ),
                // Campo de texto
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 6, 6, 12),
                    child: TextField(
                      controller: _c,
                      decoration: InputDecoration(
                        hintText: hint,
                        filled: true,
                        fillColor: Colors.grey.shade900,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      textInputAction: TextInputAction.send,
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
