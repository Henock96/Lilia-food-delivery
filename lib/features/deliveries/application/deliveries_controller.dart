import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_failure.dart';
import '../../../core/network/api_exception.dart';
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
      _resyncIfServerMovedOn(e);
      rethrow;
    }
  }

  /// Relit l'état réel quand le serveur dit que la course a bougé.
  ///
  /// ## Le scénario
  ///
  /// `RetryInterceptor` rejoue automatiquement les `PATCH` sur 5xx et timeout.
  /// Si `PATCH /deliveries/:id/accept` **expire après** que le serveur a commis,
  /// le rejeu tombe sur le verrou optimiste et reçoit « Livraison déjà acceptée
  /// ou non assignée ». Le backend a raison ; l'écran, lui, restait périmé — le
  /// livreur voyait une erreur sur une action qui avait réussi, et devait tirer
  /// pour rafraîchir. Sur la 4G de Brazzaville, ce n'est pas un cas de bord.
  ///
  /// ## Pourquoi seulement sur un 4xx
  ///
  /// Relire sur **toute** erreur ferait marteler l'API pendant une coupure
  /// réseau — précisément quand elle est déjà en difficulté, et alors que rien
  /// n'a changé côté serveur. Un `kind: client` est la seule situation où le
  /// serveur nous dit que notre vision de l'état est fausse.
  ///
  /// Best-effort : la relecture ne doit pas remplacer l'erreur d'origine, que
  /// l'appelant affiche au livreur.
  void _resyncIfServerMovedOn(Object error) {
    if (error is! ApiException || error.kind != ApiErrorKind.client) return;
    ref.invalidateSelf();
    ref.read(missionsControllerProvider.notifier).refresh();
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
      _resyncIfServerMovedOn(e);
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

  /// Conclut la course avec le code de remise donné par le client (F-06).
  ///
  /// ⚠️ Lève en cas d'échec au lieu de l'avaler : un code erroné est
  /// désormais un cas ordinaire, et l'écran doit le dire au livreur SANS
  /// quitter la course. Avant, le suivi GPS était coupé et l'écran refermé
  /// même quand le serveur refusait — la course restait ouverte, invisible.
  Future<void> markDelivered({required String handoverCode}) async {
    final previous = state;
    state = const AsyncValue.loading();
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .updateStatus(
            deliveryId,
            DeliveryStatus.livrer,
            handoverCode: handoverCode,
          );
      state = AsyncValue.data(delivery);
    } catch (_) {
      // La course est toujours en cours : on rend l'écran tel qu'il était.
      state = previous;
      rethrow;
    }
    ref.read(locationServiceProvider).stopTracking();
    // La course est terminée : une alerte de suivi n'a plus d'objet.
    ref.read(trackingIssueControllerProvider.notifier).clear();
    ref.read(missionsControllerProvider.notifier).refresh();
  }

  /// Déclare l'échec (F3-05), avec la position de la course comme preuve.
  ///
  /// ⚠️ Lève en cas de refus (attente du protocole non écoulée, réseau) : la
  /// course reste ouverte et le livreur sait pourquoi.
  Future<void> declareFailure(
    DeliveryFailureReason reason, {
    String? note,
  }) async {
    final position = ref.read(locationServiceProvider).lastPosition;
    await ref
        .read(deliveryRepositoryProvider)
        .declareFailure(
          deliveryId,
          reason: reason,
          note: note,
          latitude: position?.latitude,
          longitude: position?.longitude,
        );
    ref.read(locationServiceProvider).stopTracking();
    // La course est terminée : une alerte de suivi n'a plus d'objet.
    ref.read(trackingIssueControllerProvider.notifier).clear();
    ref.read(missionsControllerProvider.notifier).refresh();
    ref.invalidateSelf();
  }
}
