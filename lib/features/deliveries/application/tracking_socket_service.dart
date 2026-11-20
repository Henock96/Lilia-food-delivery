import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../../../constants/app_constants.dart';
import '../../auth/data/auth_repository.dart';

part 'tracking_socket_service.g.dart';

/// Fabrique la connexion. Point d'injection pour les tests, qui n'ouvrent
/// aucun vrai socket.
typedef SocketFactory = io.Socket Function(
  String url,
  Map<String, dynamic> options,
);

io.Socket _socketReel(String url, Map<String, dynamic> options) =>
    io.io(url, options);

/// Service Socket.io pour pousser la position du livreur en temps réel
/// vers le namespace `/tracking` du backend.
///
/// Backend : `tracking.gateway.ts` — events :
///   driver → server : `driver:position { orderId, lat, lng, accuracy? }`
///   server → driver : (rien, juste ack)
///
/// Fallback : si la connexion WS échoue, le caller peut utiliser
/// `DeliveryRepository.updateLocation` (HTTP PATCH) à la place.
///
/// **Jeton.** Il est relu auprès de Firebase à **chaque** tentative de
/// connexion (`setAuthFn`), et non capturé une fois à l'ouverture. Le jeton
/// figé expirait au bout d'une heure : la gateway coupait la socket à la
/// première émission (`io server disconnect`, que Socket.io ne relance pas),
/// et le relais par `firebaseIdTokenProvider` n'agissait que si la socket
/// était **encore** connectée — jamais, donc. Le suivi restait sur le repli
/// HTTP jusqu'à la fin de la course. `getIdToken()` rend le jeton en cache
/// s'il est valide et le renouvelle sinon : pas de second système de jetons.
class TrackingSocketService {
  final AuthRepository _auth;
  final SocketFactory _fabrique;
  final DateTime Function() _maintenant;
  io.Socket? _socket;
  bool _isConnecting = false;
  DateTime? _derniereTentative;

  /// Écart minimal entre deux reconnexions déclenchées par [emitPosition].
  /// Une émission a lieu toutes les 5 s : sans ce plafond, un serveur qui
  /// refuse (compte suspendu) provoquerait une connexion par position.
  static const delaiEntreRelances = Duration(seconds: 30);

  TrackingSocketService(
    this._auth, {
    SocketFactory? fabrique,
    DateTime Function()? maintenant,
  })  : _fabrique = fabrique ?? _socketReel,
        _maintenant = maintenant ?? DateTime.now;

  bool get isConnected => _socket?.connected ?? false;

  /// Connexion lazy — appelée la 1ère fois qu'on veut envoyer une position.
  /// Reconnexion auto gérée par socket_io_client.
  Future<void> connect() async {
    if (isConnected || _isConnecting) return;
    _isConnecting = true;
    _derniereTentative = _maintenant();

    try {
      final token = await _auth.getIdToken();
      if (token == null) {
        debugPrint('[Tracking WS] Pas de token Firebase, connexion annulée');
        return;
      }

      // Disconnect any stale socket
      _socket?.dispose();

      _socket = _fabrique(
        '${AppConstants.wsUrl}${AppConstants.trackingNamespace}',
        io.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .setAuthFn(_jetonFrais)
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

  /// Appelé par Socket.io à chaque ouverture du transport, reconnexions
  /// automatiques comprises. Le rappel doit toujours être servi, sans quoi la
  /// poignée de main reste suspendue : un jeton vide fait refuser la
  /// connexion par la gateway, ce qui laisse la main au repli HTTP.
  void _jetonFrais(void Function(Map<dynamic, dynamic> auth) rappel) {
    _auth.getIdToken().then(
          (token) => rappel({'token': token ?? ''}),
          onError: (Object e) {
            debugPrint('[Tracking WS] jeton indisponible : $e');
            rappel({'token': ''});
          },
        );
  }

  /// Pousse la position du livreur. Échec silencieux si pas connecté
  /// (le caller utilise HTTP fallback).
  ///
  /// Socket tombée (coupure serveur, dix tentatives épuisées) : une nouvelle
  /// connexion est relancée en arrière-plan, au plus une fois par
  /// [delaiEntreRelances]. Cette position-ci part en HTTP.
  bool emitPosition({
    required String orderId,
    required double lat,
    required double lng,
    double? accuracy,
  }) {
    final socket = _socket;
    if (socket == null || !socket.connected) {
      _relancerSiPossible();
      return false;
    }
    socket.emit('driver:position', {
      'orderId': orderId,
      'lat': lat,
      'lng': lng,
      'accuracy': ?accuracy,
    });
    return true;
  }

  void _relancerSiPossible() {
    final derniere = _derniereTentative;
    if (derniere != null &&
        _maintenant().difference(derniere) < delaiEntreRelances) {
      return;
    }
    unawaited(connect());
  }

  /// Reconnecte avec un token frais.
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
