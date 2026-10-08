import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lilia_food_delivery/core/network/api_client.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/deliveries_controller.dart';
import 'package:lilia_food_delivery/features/deliveries/application/location_service.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:lilia_food_delivery/models/delivery.dart';

/// DEL-003 — après un échec ambigu, l'app relit l'état du serveur au lieu de
/// conclure sur le code HTTP.
///
/// Le scénario de terrain : le livreur touche « J'ai récupéré » ou « Livrée »,
/// le serveur commit, la 4G décroche avant la réponse. Avant, l'app affichait
/// une erreur sur un geste réussi et laissait le suivi GPS dans le mauvais état
/// (jamais démarré après la récupération, jamais arrêté après la livraison).

Delivery _d(String status) =>
    Delivery.fromJson({'id': 'd1', 'orderId': 'o1', 'status': status});

const _timeout = ApiException(
  'Le serveur met trop de temps à répondre.',
  kind: ApiErrorKind.timeout,
);
const _network = ApiException(
  'Connexion impossible. Vérifiez votre réseau.',
  kind: ApiErrorKind.network,
);
const _badCode = ApiException(
  'Code de remise incorrect. 4 essais restants.',
  statusCode: 400,
  kind: ApiErrorKind.client,
  code: 'HANDOVER_CODE_INVALID',
);

/// Serveur simulé. `server` est l'état « réel » ; chaque mutation peut le
/// faire avancer puis échouer (réponse perdue) ou échouer sans rien changer.
class _FakeRepo extends DeliveryRepository {
  _FakeRepo(this.server)
    : super(
        ApiClient.test(
          baseUrl: 'http://test.invalid',
          tokenProvider: () async => null,
          forceRefreshToken: () async => null,
        ),
      );

  String server;

  /// Ce que la mutation fait au serveur avant de répondre (`null` = rien).
  String? commitTo;

  /// Erreur renvoyée par la mutation (`null` = succès).
  Object? mutationError;

  /// Le serveur est-il joignable pour la relecture ?
  bool getFails = false;

  /// Retient la mutation jusqu'à complétion — pour le double tap.
  Completer<void>? gate;

  int mutationCalls = 0;
  int getCalls = 0;

  Future<Delivery> _mutate() async {
    mutationCalls++;
    if (gate != null) await gate!.future;
    if (commitTo != null) server = commitTo!;
    if (mutationError != null) throw mutationError!;
    return _d(server);
  }

  @override
  Future<Delivery> getDelivery(String id) async {
    getCalls++;
    if (getFails) throw _network;
    return _d(server);
  }

  @override
  Future<List<Delivery>> getMyMissions() async => [_d(server)];

  @override
  Future<Delivery> acceptDelivery(String id) => _mutate();

  @override
  Future<Delivery> confirmPickup(String id) => _mutate();

  @override
  Future<Delivery> updateStatus(
    String id,
    DeliveryStatus status, {
    String? handoverCode,
  }) => _mutate();
}

/// Suivi GPS simulé : on n'observe que démarrages et arrêts.
class _FakeLocation implements LocationService {
  String? tracking;
  int starts = 0;
  int stops = 0;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<LocationPermissionResult> requestPermissionDetailed() async =>
      const LocationPermissionResult(granted: true);

  @override
  void startTracking({required String deliveryId, required String orderId}) {
    starts++;
    tracking = deliveryId;
  }

  @override
  void stopTracking() {
    stops++;
    tracking = null;
  }

  @override
  bool get isTracking => tracking != null;

  @override
  String? get activeDeliveryId => tracking;

  @override
  String? get activeOrderId => tracking == null ? null : 'o1';

  @override
  Position? get lastPosition => null;
}

