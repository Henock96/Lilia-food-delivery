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

  Future<void> acceptDelivery(String deliveryId) async {
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .acceptDelivery(deliveryId);
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

  Future<void> acceptDelivery() async {
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .acceptDelivery(deliveryId);
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
