import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../constants/app_constants.dart';
import '../../auth/data/auth_repository.dart';

part 'tracking_socket_service.g.dart';

/// Service Socket.io pour pousser la position du livreur en temps réel
/// vers le namespace `/tracking` du backend.
///
/// Backend : `tracking.gateway.ts` — events :
///   driver → server : `driver:position { orderId, lat, lng, accuracy? }`
///   server → driver : (rien, juste ack)
///
/// Fallback : si la connexion WS échoue, le caller peut utiliser
/// `DeliveryRepository.updateLocation` (HTTP PATCH) à la place.
class TrackingSocketService {
  final AuthRepository _auth;
  io.Socket? _socket;
  bool _isConnecting = false;

  TrackingSocketService(this._auth);

  bool get isConnected => _socket?.connected ?? false;

  /// Connexion lazy — appelée la 1ère fois qu'on veut envoyer une position.
  /// Reconnexion auto gérée par socket_io_client.
  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;

    try {
      final token = await _auth.getIdToken();
      if (token == null) {
        debugPrint('[Tracking WS] Pas de token Firebase, connexion annulée');
        return;
      }

      // Disconnect any stale socket
      _socket?.dispose();

      _socket = io.io(
        '${AppConstants.wsUrl}${AppConstants.trackingNamespace}',
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setAuth({'token': token})
            .enableReconnection()
            .setReconnectionAttempts(10)
            .setReconnectionDelay(2000)
            .setReconnectionDelayMax(10000)
            .disableAutoConnect()
            .build(),
      );

      _socket!
        ..onConnect((_) => debugPrint('[Tracking WS] connected uid=${_socket?.id}'))
        ..onDisconnect((reason) => debugPrint('[Tracking WS] disconnected: $reason'))
        ..onConnectError((e) => debugPrint('[Tracking WS] connect error: $e'))
        ..onError((e) => debugPrint('[Tracking WS] error: $e'));

      _socket!.connect();
    } catch (e) {
      debugPrint('[Tracking WS] connect threw: $e');
    } finally {
      _isConnecting = false;
    }
  }

  /// Pousse la position du livreur. Échec silencieux si pas connecté
  /// (le caller utilise HTTP fallback).
  bool emitPosition({
    required String orderId,
    required double lat,
    required double lng,
    double? accuracy,
  }) {
    final socket = _socket;
    if (socket == null || !socket.connected) return false;
    socket.emit('driver:position', {
      'orderId': orderId,
      'lat': lat,
      'lng': lng,
      'accuracy': ?accuracy,
    });
    return true;
  }

  /// Reconnecte avec un token frais — appelé après refresh Firebase token.
  Future<void> reconnect() async {
    _socket?.dispose();
    _socket = null;
    await connect();
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}

@Riverpod(keepAlive: true)
TrackingSocketService trackingSocketService(Ref ref) {
  final auth = ref.watch(authRepositoryProvider);
  final service = TrackingSocketService(auth);
  ref.onDispose(() => service.disconnect());
  return service;
}
