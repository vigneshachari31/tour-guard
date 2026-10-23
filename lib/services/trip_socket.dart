import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/geofence_update.dart';
import 'api_service.dart';

/// One authenticated connection per active trip; HTTP remains a reconnect fallback.
class TripSocket {
  final ApiService api;
  final int tripId;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _listener;
  Completer<void>? _ready;
  Completer<GeofenceUpdate>? _reply;
  bool _closed = false;
  TripSocket(this.api, this.tripId);

  Future<void> _connect() async {
    final token = await api.getToken();
    if (_closed) throw StateError('Tracking stopped');
    if (token == null) {
      throw const ApiException('Please sign in again.', statusCode: 401);
    }
    final base = Uri.parse(api.baseUrl);
    final channel = WebSocketChannel.connect(
      base.replace(
        scheme: base.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws/trips/$tripId/track',
        query: null,
      ),
    );
    _channel = channel;
    await channel.ready.timeout(const Duration(seconds: 5));
    if (_closed) {
      await channel.sink.close();
      throw StateError('Tracking stopped');
    }
    _ready = Completer<void>();
    _listener = channel.stream.listen(
      (raw) {
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          if (data['event'] == 'READY' && !(_ready?.isCompleted ?? true)) {
            _ready!.complete();
          }
          if (data['event'] == 'LOCATION_UPDATE' ||
              data['event'] == 'TRIP_COMPLETED') {
            if (!(_reply?.isCompleted ?? true)) {
              _reply!.complete(GeofenceUpdate.fromJson(data));
            }
          }
        } catch (_) {
          /* Invalid frames time out and fall back to HTTP. */
        }
      },
      onError: (_) => _disconnected(),
      onDone: _disconnected,
    );
    channel.sink.add(jsonEncode({'token': token}));
    await _ready!.future.timeout(const Duration(seconds: 5));
  }

  void _disconnected() {
    _channel = null;
    if (!(_ready?.isCompleted ?? true)) {
      _ready!.completeError(StateError('Tracking disconnected'));
    }
    if (!(_reply?.isCompleted ?? true)) {
      _reply!.completeError(StateError('Tracking disconnected'));
    }
  }

  Future<GeofenceUpdate> send(double lat, double lng) async {
    if (_channel == null) await _connect();
    _reply = Completer<GeofenceUpdate>();
    _channel!.sink.add(jsonEncode({'lat': lat, 'lng': lng}));
    return _reply!.future.timeout(const Duration(seconds: 8));
  }

  void dispose() {
    _closed = true;
    _listener?.cancel();
    _channel?.sink.close();
    _disconnected();
    _channel = null;
  }
}
