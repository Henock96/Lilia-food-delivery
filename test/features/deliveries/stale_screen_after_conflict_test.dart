import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/deliveries_controller.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:lilia_food_delivery/models/delivery.dart';

/// Ce qu'on voit après un geste refusé par le serveur.
///
/// ## Le scénario, qui n'a rien d'exotique sur la 4G de Brazzaville
///
/// `RetryInterceptor` rejoue automatiquement `PATCH` sur 5xx et timeout. Si
/// `PATCH /deliveries/:id/accept` **expire après** que le serveur a commis, le
/// rejeu tombe sur le verrou optimiste et reçoit « Livraison déjà acceptée ou
/// non assignée ».
///
/// Le backend a raison. Mais le contrôleur plaçait l'état en `AsyncValue.error`
/// **sans resynchroniser** : le livreur voyait une erreur sur une action qui
/// avait réussi, et devait tirer pour rafraîchir.
///
/// ## Pourquoi seulement sur un conflit
///
/// Rafraîchir sur **toute** erreur ferait marteler l'API pendant une coupure
/// réseau — précisément quand elle est déjà en difficulté, et alors que rien
/// n'a changé côté serveur. On ne resynchronise que lorsque le serveur nous
/// dit que l'état a bougé, c'est-à-dire sur un 4xx.
class _FakeRepository implements DeliveryRepository {
  _FakeRepository(this._onAccept);

  final Future<Delivery> Function() _onAccept;
  int getDeliveryCalls = 0;

  static final _delivery = Delivery.fromJson({
    'id': 'd1',
    'orderId': 'o1',
    'status': 'ACCEPTER',
  });

  @override
  Future<Delivery> acceptDelivery(String deliveryId) => _onAccept();

  @override
  Future<Delivery> getDelivery(String deliveryId) async {
    getDeliveryCalls++;
    return _delivery;
  }

  @override
  Future<List<Delivery>> getMyMissions() async => [_delivery];

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non utilisé ici');
}

void main() {
  late ProviderContainer container;
  late _FakeRepository repo;

  void build(Future<Delivery> Function() onAccept) {
    repo = _FakeRepository(onAccept);
    container = ProviderContainer(
      overrides: [deliveryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
  }

  DeliveryDetailController notifier() =>
      container.read(deliveryDetailControllerProvider('d1').notifier);

  /// Abonne le conteneur comme le fait l'écran.
  ///
  /// ⚠️ Sans abonné, `ref.invalidateSelf()` marque le provider périmé **sans le
  /// reconstruire** : Riverpod ne recalcule que ce que quelqu'un observe. Un
  /// test sans écoute mesurerait donc l'absence d'écran, pas l'absence de
  /// resynchronisation — et rendrait un vert trompeur. C'est le même piège que
  /// « un provider que personne n'observe n'est jamais construit ».
  void watchLikeTheScreen() {
    container.listen(
      deliveryDetailControllerProvider('d1'),
      (_, _) {},
      fireImmediately: true,
    );
  }

  test('un conflit resynchronise l’écran sur l’état réel du serveur', () async {
    build(
      () async => throw const ApiException(
        'Livraison déjà acceptée ou non assignée',
        statusCode: 400,
        kind: ApiErrorKind.client,
      ),
    );
    watchLikeTheScreen();
    await container.read(deliveryDetailControllerProvider('d1').future);
    final before = repo.getDeliveryCalls;

    await expectLater(notifier().acceptDelivery(), throwsA(isA<ApiException>()));
    // Laisse la resynchronisation s'exécuter.
    await Future<void>.delayed(Duration.zero);

    expect(
      repo.getDeliveryCalls,
      greaterThan(before),
      reason: 'le serveur dit que l’état a bougé — l’écran doit aller le relire',
    );
  });

  test('une coupure réseau ne déclenche AUCUNE relecture', () async {
    build(
      () async => throw const ApiException(
        'Connexion impossible. Vérifiez votre réseau.',
        kind: ApiErrorKind.network,
      ),
    );
    watchLikeTheScreen();
    await container.read(deliveryDetailControllerProvider('d1').future);
    final before = repo.getDeliveryCalls;

    await expectLater(notifier().acceptDelivery(), throwsA(isA<ApiException>()));
    await Future<void>.delayed(Duration.zero);

    // Rien n'a changé côté serveur, et le réseau est déjà en difficulté :
    // insister le martèlerait pour rien.
    expect(repo.getDeliveryCalls, before);
  });

  test('l’erreur reste remontée à l’appelant', () async {
    build(
      () async => throw const ApiException(
        'Livraison déjà acceptée',
        statusCode: 400,
        kind: ApiErrorKind.client,
      ),
    );
    watchLikeTheScreen();
    await container.read(deliveryDetailControllerProvider('d1').future);

    // La resynchronisation ne doit pas avaler l'erreur : l'écran affiche
    // toujours le message, il cesse seulement d'être périmé.
    await expectLater(notifier().acceptDelivery(), throwsA(isA<ApiException>()));
  });
}
