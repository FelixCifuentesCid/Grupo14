// lib/screens/chat_screen.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/chat_api.dart';
import '../core/api.dart';
import '../core/auth_state.dart';

class ChatScreen extends StatefulWidget {
  final ChatApi api;
  final int threadId;

  /// Opcional: si lo pasas, el UI sabrá de inmediato cuáles mensajes son tuyos.
  final int? currentUserId;

  const ChatScreen({
    super.key,
    required this.api,
    required this.threadId,
    this.currentUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _c = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();

  bool _loading = true;
  int? _lastId;
  int? _myId;                  // ← id del usuario actual (desde authState o aprendido)
  String? _pendingText;        // ← último texto enviado (para aprender mi id)
  String? _pendingImageUrl;    // ← última imagen enviada (para aprender mi id)

  final _seenIds = <int>{};
  final _msgs = <Map<String, dynamic>>[];

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();

    // 1) Identidad: primero la que venga por props, si no, desde authState
    _myId = widget.currentUserId ?? authState.userId;

    // 2) Carga inicial + polling
    _bootstrap();
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final first = await widget.api.getMessages(widget.threadId, limit: 100);
      setState(() {
        _addMany(first);
        _loading = false;
      });
      _jumpBottom();
      _startPolling();
    } catch (_) {
      _startPolling();
      setState(() => _loading = false);
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final news = await widget.api.getMessages(
          widget.threadId,
          afterId: _lastId,
          limit: 50,
        );
        if (news.isNotEmpty) {
          setState(() => _addMany(news));
          _jumpBottom();
          if (_lastId != null) {
            // fire-and-forget (no esperamos)
            widget.api.markRead(widget.threadId, _lastId!);
          }
        }
      } catch (_) {}
    });
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 120,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  int? _msgId(Map m) {
    final id = m['id'];
    if (id is int) return id;
    if (id is String) return int.tryParse(id);
    return null;
  }

  void _addMessage(Map<String, dynamic> m) {
    final id = _msgId(m);
    if (id == null) return;
    if (_seenIds.contains(id)) return; // no duplicar
    _seenIds.add(id);
    _msgs.add(m);
    if (_lastId == null || id > _lastId!) _lastId = id;
  }

  void _addMany(List<Map<String, dynamic>> items) {
    for (final m in items) {
      _addMessage(m);
    }
  }

  // ====== Enviar texto ======
  Future<void> _send() async {
    final text = _c.text.trim();
    if (text.isEmpty) return;
    _c.clear();

    _pendingText = text; // para aprender mi id tras el delta

    try {
      await widget.api.sendMessage(widget.threadId, text: text);

      final delta =
          await widget.api.getMessages(widget.threadId, afterId: _lastId, limit: 20);

      // Aprende mi id automáticamente si aún no lo tenemos
      if (_myId == null && _pendingText != null) {
        for (final m in delta) {
          final t = (m['text'] as String?)?.trim();
          if (t != null && t == _pendingText) {
            final sid = m['sender_id'];
            if (sid is int) _myId = sid;
            if (sid is String) _myId = int.tryParse(sid);
            break;
          }
        }
      }

      if (delta.isNotEmpty) {
        setState(() => _addMany(delta));
        _jumpBottom();
        if (_lastId != null) {
          // fire-and-forget
          widget.api.markRead(widget.threadId, _lastId!);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo enviar: $e')));
    } finally {
      _pendingText = null;
    }
  }

  // ====== Adjuntar imagen desde galería ======
  Future<void> _pickAndSendImage() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 92,
      );
      if (x == null) return;

      final bytes = await x.readAsBytes();
      final b64 = base64Encode(bytes);
      final url = await Api.uploadImageBase64(b64);

      _pendingImageUrl = url; // para aprender mi id tras el delta

      await widget.api.sendMessage(widget.threadId, imageUrl: url);

      final delta =
          await widget.api.getMessages(widget.threadId, afterId: _lastId, limit: 20);

      if (_myId == null && _pendingImageUrl != null) {
        for (final m in delta) {
          final iu = (m['image_url'] as String?)?.trim();
          if (iu != null && iu == _pendingImageUrl) {
            final sid = m['sender_id'];
            if (sid is int) _myId = sid;
            if (sid is String) _myId = int.tryParse(sid);
            break;
          }
        }
      }

      if (delta.isNotEmpty) {
        setState(() => _addMany(delta));
        _jumpBottom();
        if (_lastId != null) {
          widget.api.markRead(widget.threadId, _lastId!);
        }
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo adjuntar: $e')));
    }
  }

  // ====== ¿Es mi mensaje? (solo cliente, sin tocar backend) ======
  bool _isMine(Map<String, dynamic> m) {
    // Si el backend manda banderita, la respetamos
    final flag = m['is_mine'] ?? m['mine'];
    if (flag is bool) return flag;

    // Comparación por sender_id
    if (_myId != null) {
      final sid = m['sender_id'];
      if (sid is int) return sid == _myId;
      if (sid is String) return int.tryParse(sid) == _myId;
    }

    // Desconocido
    return false;
  }

  // ====== UI: burbuja de mensaje ======
  Widget _bubble(Map<String, dynamic> m) {
    final textRaw = (m['text'] as String?)?.trim() ?? '';
    final img = (m['image_url'] as String?)?.trim();

    // Candidatas a imagen: image_url del backend + URLs en el texto
    final urls = <String>[];
    if (img != null && img.isNotEmpty) urls.add(img);
    urls.addAll(_extractUrls(textRaw));
    final imageUrls = urls.toSet().toList(); // sin duplicados
    final hasImages = imageUrls.isNotEmpty;

    // “Deja solo la imagen”: si hay imágenes, no mostramos texto ni links
    final displayText = hasImages ? '' : _stripUrls(textRaw);
    final hasText = displayText.isNotEmpty;

    final isMine = _isMine(m);
    final bg = isMine ? Colors.blueAccent : Colors.grey.shade800;
    final align = isMine ? Alignment.centerRight : Alignment.centerLeft;

    return Align(
      alignment: align,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: hasImages
            ? const EdgeInsets.all(6)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 360),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (hasText)
              Text(
                displayText,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.25,
                ),
              ),
            if (hasImages) ...[
              for (final u in imageUrls) ...[
                const SizedBox(height: 4),
                _imageThumb(u),
              ]
            ],
          ],
        ),
      ),
    );
  }

  Widget _imageThumb(String url) {
    return GestureDetector(
      onTap: () => _openImage(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 120,
            child: Center(child: Text('[imagen]')),
          ),
        ),
      ),
    );
  }

  void _openImage(String url) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.black,
        child: InteractiveViewer(
          child: Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const SizedBox(
              height: 200,
              child: Center(child: Text('[imagen]', style: TextStyle(color: Colors.white))),
            ),
          ),
        ),
      ),
    );
  }

  // ====== Helpers para limpiar texto / URLs ======
  final _urlExp = RegExp(r'(https?:\/\/[^\s]+)', caseSensitive: false);

  String _stripUrls(String s) => s.replaceAll(_urlExp, '').trim();

  List<String> _extractUrls(String s) =>
      _urlExp.allMatches(s).map((m) => m.group(0)!).toList();

  // ====== BUILD ======
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
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                    itemCount: _msgs.length,
                    itemBuilder: (_, i) => _bubble(_msgs[i]),
                  ),
          ),
          SafeArea(
            top: false,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.photo),
                  onPressed: _pickAndSendImage,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: TextField(
                      controller: _c,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Escribe un mensaje…',
                        border: OutlineInputBorder(),
                        isDense: true,
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
