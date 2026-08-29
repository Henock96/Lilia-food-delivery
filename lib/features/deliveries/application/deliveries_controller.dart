import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/delivery.dart';
import '../data/delivery_repository.dart';
import 'location_service.dart';

part 'deliveries_controller.g.dart';

/// Liste de mes missions actives (ASSIGNER + EN_TRANSIT)
@riverpod
class MissionsController extends _$MissionsController {
  @override
  FutureOr<List<Delivery>> build() =>
      ref.watch(deliveryRepositoryProvider).getMyMissions();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(deliveryRepositoryProvider).getMyMissions(),
    );
  }

  /// Accepte la mission. Le tracking GPS ne démarre PAS ici : le livreur n'a
  /// pas encore le repas, diffuser sa position ferait croire au client que la
  /// commande est en route. Il démarre à la récupération ([confirmPickup]).
  Future<void> acceptDelivery(String deliveryId) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(deliveryRepositoryProvider).acceptDelivery(deliveryId);
      ref.invalidateSelf();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Confirme la récupération du repas : c'est ce geste qui met la commande
  /// EN_ROUTE et prévient le client. Le tracking démarre donc ici.
  Future<void> confirmPickup(String deliveryId) async {
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .confirmPickup(deliveryId);
      final svc = ref.read(locationServiceProvider);
      final granted = await svc.requestPermission();
      if (granted) {
        svc.startTracking(deliveryId: delivery.id, orderId: delivery.orderId);
      }
      ref.invalidateSelf();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}

/// Historique de toutes mes livraisons
@riverpod
class DeliveriesHistoryController extends _$DeliveriesHistoryController {
  @override
  FutureOr<List<Delivery>> build() =>
      ref.watch(deliveryRepositoryProvider).getMyDeliveries();

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(deliveryRepositoryProvider).getMyDeliveries(),
    );
  }
}

/// Détail d'une livraison spécifique
@riverpod
class DeliveryDetailController extends _$DeliveryDetailController {
  @override
  FutureOr<Delivery> build(String deliveryId) =>
      ref.watch(deliveryRepositoryProvider).getDelivery(deliveryId);

  /// Accepte la mission : ASSIGNER → ACCEPTER.
  ///
  /// Aucun tracking GPS ici. Le livreur va chercher le repas ; sa position
  /// n'intéresse le client qu'une fois la commande en main.
  Future<void> acceptDelivery() async {
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .acceptDelivery(deliveryId);
      state = AsyncValue.data(delivery);
      ref.read(missionsControllerProvider.notifier).refresh();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Confirme la récupération du repas : ACCEPTER → EN_TRANSIT.
  ///
  /// Côté backend, la commande passe EN_ROUTE et le client reçoit enfin
  /// « votre commande est en route ». C'est aussi le moment où le partage de
  /// position devient pertinent.
  Future<void> confirmPickup() async {
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .confirmPickup(deliveryId);
      state = AsyncValue.data(delivery);
      final svc = ref.read(locationServiceProvider);
      final granted = await svc.requestPermission();
      if (granted) {
        svc.startTracking(deliveryId: delivery.id, orderId: delivery.orderId);
      }
      ref.read(missionsControllerProvider.notifier).refresh();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  Future<void> markDelivered() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(deliveryRepositoryProvider)
          .updateStatus(deliveryId, DeliveryStatus.livrer),
    );
    ref.read(locationServiceProvider).stopTracking();
    ref.read(missionsControllerProvider.notifier).refresh();
  }

  Future<void> markFailed() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref
          .read(deliveryRepositoryProvider)
          .updateStatus(deliveryId, DeliveryStatus.echec),
    );
    ref.read(locationServiceProvider).stopTracking();
    ref.read(missionsControllerProvider.notifier).refresh();
  }
}
