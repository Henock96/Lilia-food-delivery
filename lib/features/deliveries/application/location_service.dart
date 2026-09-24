import 'dart:async';
import 'dart:io' show Platform;

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

  StreamSubscription<Position>? _positionSub;
  Timer? _heartbeat;
  String? _activeDeliveryId;
  String? _activeOrderId;
  Position? _lastPosition;

  /// Dernière position reçue pendant la course — jointe à une déclaration
  /// d'échec (F3-05) comme preuve de présence. `null` hors course.
  Position? get lastPosition => _lastPosition;
  DateTime? _lastPublishedAt;
  int _publishCount = 0;

  /// Cadence maximale de publication. Le flux GPS peut émettre bien plus
  /// souvent ; on ne sature ni le socket ni la 4G de Brazzaville pour autant.
  static const _minPublishInterval = Duration(seconds: 5);

  /// Cadence minimale : un livreur arrêté à un feu n'émet aucun point (filtre
  /// de distance), mais son marqueur ne doit pas paraître mort côté client —
  /// les métadonnées Redis expirent au bout de 5 minutes.
  static const _heartbeatInterval = Duration(seconds: 20);

  /// 1 écriture HTTP sur 3 publications : garantit une trace en base même
  /// quand le WebSocket fonctionne, sans écrire à chaque point.
  static const _httpEveryNPublishes = 3;

  /// Distance minimale entre deux points remontés par l'OS.
  static const _distanceFilterMeters = 10;

  /// Réglages de collecte, par plateforme.
  ///
  /// C'est ici que se joue le suivi écran éteint. La version précédente
  /// appelait `getCurrentPosition` dans un `Timer.periodic` : les deux sont
  /// suspendus par Android et iOS dès que l'app quitte le premier plan, si
  /// bien que le suivi s'arrêtait quand le livreur rangeait son téléphone —
  /// c'est-à-dire pendant à peu près toute la course.
  static LocationSettings _settings() {
    if (Platform.isAndroid) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        // Service de premier plan : Android continue de livrer les positions
        // et le livreur voit en permanence que sa position est transmise.
        // La notification est le prix — assumé — de l'honnêteté.
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Livraison en cours',
          notificationText:
              'Votre position est partagée avec le client jusqu\'à la '
              'livraison.',
          notificationChannelName: 'Suivi de livraison',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }
    if (Platform.isIOS) {
      return AppleSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: _distanceFilterMeters,
        // Nécessite `UIBackgroundModes: location` dans Info.plist.
        allowBackgroundLocationUpdates: true,
        // Bandeau bleu système : le livreur sait qu'il est suivi. Le masquer
        // serait techniquement possible et déontologiquement douteux.
        showBackgroundLocationIndicator: true,
        // iOS met les mises à jour en pause quand il juge l'appareil immobile.
        // Pendant une course, une pause est indistinguable d'une panne côté
        // client.
        pauseLocationUpdatesAutomatically: false,
      );
    }
    return const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: _distanceFilterMeters,
    );
  }

  LocationService(this._repo, this._ws, this._ref);

  Future<bool> requestPermission() async {
    return (await requestPermissionDetailed()).granted;
  }

  /// Variante qui dit **pourquoi** la localisation n'est pas disponible.
  ///
  /// `requestPermission()` renvoyait un simple `false` : l'appelant ne
  /// démarrait pas le tracking et n'affichait rien. Le livreur croyait donc
  /// être suivi alors qu'aucune position ne partait — et le client voyait un
  /// marqueur figé sans explication. Un refus doit se dire, et se dire
  /// précisément : couper le GPS et refuser l'autorisation n'appellent pas la
  /// même action de l'utilisateur.
  Future<LocationPermissionResult> requestPermissionDetailed() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return const LocationPermissionResult(
        granted: false,
        reason: LocationDenialReason.serviceDisabled,
      );
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.deniedForever) {
      return const LocationPermissionResult(
        granted: false,
        reason: LocationDenialReason.deniedForever,
      );
    }

    final granted =
        permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;

    return LocationPermissionResult(
      granted: granted,
      reason: granted ? null : LocationDenialReason.denied,
    );
  }

  /// Démarre le tracking pour la livraison + commande.
  /// - deliveryId : ID Delivery (pour fallback HTTP `/deliveries/:id/location`)
  /// - orderId    : ID Order (pour event WS `driver:position`)
  void startTracking({required String deliveryId, required String orderId}) {
    if (_activeDeliveryId == deliveryId && _positionSub != null) return;
    stopTracking();

    _activeDeliveryId = deliveryId;
    _activeOrderId = orderId;
    _publishCount = 0;
    _lastPublishedAt = null;

    // Connexion WS lazy en arrière-plan
    _ws.connect();

    _positionSub = Geolocator.getPositionStream(
      locationSettings: _settings(),
    ).listen(
      _onPosition,
      // GPS momentanément indisponible (tunnel, permission révoquée en cours
      // de course) : on ne tue pas l'abonnement, il repartira tout seul.
      onError: (Object e) => debugPrint('[LocationService] flux GPS : $e'),
      cancelOnError: false,
    );

    // Le battement ne survit pas à l'arrière-plan (les timers y sont
    // suspendus) — c'est voulu : en arrière-plan, c'est le flux GPS qui
    // publie. Il ne sert qu'au livreur arrêté, app à l'écran.
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => _publishHeartbeat());
  }

  void stopTracking() {
    _positionSub?.cancel();
    _positionSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
    _activeDeliveryId = null;
    _activeOrderId = null;
    _lastPosition = null;
    _lastPublishedAt = null;
    _publishCount = 0;
  }

  void _onPosition(Position position) {
    _lastPosition = position;
    final since = _lastPublishedAt == null
        ? null
        : DateTime.now().difference(_lastPublishedAt!);
    if (since != null && since < _minPublishInterval) return;
    unawaited(_publish(position));
  }

  /// Republie la dernière position connue si rien n'est parti récemment.
  ///
  /// Un livreur à l'arrêt n'émet aucun point (filtre de distance) : sans ce
  /// battement, les métadonnées Redis expireraient au bout de 5 minutes et le
  /// client verrait son livreur disparaître alors qu'il est simplement au feu.
  void _publishHeartbeat() {
    final position = _lastPosition;
    if (position == null) return;
    final since = _lastPublishedAt == null
        ? null
        : DateTime.now().difference(_lastPublishedAt!);
    if (since != null && since < _heartbeatInterval) return;
    unawaited(_publish(position));
  }

  Future<void> _publish(Position position) async {
    final deliveryId = _activeDeliveryId;
    final orderId = _activeOrderId;
    if (deliveryId == null || orderId == null) return;

    _lastPublishedAt = DateTime.now();
    _publishCount++;

    // 1. Toujours essayer WebSocket en premier
    final wsSent = _ws.emitPosition(
      orderId: orderId,
      lat: position.latitude,
      lng: position.longitude,
      accuracy: position.accuracy,
    );

    // 2. Repli HTTP : si le WS est indisponible, ou une publication sur N pour
    //    garantir une trace en base même quand le WS fonctionne.
    final shouldFallbackHttp =
        !wsSent || (_publishCount % _httpEveryNPublishes == 0);
    if (!shouldFallbackHttp) return;

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

  bool get isTracking => _positionSub != null;
  String? get activeDeliveryId => _activeDeliveryId;
  String? get activeOrderId => _activeOrderId;
}