void main() {
  late _FakeRepo repo;
  late _FakeLocation location;
  late ProviderContainer container;

  Future<DeliveryDetailController> open(String status) async {
    repo = _FakeRepo(status);
    location = _FakeLocation();
    container = ProviderContainer(
      overrides: [
        deliveryRepositoryProvider.overrideWithValue(repo),
        locationServiceProvider.overrideWithValue(location),
      ],
    );
    addTearDown(container.dispose);
    // Abonné comme l'écran : sans lui, un provider autoDispose disparaît.
    container.listen(deliveryDetailControllerProvider('d1'), (_, _) {});
    await container.read(deliveryDetailControllerProvider('d1').future);
    return container.read(deliveryDetailControllerProvider('d1').notifier);
  }

  DeliveryStatus? shown() =>
      container.read(deliveryDetailControllerProvider('d1')).value?.status;

  group('Récupération (PATCH /pickup)', () {
    test('Cas A — commit puis délai dépassé : relu EN_TRANSIT ⇒ succès, '
        'suivi démarré', () async {
      final c = await open('ACCEPTER');
      repo
        ..commitTo = 'EN_TRANSIT'
        ..mutationError = _timeout;

      final issue = await c.confirmPickup();

      expect(issue, isNull, reason: 'pas d’erreur : la récupération a eu lieu');
      expect(repo.getCalls, greaterThan(1), reason: 'état relu au serveur');
      expect(shown(), DeliveryStatus.en_transit);
      expect(location.tracking, 'd1');
    });

    test('vraie erreur : relu ACCEPTER ⇒ erreur remontée, écran récupérable, '
        'aucun suivi', () async {
      final c = await open('ACCEPTER');
      repo.mutationError = _network;

      await expectLater(c.confirmPickup(), throwsA(_network));
      expect(shown(), DeliveryStatus.accepter, reason: 'le geste reste à refaire');
      expect(location.starts, 0);
    });
  });

  group('Livraison (PATCH /status LIVRER)', () {
    test('Cas B — commit puis délai dépassé : relu LIVRER ⇒ succès, suivi '
        'arrêté', () async {
      final c = await open('EN_TRANSIT');
      location.startTracking(deliveryId: 'd1', orderId: 'o1');
      repo
        ..commitTo = 'LIVRER'
        ..mutationError = _timeout;

      await c.markDelivered(handoverCode: '1234');

      expect(shown(), DeliveryStatus.livrer);
      expect(location.tracking, isNull);
      expect(location.stops, 1);
    });

    test('Cas C — vraie erreur (code faux) : relu EN_TRANSIT ⇒ erreur '
        'affichée, suivi toujours actif', () async {
      final c = await open('EN_TRANSIT');
      location.startTracking(deliveryId: 'd1', orderId: 'o1');
      repo.mutationError = _badCode;

      await expectLater(
        c.markDelivered(handoverCode: '0000'),
        throwsA(_badCode),
      );
      expect(shown(), DeliveryStatus.en_transit);
      expect(location.tracking, 'd1');
      expect(location.stops, 0);
    });

    test('course close autrement (échec déclaré par l’admin) : erreur dite, '
        'suivi arrêté', () async {
      final c = await open('EN_TRANSIT');
      location.startTracking(deliveryId: 'd1', orderId: 'o1');
      repo
        ..commitTo = 'ECHEC'
        ..mutationError = const ApiException(
          'Cette livraison a changé d’état entre-temps.',
          statusCode: 409,
          kind: ApiErrorKind.client,
        );

      await expectLater(
        c.markDelivered(handoverCode: '1234'),
        throwsA(isA<ApiException>()),
      );
      expect(shown(), DeliveryStatus.echec);
      expect(location.tracking, isNull);
    });
  });

  test('Cas D — double tap : une seule requête, même issue pour les deux',
      () async {
    final c = await open('EN_TRANSIT');
    location.startTracking(deliveryId: 'd1', orderId: 'o1');
    repo
      ..commitTo = 'LIVRER'
      ..gate = Completer<void>();

    final first = c.markDelivered(handoverCode: '1234');
    final second = c.markDelivered(handoverCode: '1234');
    repo.gate!.complete();
    await Future.wait([first, second]);

    expect(repo.mutationCalls, 1);
    expect(shown(), DeliveryStatus.livrer);
    expect(location.stops, 1);
  });

  test('Cas E — backend injoignable (mutation ET relecture) : erreur '
      'd’origine, écran inchangé, suivi inchangé', () async {
    final c = await open('EN_TRANSIT');
    location.startTracking(deliveryId: 'd1', orderId: 'o1');
    repo
      ..mutationError = _network
      ..getFails = true;

    await expectLater(c.markDelivered(handoverCode: '1234'), throwsA(_network));
    expect(shown(), DeliveryStatus.en_transit);
    expect(location.tracking, 'd1');
  });

  test('Acceptation : commit puis réponse perdue ⇒ relu ACCEPTER ⇒ succès',
      () async {
    final c = await open('ASSIGNER');
    repo
      ..commitTo = 'ACCEPTER'
      ..mutationError = _network;

    await c.acceptDelivery();
    expect(shown(), DeliveryStatus.accepter);
  });

  test('après une issue, un nouveau geste repart (la garde est libérée)',
      () async {
    final c = await open('EN_TRANSIT');
    repo.mutationError = _badCode;
    await expectLater(c.markDelivered(handoverCode: '0000'), throwsA(_badCode));

    repo
      ..mutationError = null
      ..commitTo = 'LIVRER';
    await c.markDelivered(handoverCode: '1234');
    expect(repo.mutationCalls, 2);
    expect(shown(), DeliveryStatus.livrer);
  });
}
