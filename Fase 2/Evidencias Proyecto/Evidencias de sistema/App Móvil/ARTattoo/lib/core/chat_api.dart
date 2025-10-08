import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'api.dart';
import 'auth_state.dart';

class ChatApi {
  final String base = 'http://167.114.145.34:8000';
  final String jwt; // compat, pero NO lo "congelamos"
  ChatApi(this.jwt);

  Future<Map<String, String>> _h() async {
    await Api.ensureValidToken();
    final t = authState.token ?? jwt;
    return {
      HttpHeaders.authorizationHeader: 'Bearer $t',
      HttpHeaders.contentTypeHeader: 'application/json',
    };
  }

  Future<int> ensureThread(int otherUserId) async {
    final r = await http.post(
      Uri.parse('$base/chat/threads/ensure'),
      headers: await _h(),
      body: jsonEncode({'other_user_id': otherUserId}),
    );
    if (r.statusCode != 200) {
      throw Exception('ensureThread: ${r.statusCode} ${r.body}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    return data['thread_id'] as int;
  }

  Future<List<Map<String, dynamic>>> listThreads() async {
    final r = await http.get(Uri.parse('$base/chat/threads'), headers: await _h());
    if (r.statusCode != 200) {
      throw Exception('listThreads: ${r.statusCode} ${r.body}');
    }
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<List<Map<String, dynamic>>> getMessages(int threadId,
      {int? afterId, int limit = 50}) async {
    final q = <String, String>{
      'limit': '$limit',
      if (afterId != null) 'after_id': '$afterId'
    };
    final u = Uri.parse('$base/chat/threads/$threadId/messages')
        .replace(queryParameters: q);
    final r = await http.get(u, headers: await _h());
    if (r.statusCode != 200) {
      throw Exception('getMessages: ${r.statusCode} ${r.body}');
    }
    return List<Map<String, dynamic>>.from(jsonDecode(r.body));
  }

  Future<Map<String, dynamic>> sendMessage(int threadId,
      {String? text, String? imageUrl}) async {
    final r = await http.post(
      Uri.parse('$base/chat/threads/$threadId/messages'),
      headers: await _h(),
      body: jsonEncode({'text': text, 'image_url': imageUrl}),
    );
    if (r.statusCode != 201) {
      throw Exception('sendMessage: ${r.statusCode} ${r.body}');
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<void> markRead(int threadId, int lastId) async {
    final r = await http.post(
      Uri.parse('$base/chat/threads/$threadId/read'),
      headers: await _h(),
      body: jsonEncode({'last_id': lastId}),
    );
    if (r.statusCode != 200) {
      throw Exception('markRead: ${r.statusCode} ${r.body}');
    }
  }

  /// SSE con token encodeado y header Authorization (por si el backend lo usa)
  Stream<Map<String, dynamic>> openSseStream(int threadId, {int? lastId}) {
    final controller = StreamController<Map<String, dynamic>>();
    final client = HttpClient()..idleTimeout = const Duration(minutes: 5);

    controller.onCancel = () {
      try { client.close(force: true); } catch (_) {}
    };

    () async {
      try {
        // refresca antes y usa token vigente
        await Api.ensureValidToken();
        final token = authState.token ?? jwt;

        final tokenQ = Uri.encodeQueryComponent(token);
        final lastQ  = lastId != null ? '&last_id=$lastId' : '';
        final uri = Uri.parse('$base/chat/threads/$threadId/sse?token=$tokenQ$lastQ');

        final req = await client.getUrl(uri);
        // aunque el backend valide por query, también mandamos Authorization
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
        req.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');

        final resp = await req.close();
        if (resp.statusCode != 200) {
          controller.addError('SSE HTTP ${resp.statusCode}');
          await controller.close();
          client.close(force: true);
          return;
        }

        final lines = resp.transform(utf8.decoder).transform(const LineSplitter());
        String? eventName;
        final dataBuf = StringBuffer();

        await for (final line in lines) {
          if (line.isEmpty) {
            final dataStr = dataBuf.toString();
            if (eventName == 'message' && dataStr.isNotEmpty) {
              try {
                final obj = jsonDecode(dataStr) as Map<String, dynamic>;
                if (!controller.isClosed) controller.add(obj);
              } catch (_) {}
            }
            eventName = null;
            dataBuf.clear();
            continue;
          }
          if (line.startsWith('event:')) {
            eventName = line.substring(6).trim();
          } else if (line.startsWith('data:')) {
            final v = line.substring(5).trimRight();
            if (dataBuf.isNotEmpty) dataBuf.write('\n');
            dataBuf.write(v);
          }
        }
      } catch (e) {
        if (!controller.isClosed) controller.addError(e);
      } finally {
        if (!controller.isClosed) await controller.close();
        client.close(force: true);
      }
    }();

    return controller.stream;
  }
}
