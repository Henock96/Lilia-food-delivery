// Flux GPS d'affichage de la carte de course (audit du 18/11 : L-4, L-5,
// SEC-18). GPS coupé ou flux en erreur, la carte encartée restait sur
// « Acquisition du signal GPS… » pour toute la course.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lilia_food_delivery/features/deliveries/application/driver_gps_watcher.dart';

Position _point(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 11, 20),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _Gps {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.whileInUse;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  int abonnements = 0;
  final positions = StreamController<Position>.broadcast();
  final service = StreamController<ServiceStatus>.broadcast();
  int changements = 0;

  DriverGpsWatcher watcher({
    Duration weakSignalAfter = const Duration(seconds: 30),
  }) => DriverGpsWatcher(
    distanceFilter: 10,
    onChanged: () => changements++,
    isServiceEnabled: () async => serviceEnabled,
    checkPermission: () async => permission,
    requestPermission: () async => permission = afterRequest,
    positionStream: (_) {
      abonnements++;
      return positions.stream;
    },
    serviceStatusStream: () => service.stream,
    weakSignalAfter: weakSignalAfter,
  );
}

Future<void> _laisserPasser() => Future<void>.delayed(Duration.zero);

void main() {
  late _Gps gps;
  setUp(() => gps = _Gps());

  test('un point reçu passe la carte en direct', () async {
    final w = gps.watcher();
    await w.start();
    expect(w.state, MapGpsState.acquiring);

    gps.positions.add(_point(-4.26, 15.28));
    await _laisserPasser();

    expect(w.state, MapGpsState.live);
    expect(w.position?.latitude, -4.26);
    w.dispose();
  });

  test('localisation éteinte : état explicite, aucun abonnement', () async {
    gps.serviceEnabled = false;
    final w = gps.watcher();
    await w.start();

    expect(w.state, MapGpsState.serviceDisabled);
    expect(w.state.action, MapGpsAction.openLocationSettings);
    expect(gps.abonnements, 0);
    w.dispose();
  });

  test('rallumer la localisation relance le flux tout seul', () async {
    gps.serviceEnabled = false;
    final w = gps.watcher();
    await w.start();

    gps.serviceEnabled = true;
    gps.service.add(ServiceStatus.enabled);
    await _laisserPasser();
    await _laisserPasser();

    expect(w.state, MapGpsState.acquiring);
    expect(gps.abonnements, 1);
    w.dispose();
  });

  test('refus ponctuel puis autorisation redemandée sur place', () async {
    gps.permission = LocationPermission.denied;
    final w = gps.watcher();
    await w.start();
    expect(w.state, MapGpsState.denied);
    expect(w.state.action, MapGpsAction.requestPermission);

    await w.requestPermissionAndStart();

    expect(w.state, MapGpsState.acquiring);
    expect(gps.abonnements, 1);
    w.dispose();
  });

  test('refus définitif : renvoi aux réglages de l’app', () async {
    gps.permission = LocationPermission.deniedForever;
    final w = gps.watcher();
    await w.start();

    expect(w.state, MapGpsState.deniedForever);
    expect(w.state.action, MapGpsAction.openAppSettings);
    expect(w.state.actionLabel, 'Réglages');
    w.dispose();
  });

  test('erreur du flux : état récupérable, pas de spinner éternel', () async {
    final w = gps.watcher();
    await w.start();

    gps.positions.addError(Exception('capteur'));
    await _laisserPasser();
    expect(w.state, MapGpsState.streamFailed);
    expect(w.state.action, MapGpsAction.retry);

    gps.positions.addError(const LocationServiceDisabledException());
    await _laisserPasser();
    expect(w.state, MapGpsState.serviceDisabled);
    w.dispose();
  });

  test('aucun point au bout du délai : signal faible, jamais d’attente '
      'infinie', () async {
    final w = gps.watcher(weakSignalAfter: const Duration(milliseconds: 20));
    await w.start();

    await Future<void>.delayed(const Duration(milliseconds: 40));

    expect(w.state, MapGpsState.weakSignal);
    expect(w.state.message, isNot(contains('Acquisition')));
    w.dispose();
  });

  test('redémarrer ne double jamais l’abonnement', () async {
    final w = gps.watcher();
    // Deux démarrages concurrents (réessai pendant le premier) : un seul
    // abonnement survit.
    await Future.wait([w.start(), w.start()]);
    await w.start();

    gps.positions.add(_point(-4.26, 15.28));
    await _laisserPasser();

    expect(gps.positions.hasListener, isTrue);
    expect(w.state, MapGpsState.live);
    expect(gps.abonnements, 2, reason: 'le démarrage doublé est écarté');
    w.dispose();
    expect(gps.positions.hasListener, isFalse);
  });

  test('dispose libère le flux et fait taire les rappels', () async {
    final w = gps.watcher();
    await w.start();
    w.dispose();
    final avant = gps.changements;

    gps.positions.add(_point(-4.26, 15.28));
    gps.service.add(ServiceStatus.disabled);
    await _laisserPasser();

    expect(gps.positions.hasListener, isFalse);
    expect(gps.service.hasListener, isFalse);
    expect(gps.changements, avant);
  });
}
