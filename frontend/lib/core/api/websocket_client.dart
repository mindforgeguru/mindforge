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

  /// Returns a stream of WebSocket events for the given user.
  ///
  /// If already connected for this user, the existing broadcast stream is
  /// returned so multiple screens can subscribe without tearing down the
  /// connection or replacing the controller.
  Stream<Map<String, dynamic>> connect(int userId) {
    if (_connectedUserId == userId &&
        _controller != null &&
        !_controller!.isClosed) {
      return _controller!.stream;
    }

    _connectedUserId = userId;
    _controller?.close();
    _controller = StreamController<Map<String, dynamic>>.broadcast();

    _connect(userId);
    return _controller!.stream;
  }

  void _connect(int userId) {
    try {
      final uri = Uri.parse('${AppConstants.wsBaseUrl}/$userId');
      _channel = WebSocketChannel.connect(uri);
      // Await the ready future so connection errors are caught here
      _channel!.ready.catchError((_) {
        _channel = null;
        Future.delayed(const Duration(seconds: 5), () {
          if (_connectedUserId != null) _connect(_connectedUserId!);
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
          // Auto-reconnect after 3 seconds on disconnect
          Future.delayed(const Duration(seconds: 3), () {
            if (_connectedUserId != null) {
              _connect(_connectedUserId!);
            }
          });
        },
        onError: (error) {
          Future.delayed(const Duration(seconds: 5), () {
            if (_connectedUserId != null) {
              _connect(_connectedUserId!);
            }
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
        if (_connectedUserId != null) {
          _connect(_connectedUserId!);
        }
      });
    }
  }

  void disconnect() {
    _pingTimer?.cancel();
    _channel?.sink.close();
    _controller?.close();
    _connectedUserId = null;
    _channel = null;
  }

  bool get isConnected => _channel != null;
}
