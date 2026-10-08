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
/// `PATCH /deliveries/:id/accept` **expire après** que le serveur a commis, ou
/// un second appareil a déjà agi : le serveur répond « Livraison déjà acceptée
/// ou non assignée », ou la réponse ne revient jamais.
///
/// Le contrôleur plaçait l'état en `AsyncValue.error` **sans resynchroniser** :
/// le livreur voyait une erreur sur une action qui avait réussi, et devait
/// tirer pour rafraîchir.
///
/// ## Pourquoi aussi sur une coupure réseau (DEL-003, octobre 2026)
///
/// Cette suite exigeait autrefois de NE PAS relire sur une coupure, pour ne pas
/// marteler l'API. Mais depuis que les `PATCH` ne sont plus rejoués
/// automatiquement, une coupure est justement le cas ambigu : le serveur a
/// peut-être commis. Une seule relecture par geste du livreur tranche la
/// question ; ce n'est pas un martèlement.
class _FakeRepository implements DeliveryRepository {
  _FakeRepository(this._onAccept);

  final Future<Delivery> Function() _onAccept;
  int getDeliveryCalls = 0;

  /// État réel côté serveur, tel que la relecture le rend. `ASSIGNER` : le
  /// geste n'a pas eu lieu ; `EN_ATTENTE` : la mission a été retirée.
  String serverStatus = 'ASSIGNER';

  Delivery get _delivery => Delivery.fromJson({
    'id': 'd1',
    'orderId': 'o1',
    'status': serverStatus,
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
    repo.serverStatus = 'EN_ATTENTE'; // mission retirée entre-temps
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

  test('une coupure réseau déclenche UNE relecture (DEL-003)', () async {
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

    // Le serveur a peut-être commis : une relecture, une seule, le dira.
    expect(repo.getDeliveryCalls, before + 1);
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
    // toujours le message, il cesse seulement d'être périmé. (Si la relecture
    // disait ACCEPTER, l'acceptation aurait eu lieu et il n'y aurait pas
    // d'erreur : voir `critical_mutation_reconcile_test.dart`.)
    await expectLater(notifier().acceptDelivery(), throwsA(isA<ApiException>()));
  });
}
