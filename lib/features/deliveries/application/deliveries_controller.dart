import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/delivery.dart';
import '../data/delivery_repository.dart';
import 'location_service.dart';
import 'tracking_issue.dart';

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

  // La confirmation de récupération vit dans `DeliveryDetailController` : le
  // livreur la déclenche depuis l'écran de détail, jamais depuis la liste.
  //
  // Une seconde implémentation existait ici, jamais appelée. Elle utilisait
  // l'ancien `requestPermission()`, qui rend un simple booléen : un refus de
  // localisation y était avalé, et le livreur croyait être suivi alors
  // qu'aucune position ne partait. C'est précisément le défaut corrigé dans
  // `DeliveryDetailController` — le duplicat mort le conservait, prêt à
  // resurgir au premier branchement.
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

  /// Refuse la mission : elle redevient assignable pour le vendeur.
  Future<void> declineDelivery({String? reason}) async {
    state = const AsyncValue.loading();
    try {
      await ref
          .read(deliveryRepositoryProvider)
          .declineDelivery(deliveryId, reason: reason);
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
  /// Confirme la récupération et démarre le partage de position.
  ///
  /// Renvoie le motif si la localisation n'a pas pu être activée — la
  /// récupération, elle, a bien eu lieu. L'appelant affiche ce motif au
  /// livreur : auparavant, un refus de permission était avalé et le livreur
  /// croyait être suivi alors qu'aucune position ne partait.
  Future<LocationPermissionResult?> confirmPickup() async {
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .confirmPickup(deliveryId);
      state = AsyncValue.data(delivery);

      final svc = ref.read(locationServiceProvider);
      final permission = await svc.requestPermissionDetailed();
      if (permission.granted) {
        svc.startTracking(deliveryId: delivery.id, orderId: delivery.orderId);
      }

      // Le snackbar de l'écran dit le problème à l'instant T ; le bandeau, lui,
      // reste tant que la cause dure. Le livreur qui balaie le premier sans le
      // lire garde le second sous les yeux jusqu'à ce qu'il agisse.
      ref
          .read(trackingIssueControllerProvider.notifier)
          .report(permission, deliveryId: delivery.id);

      ref.read(missionsControllerProvider.notifier).refresh();
      return permission.granted ? null : permission;
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
    // La course est terminée : une alerte de suivi n'a plus d'objet.
    ref.read(trackingIssueControllerProvider.notifier).clear();
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
    // La course est terminée : une alerte de suivi n'a plus d'objet.
    ref.read(trackingIssueControllerProvider.notifier).clear();
    ref.read(missionsControllerProvider.notifier).refresh();
  }
}
