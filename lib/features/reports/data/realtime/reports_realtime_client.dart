import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models/report_realtime_event.dart';

sealed class ReportsRealtimeSignal {
  const ReportsRealtimeSignal();
}

/// Emitted after Socket.IO has an authenticated connection. A reconnect is
/// reported with [isReconnect] so listeners can resync through REST.
class ReportsRealtimeConnected extends ReportsRealtimeSignal {
  final bool isReconnect;

  const ReportsRealtimeConnected({required this.isReconnect});
}

class ReportsRealtimeChanged extends ReportsRealtimeSignal {
  final ReportRealtimeEvent event;

  const ReportsRealtimeChanged(this.event);
}

/// Transport boundary so provider tests never open a real network socket.
abstract class ReportsRealtimeClient {
  Stream<ReportsRealtimeSignal> get signals;

  Future<void> connect({required String baseUrl, required String token});

  Future<void> disconnect();

  void dispose();
}

/// Socket.IO client for the `/reports` namespace.
///
/// The token is sent in the handshake auth payload. The server validates it
/// and assigns identity-scoped rooms; this client never joins a room itself.
class SocketIoReportsRealtimeClient implements ReportsRealtimeClient {
  final StreamController<ReportsRealtimeSignal> _signals =
      StreamController<ReportsRealtimeSignal>.broadcast();

  io.Socket? _socket;
  String? _baseUrl;
  String? _token;
  bool _hasConnected = false;
  bool _disposed = false;

  @override
  Stream<ReportsRealtimeSignal> get signals => _signals.stream;

  @override
  Future<void> connect({required String baseUrl, required String token}) async {
    if (_disposed) return;

    final normalized = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    if (_socket != null && _baseUrl == normalized && _token == token) return;

    // Close the previous socket synchronously before creating the next one so
    // rapid auth changes cannot leave an orphaned connection behind.
    _closeSocket();
    if (_disposed) return;

    _baseUrl = normalized;
    _token = token;

    final socket = io.io(
      '$normalized/reports',
      io.OptionBuilder()
          .setTransports(['websocket', 'polling'])
          .disableAutoConnect()
          .setAuth({'token': token})
          .enableReconnection()
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
          .enableForceNew()
          .build(),
    );
    _socket = socket;

    socket.onConnect((_) {
      if (_disposed || _socket != socket) return;
      _signals.add(ReportsRealtimeConnected(isReconnect: _hasConnected));
      _hasConnected = true;
    });

    socket.on('report:changed', (payload) {
      if (_disposed || _socket != socket) return;
      final event = ReportRealtimeEvent.tryParse(payload);
      if (event != null) _signals.add(ReportsRealtimeChanged(event));
    });

    socket.onConnectError((error) {
      if (_disposed || _socket != socket) return;
      // A rejected token will never succeed by retrying. Stop the socket and
      // let the auth lifecycle open a new one after a fresh sign-in.
      if (_isAuthError(error)) {
        debugPrint('[Reports realtime] connection rejected; waiting for auth');
        _closeSocket();
      }
    });

    socket.on('reports:error', (_) {
      if (_disposed || _socket != socket) return;
      _closeSocket();
    });

    socket.connect();
  }

  @override
  Future<void> disconnect() async {
    _closeSocket();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeSocket();
    unawaited(_signals.close());
  }

  void _closeSocket() {
    final socket = _socket;
    _socket = null;
    _baseUrl = null;
    _token = null;
    _hasConnected = false;
    socket?.dispose();
  }

  bool _isAuthError(Object? error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('unauthorized') ||
        message.contains('session expired');
  }
}
