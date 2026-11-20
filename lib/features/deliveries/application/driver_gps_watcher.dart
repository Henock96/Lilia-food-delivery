import 'dart:async';

import 'package:geolocator/geolocator.dart';

import 'location_service.dart';

/// Ce que la carte de course doit dire de la position du livreur.
///
/// Audit du 18/11 (L-4, L-5, SEC-18) : le flux GPS d'affichage ne vérifiait que
/// la permission, sans regarder si la localisation du téléphone était allumée,
/// et n'avait pas d'`onError`. GPS coupé ou flux en erreur, la carte encartée
/// restait sur « Acquisition du signal GPS… » pour toute la course.
enum MapGpsState {
  /// Abonné, aucun point encore reçu.
  acquiring,

  /// Au moins un point reçu.
  live,

  /// Aucun point au bout de [DriverGpsWatcher.weakSignalAfter].
  weakSignal,

  /// La localisation du téléphone est éteinte.
  serviceDisabled,

  /// Refus ponctuel : redemander est possible.
  denied,

  /// Refus définitif : seuls les réglages système débloquent.
  deniedForever,

  /// Le flux a levé une erreur qu'on ne sait pas qualifier.
  streamFailed,
}

/// Le geste proposé au livreur pour sortir de l'état.
enum MapGpsAction {
  none,
  openLocationSettings,
  openAppSettings,
  requestPermission,
  retry,
}

extension MapGpsStateUi on MapGpsState {
  String get message => switch (this) {
    MapGpsState.acquiring => 'Recherche de votre position…',
    MapGpsState.live => '',
    MapGpsState.weakSignal =>
      'Signal GPS faible : votre position n\'est pas encore connue. '
          'La destination reste affichée.',
    MapGpsState.serviceDisabled => const LocationPermissionResult(
      granted: false,
      reason: LocationDenialReason.serviceDisabled,
    ).message,
    MapGpsState.denied => const LocationPermissionResult(
      granted: false,
      reason: LocationDenialReason.denied,
    ).message,
    MapGpsState.deniedForever => const LocationPermissionResult(
      granted: false,
      reason: LocationDenialReason.deniedForever,
    ).message,
    MapGpsState.streamFailed =>
      'Votre position ne peut pas être lue pour le moment.',
  };

  MapGpsAction get action => switch (this) {
    MapGpsState.acquiring || MapGpsState.live => MapGpsAction.none,
    MapGpsState.serviceDisabled => MapGpsAction.openLocationSettings,
    MapGpsState.denied => MapGpsAction.requestPermission,
    MapGpsState.deniedForever => MapGpsAction.openAppSettings,
    MapGpsState.weakSignal || MapGpsState.streamFailed => MapGpsAction.retry,
  };

  /// Libellés alignés sur `TrackingIssueBanner`.
  String? get actionLabel => switch (action) {
    MapGpsAction.none => null,
    MapGpsAction.openLocationSettings => 'Activer',
    MapGpsAction.openAppSettings => 'Réglages',
    MapGpsAction.requestPermission => 'Autoriser',
    MapGpsAction.retry => 'Réessayer',
  };

  /// Un état qui mérite d'être réévalué au retour au premier plan : le livreur
  /// revient peut-être des réglages.
  bool get recoverable => switch (this) {
    MapGpsState.acquiring || MapGpsState.live => false,
    _ => true,
  };
}

/// Flux GPS **d'affichage** d'une carte de course.
///
/// Distinct du `LocationService`, qui publie la position au serveur : celui-ci
/// ne fait que dessiner le marqueur « Vous ». Un seul abonnement à la fois —
/// chaque [start] annule le précédent, et une génération écarte le résultat
/// d'un démarrage doublé par un autre pendant ses `await`.
class DriverGpsWatcher {
  DriverGpsWatcher({
    required this.distanceFilter,
    required void Function() onChanged,
    Future<bool> Function()? isServiceEnabled,
    Future<LocationPermission> Function()? checkPermission,
    Future<LocationPermission> Function()? requestPermission,
    Stream<Position> Function(LocationSettings settings)? positionStream,
    Stream<ServiceStatus> Function()? serviceStatusStream,
    this.weakSignalAfter = const Duration(seconds: 30),
  }) : _onChanged = onChanged,
       _isServiceEnabled =
           isServiceEnabled ?? Geolocator.isLocationServiceEnabled,
       _checkPermission = checkPermission ?? Geolocator.checkPermission,
       _requestPermission = requestPermission ?? Geolocator.requestPermission,
       _positionStream =
           positionStream ??
           ((s) => Geolocator.getPositionStream(locationSettings: s)),
       _serviceStatusStream =
           serviceStatusStream ?? Geolocator.getServiceStatusStream;

