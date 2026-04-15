import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../utils/constants.dart';

final webSocketClientProvider = Provider<WebSocketClient>((ref) {
  return WebSocketClient();
});

class WebSocketClient {
  WebSocketChannel? _channel;
  StreamController<Map<String, dynamic>>? _controller;
  int? _connectedUserId;
  Timer? _pingTimer;
  // Incremented on every disconnect/reconnect cycle so stale delayed callbacks
  // can detect they belong to an old generation and skip firing.
  int _generation = 0;

  /// Returns a stream of WebSocket events for the given user.
  ///
  /// If already connected for this user, the existing broadcast stream is
  /// returned so multiple screens can subscribe without tearing down the
  /// connection or replacing the controller.
  Stream<Map<String, dynamic>> connect(int userId) {
    if (_connectedUserId == userId &&
        _controller != null &&
        !_controller!.isClosed) {
      // Same user — reuse the broadcast stream but if the underlying channel
      // is gone (killed while the phone was locked) kick off an immediate
      // reconnect instead of waiting for the delayed-timer path.
      if (_channel == null) {
        _generation++;
        _connect(userId, _generation);
      }
      return _controller!.stream;
    }

    _connectedUserId = userId;
    _generation++;
    _controller?.close();
    _controller = StreamController<Map<String, dynamic>>.broadcast();

    _connect(userId, _generation);
    return _controller!.stream;
  }

  void _connect(int userId, int generation) {
    // Bail out if this callback belongs to a stale reconnect cycle.
    if (generation != _generation) return;

    try {
      // Close any existing channel before opening a new one.
      _channel?.sink.close();
      _channel = null;

      final uri = Uri.parse('${AppConstants.wsBaseUrl}/$userId');
      _channel = WebSocketChannel.connect(uri);

      // Catch connection-level errors (e.g. DNS failure, TLS rejection).
      _channel!.ready.catchError((_) {
        if (generation != _generation) return;
        _channel = null;
        Future.delayed(const Duration(seconds: 5), () {
          _connect(userId, generation);
        });
      });

      _channel!.stream.listen(
        (data) {
          if (data is String) {
            try {
              final event = jsonDecode(data) as Map<String, dynamic>;
              if (_controller != null && !_controller!.isClosed) {
                _controller!.add(event);
              }
            } catch (_) {
              // Ignore non-JSON messages (e.g. "pong")
            }
          }
        },
        onDone: () {
          _channel = null; // mark as dead so connect() can detect it on resume
          // Auto-reconnect after 3 seconds on disconnect.
          // Pass the current generation so stale timers self-cancel.
          Future.delayed(const Duration(seconds: 3), () {
            _connect(userId, generation);
          });
        },
        onError: (error) {
          _channel = null; // mark as dead
          Future.delayed(const Duration(seconds: 5), () {
            _connect(userId, generation);
          });
        },
        cancelOnError: false,
      );

      // Send a ping every 30 seconds to keep connection alive
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _channel?.sink.add('ping');
      });
    } catch (e) {
      // Retry connection after delay
      Future.delayed(const Duration(seconds: 5), () {
        _connect(userId, generation);
      });
    }
  }

  void disconnect() {
    _generation++; // Invalidate all pending reconnect callbacks
    _pingTimer?.cancel();
    _channel?.sink.close();
    _controller?.close();
    _connectedUserId = null;
    _channel = null;
  }

  bool get isConnected => _channel != null;
}
