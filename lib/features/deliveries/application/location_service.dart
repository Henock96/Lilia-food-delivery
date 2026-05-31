import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../data/delivery_repository.dart';
import 'position_queue_service.dart';
import 'tracking_socket_service.dart';

part 'location_service.g.dart';

/// Envoie la position GPS au backend pendant EN_TRANSIT.
///
/// Stratégie :
///  - WebSocket (Socket.io /tracking) toutes les 5s — temps réel
///  - Fallback HTTP PATCH /deliveries/:id/location toutes les 15s si WS indisponible
///
/// Le caller (deliveries_controller) doit appeler :
///  - `startTracking(deliveryId, orderId)` après acceptDelivery()
///  - `stopTracking()` après markDelivered() / markFailed()
class LocationService {
  final DeliveryRepository _repo;
  final TrackingSocketService _ws;
  final Ref _ref;

  Timer? _timer;
  String? _activeDeliveryId;
  String? _activeOrderId;
  int _tickCount = 0;

  // Fréquences
  static const _wsInterval = Duration(seconds: 5);   // push WebSocket
  static const _httpEveryNTicks = 3;                  // 1 HTTP toutes les 3 ticks (= 15s)

  LocationService(this._repo, this._ws, this._ref);

  Future<bool> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  /// Démarre le tracking pour la livraison + commande.
  /// - deliveryId : ID Delivery (pour fallback HTTP `/deliveries/:id/location`)
  /// - orderId    : ID Order (pour event WS `driver:position`)
  void startTracking({required String deliveryId, required String orderId}) {
    if (_activeDeliveryId == deliveryId && _timer != null) return;
    stopTracking();

    _activeDeliveryId = deliveryId;
    _activeOrderId = orderId;
    _tickCount = 0;

    // Connexion WS lazy en arrière-plan
    _ws.connect();

    _sendLocation();
    _timer = Timer.periodic(_wsInterval, (_) => _sendLocation());
  }

  void stopTracking() {
    _timer?.cancel();
    _timer = null;
    _activeDeliveryId = null;
    _activeOrderId = null;
    _tickCount = 0;
  }

  Future<void> _sendLocation() async {
    final deliveryId = _activeDeliveryId;
    final orderId = _activeOrderId;
    if (deliveryId == null || orderId == null) return;

    Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
    } catch (e) {
      debugPrint('[LocationService] GPS indisponible : $e');
      return;
    }

    _tickCount++;

    // 1. Toujours essayer WebSocket en premier
    final wsSent = _ws.emitPosition(
      orderId: orderId,
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
    );

    // 2. Fallback HTTP : seulement si WS indisponible, OU tous les N ticks
    //    pour garantir l'écriture DB régulière même si WS marche
    final shouldFallbackHttp = !wsSent || (_tickCount % _httpEveryNTicks == 0);
    if (shouldFallbackHttp) {
      try {
        await _repo.updateLocation(
          deliveryId,
          position.latitude,
          position.longitude,
          position.accuracy,
        );
      } catch (e) {
        debugPrint('⚠️ HTTP PATCH location failed, queueing: $e');
        final queue = await _ref.read(positionQueueServiceProvider.future);
        await queue.enqueue(QueuedPosition(
          deliveryId: deliveryId,
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
          recordedAt: DateTime.now().toUtc(),
        ));
      }
    }
  }

  bool get isTracking => _timer != null;
  String? get activeDeliveryId => _activeDeliveryId;
  String? get activeOrderId => _activeOrderId;
}

@Riverpod(keepAlive: true)
LocationService locationService(Ref ref) => LocationService(
  ref.watch(deliveryRepositoryProvider),
  ref.watch(trackingSocketServiceProvider),
  ref,
);