  final int distanceFilter;
  final Duration weakSignalAfter;
  final void Function() _onChanged;
  final Future<bool> Function() _isServiceEnabled;
  final Future<LocationPermission> Function() _checkPermission;
  final Future<LocationPermission> Function() _requestPermission;
  final Stream<Position> Function(LocationSettings) _positionStream;
  final Stream<ServiceStatus> Function() _serviceStatusStream;

  MapGpsState _state = MapGpsState.acquiring;
  Position? _position;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<ServiceStatus>? _serviceSub;
  Timer? _weakSignalTimer;
  int _generation = 0;
  bool _disposed = false;

  MapGpsState get state => _state;
  Position? get position => _position;

  Future<void> start() async {
    if (_disposed) return;
    final generation = ++_generation;
    _stopPositionStream();
    _set(MapGpsState.acquiring);
    _watchServiceStatus();

    final serviceEnabled = await _isServiceEnabled();
    if (_stale(generation)) return;
    if (!serviceEnabled) {
      _set(MapGpsState.serviceDisabled);
      return;
    }

    final permission = await _checkPermission();
    if (_stale(generation)) return;
    switch (permission) {
      case LocationPermission.deniedForever:
        _set(MapGpsState.deniedForever);
        return;
      case LocationPermission.denied:
      case LocationPermission.unableToDetermine:
        _set(MapGpsState.denied);
        return;
      case LocationPermission.whileInUse:
      case LocationPermission.always:
        break;
    }

    _weakSignalTimer = Timer(weakSignalAfter, () {
      if (_state == MapGpsState.acquiring) _set(MapGpsState.weakSignal);
    });
    _positionSub =
        _positionStream(
          LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: distanceFilter,
          ),
        ).listen(
          (position) {
            _weakSignalTimer?.cancel();
            _position = position;
            _state = MapGpsState.live;
            _onChanged();
          },
          onError: (Object error) {
            _weakSignalTimer?.cancel();
            _set(switch (error) {
              LocationServiceDisabledException() => MapGpsState.serviceDisabled,
              PermissionDeniedException() => MapGpsState.denied,
              _ => MapGpsState.streamFailed,
            });
          },
          cancelOnError: false,
        );
  }

  /// Redemande l'autorisation sur place, puis repart.
  Future<void> requestPermissionAndStart() async {
    if (_disposed) return;
    await _requestPermission();
    await start();
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _stopPositionStream();
    _serviceSub?.cancel();
    _serviceSub = null;
  }

  /// Rallumer la localisation relance le flux, sans attendre un geste.
  void _watchServiceStatus() {
    _serviceSub ??= _serviceStatusStream().listen(
      (status) {
        if (status == ServiceStatus.enabled &&
            _state == MapGpsState.serviceDisabled) {
          unawaited(start());
        } else if (status == ServiceStatus.disabled) {
          _stopPositionStream();
          _set(MapGpsState.serviceDisabled);
        }
      },
      // Plateforme sans ce flux : on retombe sur le bouton et la reprise au
      // premier plan.
      onError: (Object _) {},
    );
  }

  bool _stale(int generation) => _disposed || generation != _generation;

  void _stopPositionStream() {
    _weakSignalTimer?.cancel();
    _weakSignalTimer = null;
    _positionSub?.cancel();
    _positionSub = null;
  }

  void _set(MapGpsState state) {
    if (_disposed || _state == state) return;
    _state = state;
    _onChanged();
  }
}