@Riverpod(keepAlive: true)
LocationService locationService(Ref ref) => LocationService(
  ref.watch(deliveryRepositoryProvider),
  ref.watch(trackingSocketServiceProvider),
  ref,
);


/// Pourquoi la position n'est pas disponible.
///
/// Chaque cas appelle une action différente de la part du livreur : rallumer
/// la localisation, réessayer, ou passer par les réglages système. Les
/// confondre en un seul `false` ne lui permettait de rien faire.
enum LocationDenialReason {
  /// La localisation de l'appareil est éteinte.
  serviceDisabled,

  /// Refus ponctuel : redemander est possible.
  denied,

  /// Refus définitif : seul un passage par les réglages système débloque.
  deniedForever,
}

class LocationPermissionResult {
  const LocationPermissionResult({required this.granted, this.reason});

  final bool granted;
  final LocationDenialReason? reason;

  /// Message affichable tel quel, formulé côté livreur.
  String get message => switch (reason) {
    LocationDenialReason.serviceDisabled =>
      'La localisation de votre téléphone est désactivée. Activez-la pour '
          'que le client puisse suivre sa commande.',
    LocationDenialReason.deniedForever =>
      'L\'accès à votre position est bloqué. Autorisez-le dans les réglages '
          'du téléphone pour que le client puisse suivre sa commande.',
    LocationDenialReason.denied =>
      'Sans accès à votre position, le client ne pourra pas suivre sa '
          'commande. Vous pouvez continuer la livraison normalement.',
    null => '',
  };
}
