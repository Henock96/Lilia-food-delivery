import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_client.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/available_deliveries_controller.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:lilia_food_delivery/models/delivery.dart';
import 'package:lilia_food_delivery/models/delivery_offer.dart';

/// Serveur simulé du dispatch FCFS : la liste, puis l'issue du claim.
class _FakeRepo extends DeliveryRepository {
  _FakeRepo()
    : super(
        ApiClient.test(
          baseUrl: 'http://test',
          tokenProvider: () async => null,
          forceRefreshToken: () async => null,
        ),
      );

  List<String> offers = ['d-1', 'd-2'];
  Object? claimError;
  int claims = 0;
  int lists = 0;

  @override
  Future<AvailableDeliveries> getAvailableDeliveries() async {
    lists++;
    return AvailableDeliveries(
      offers: [
        for (final id in offers)
          DeliveryOffer.fromJson({'deliveryId': id, 'orderRef': '#$id'}),
      ],
      dispatchEnabled: true,
      ineligibility: null,
    );
  }

  @override
  Future<List<Delivery>> getMyMissions() async => const [];

  @override
  Future<Delivery> claimDelivery(String id) async {
    claims++;
    final err = claimError;
    if (err != null) throw err;
    offers.remove(id);
    return Delivery.fromJson({
      'id': id,
      'orderId': 'o-$id',
      'status': 'ACCEPTER',
      'createdAt': '2026-11-10T12:00:00.000Z',
      'updatedAt': '2026-11-10T12:00:00.000Z',
    });
  }
}

void main() {
  late _FakeRepo repo;
  late ProviderContainer container;

  setUp(() {
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [deliveryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  });

  Future<AvailableDeliveries> loaded() =>
      container.read(availableDeliveriesControllerProvider.future);

  test('gagné : la carte sort de la liste, la mission est rendue', () async {
    await loaded();
    final outcome = await container
        .read(availableDeliveriesControllerProvider.notifier)
        .claim('d-1');
    expect(outcome, isA<ClaimWon>());
    expect((outcome as ClaimWon).delivery.status, DeliveryStatus.accepter);
    final after = container.read(availableDeliveriesControllerProvider).value!;
    expect(after.offers.map((o) => o.deliveryId), ['d-2']);
  });

  test('409 DELIVERY_ALREADY_TAKEN : message du serveur, carte retirée', () async {
    await loaded();
    repo.claimError = const ApiException(
      'Désolé, cette commande vient d’être acceptée par un autre livreur.',
      statusCode: 409,
      kind: ApiErrorKind.client,
      code: 'DELIVERY_ALREADY_TAKEN',
    );
    repo.offers = ['d-2']; // le serveur, lui, ne la propose plus
    final outcome = await container
        .read(availableDeliveriesControllerProvider.notifier)
        .claim('d-1');
    expect(outcome, isA<ClaimTaken>());
    expect(
      (outcome as ClaimTaken).message,
      'Désolé, cette commande vient d’être acceptée par un autre livreur.',
    );
    final after = container.read(availableDeliveriesControllerProvider).value!;
    expect(after.offers.map((o) => o.deliveryId), isNot(contains('d-1')));
    // Et la liste a été relue au serveur, pas seulement amputée.
    await Future<void>.delayed(Duration.zero);
    expect(repo.lists, greaterThanOrEqualTo(2));
  });

  test('409 DRIVER_BUSY : refusé, la carte reste', () async {
    await loaded();
    repo.claimError = const ApiException(
      'Vous avez déjà une livraison en cours.',
      statusCode: 409,
      kind: ApiErrorKind.client,
      code: 'DRIVER_BUSY',
    );
    final outcome = await container
        .read(availableDeliveriesControllerProvider.notifier)
        .claim('d-1');
    expect(outcome, isA<ClaimRefused>());
    expect((outcome as ClaimRefused).busy, isTrue);
  });

  test('403 DRIVER_NOT_ELIGIBLE : refusé avec le message du serveur', () async {
    await loaded();
    repo.claimError = const ApiException(
      'Passez « Disponible » pour accepter une livraison.',
      statusCode: 403,
      kind: ApiErrorKind.client,
      code: 'DRIVER_NOT_ELIGIBLE',
    );
    final outcome = await container
        .read(availableDeliveriesControllerProvider.notifier)
        .claim('d-1');
    expect(outcome, isA<ClaimRefused>());
    expect((outcome as ClaimRefused).message, contains('Disponible'));
  });

  test('panne réseau : rien n’est décidé, la carte reste', () async {
    await loaded();
    repo.claimError = const ApiException(
      'hors ligne',
      kind: ApiErrorKind.network,
    );
    final outcome = await container
        .read(availableDeliveriesControllerProvider.notifier)
        .claim('d-1');
    expect(outcome, isA<ClaimFailed>());
    final after = container.read(availableDeliveriesControllerProvider).value!;
    expect(after.offers.map((o) => o.deliveryId), contains('d-1'));
  });

  test('un double appui n’envoie qu’un claim', () async {
    await loaded();
    final notifier = container.read(
      availableDeliveriesControllerProvider.notifier,
    );
    final results = await Future.wait([
      notifier.claim('d-1'),
      notifier.claim('d-1'),
    ]);
    expect(repo.claims, 1);
    expect(results.whereType<ClaimWon>(), hasLength(1));
    expect(results.whereType<ClaimIgnored>(), hasLength(1));
  });

  test('réponse perdue : message neutre, tout est relu', () async {
    await loaded();
    final before = repo.lists;
    repo.claimError = const ApiException(
      'timeout',
      kind: ApiErrorKind.network,
    );
    final outcome = await container
        .read(availableDeliveriesControllerProvider.notifier)
        .claim('d-1');
    expect(outcome, isA<ClaimFailed>());
    expect((outcome as ClaimFailed).message, contains('Vérifiez vos missions'));
    await Future<void>.delayed(Duration.zero);
    expect(repo.lists, greaterThan(before));
  });
}
