import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_failure.dart';
import '../../../core/network/api_exception.dart';
import '../../profile/application/profile_controller.dart';
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

  /// Relecture de fond (DEL-005) : retour au premier plan, polling.
  ///
  /// Contrairement à [refresh], la liste affichée reste à l'écran pendant la
  /// requête — un spinner toutes les 60 s rendrait la liste inutilisable. Un
  /// échec ne remplace pas une liste déjà affichée par un écran d'erreur : le
  /// prochain cycle réessaie, et le geste manuel « Réessayer » reste là pour
  /// montrer l'erreur. Sans liste à l'écran, l'erreur est montrée.
  ///
  /// Rend `true` si la liste a été mise à jour.
  Future<bool> syncSilently() async {
    try {
      final missions = await ref
          .read(deliveryRepositoryProvider)
          .getMyMissions();
      state = AsyncValue.data(missions);
      return true;
    } catch (e, st) {
      debugPrint('[Missions] relecture de fond en échec : $e');
      if (!state.hasValue) state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Accepte la mission. Le tracking GPS ne démarre PAS ici : le livreur n'a
  /// pas encore le repas, diffuser sa position ferait croire au client que la
  /// commande est en route. Il démarre à la récupération ([confirmPickup]).
  Future<void> acceptDelivery(String deliveryId) async {
    state = const AsyncValue.loading();
    try {
      await ref.read(deliveryRepositoryProvider).acceptDelivery(deliveryId);
      ref.invalidateSelf();
      _driverStatusMoved(ref);
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
  ///
  /// Sur échec, l'état réel est relu ([_reconcile]) : si le serveur dit
  /// `ACCEPTER`, l'acceptation a eu lieu et la réponse s'est simplement perdue.
  Future<void> acceptDelivery() => _once('accept', () async {
    final previous = state;
    state = const AsyncValue.loading();
    final Delivery delivery;
    try {
      delivery = await ref
          .read(deliveryRepositoryProvider)
          .acceptDelivery(deliveryId);
    } catch (e, st) {
      final server = await _reconcile(previous);
      if (server?.status != DeliveryStatus.accepter) {
        Error.throwWithStackTrace(e, st);
      }
      ref.read(missionsControllerProvider.notifier).refresh();
      _driverStatusMoved(ref);
      return;
    }
    state = AsyncValue.data(delivery);
    ref.read(missionsControllerProvider.notifier).refresh();
    _driverStatusMoved(ref);
  });

  // ─── Mutations critiques : la vérité est relue au serveur (DEL-003) ───────
  //
  // Une mutation dont la réponse se perd (coupure 4G juste après le commit,
  // délai dépassé, 5xx d'un proxy) ne dit RIEN de ce que le serveur a fait.
  // Conclure « échec » sur le seul code HTTP affichait une erreur sur une
  // livraison réussie et laissait le suivi GPS tourner sans fin ; à l'inverse,
  // une récupération réussie ne démarrait pas le suivi.
  //
  // Après tout échec d'accept / pickup / livraison, on relit donc
  // `GET /deliveries/:id` et on conclut d'après le statut réel. Les `PATCH` ne
  // sont plus rejoués automatiquement (`RetryInterceptor`) : le rejeu ajoutait
  // un second refus au doute, sans rien trancher.

  /// Gestes en cours, par nature. Un second tap pendant le premier reçoit le
  /// même résultat au lieu d'envoyer une seconde requête.
  final Map<String, Future<Object?>> _inFlight = {};

  Future<T> _once<T>(String key, Future<T> Function() action) {
    final running = _inFlight[key];
    if (running != null) return running.then((v) => v as T);
    // Le contrôleur est autoDispose : un livreur qui revient en arrière
    // pendant la requête le détruisait avant la réponse, et ce qui suit
    // l'`await` (démarrer ou arrêter le suivi GPS) n'avait jamais lieu alors
    // que le serveur, lui, avait conclu. Il reste en vie jusqu'à l'issue.
    final keepAlive = ref.keepAlive();
    final future = action();
    _inFlight[key] = future;
    // Libère la garde quelle que soit l'issue ; l'erreur, elle, reste à
    // l'appelant via `future`.
    future.then<void>((_) {}, onError: (_) {}).whenComplete(() {
      if (identical(_inFlight[key], future)) _inFlight.remove(key);
      keepAlive.close();
    });
    return future;
  }

  /// Relit la course après l'échec d'une mutation et place l'écran sur l'état
  /// réel. Rend `null` si le serveur reste injoignable : rien ne peut alors
  /// être conclu, l'écran revient à [previous] et l'erreur d'origine est
  /// remontée par l'appelant.
  Future<Delivery?> _reconcile(AsyncValue<Delivery> previous) async {
    try {
      final server = await ref
          .read(deliveryRepositoryProvider)
          .getDelivery(deliveryId);
      state = AsyncValue.data(server);
      return server;
    } catch (e) {
      // L'erreur d'origine est remontée par l'appelant ; celle-ci est tracée
      // pour qu'une double panne (mutation + relecture) reste diagnostiquable.
      debugPrint('[DeliveryDetail] relecture après échec impossible : $e');
      state = previous;
      return null;
    }
  }

  /// Refuse la mission : elle redevient assignable pour le vendeur.
  ///
  /// Comme les autres gestes (DEL-003), un échec est tranché par une
  /// relecture — mais le refus a une signature propre : réussi, la course
  /// n'appartient plus au livreur et sa relecture est refusée (403/404).
  Future<void> declineDelivery({String? reason}) => _once('decline', () async {
    final previous = state;
    state = const AsyncValue.loading();
    final repo = ref.read(deliveryRepositoryProvider);
    try {
      await repo.declineDelivery(deliveryId, reason: reason);
    } catch (e, st) {
      try {
        final server = await repo.getDelivery(deliveryId);
        // Toujours la sienne : le refus n'a pas eu lieu.
        state = AsyncValue.data(server);
      } on ApiException catch (read) {
        if (read.statusCode == 403 || read.statusCode == 404) {
          // Plus la sienne : le refus est acquis, la réponse s'était perdue.
          ref.read(missionsControllerProvider.notifier).refresh();
          return;
        }
        debugPrint('[DeliveryDetail] relecture après refus impossible : $read');
        state = previous;
      } catch (read) {
        debugPrint('[DeliveryDetail] relecture après refus impossible : $read');
        state = previous;
      }
      Error.throwWithStackTrace(e, st);
    }
    ref.read(missionsControllerProvider.notifier).refresh();
  });

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
  Future<LocationPermissionResult?> confirmPickup() =>
      _once('pickup', () async {
        final previous = state;
        state = const AsyncValue.loading();
        Delivery delivery;
        try {
          delivery = await ref
              .read(deliveryRepositoryProvider)
              .confirmPickup(deliveryId);
        } catch (e, st) {
          // EN_TRANSIT : la récupération est acquise, seule la réponse a été
          // perdue — on enchaîne comme sur un succès. ACCEPTER : rien n'a eu
          // lieu, l'écran reste sur le geste à refaire. Tout autre état (course
          // réassignée, échec déclaré) : l'écran le montre, l'erreur est dite.
          final server = await _reconcile(previous);
          if (server == null || server.status != DeliveryStatus.en_transit) {
            Error.throwWithStackTrace(e, st);
          }
          delivery = server;
        }
        state = AsyncValue.data(delivery);

        final svc = ref.read(locationServiceProvider);
        final permission = await svc.requestPermissionDetailed();
        if (permission.granted) {
          svc.startTracking(deliveryId: delivery.id, orderId: delivery.orderId);
        }

        // Le snackbar de l'écran dit le problème à l'instant T ; le bandeau,
        // lui, reste tant que la cause dure. Le livreur qui balaie le premier
        // sans le lire garde le second sous les yeux jusqu'à ce qu'il agisse.
        ref
            .read(trackingIssueControllerProvider.notifier)
            .report(permission, deliveryId: delivery.id);

        ref.read(missionsControllerProvider.notifier).refresh();
        return permission.granted ? null : permission;
      });

  /// Conclut la course avec le code de remise donné par le client (F-06).
  ///
  /// ⚠️ Lève en cas d'échec au lieu de l'avaler : un code erroné est
  /// désormais un cas ordinaire, et l'écran doit le dire au livreur SANS
  /// quitter la course. Avant, le suivi GPS était coupé et l'écran refermé
  /// même quand le serveur refusait — la course restait ouverte, invisible.
  Future<void> markDelivered({required String handoverCode}) =>
      _once('deliver', () async {
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
        } catch (e, st) {
          // LIVRER : la livraison est acquise (réponse perdue) — on conclut.
          // EN_TRANSIT : code erroné, réseau… la course reste ouverte, le
          // suivi continue. Course close autrement (échec déclaré, annulée) :
          // plus rien à suivre, mais l'erreur est dite.
          final server = await _reconcile(previous);
          if (server == null || server.status != DeliveryStatus.livrer) {
            if (server != null && !server.status.isActive) _endTracking();
            Error.throwWithStackTrace(e, st);
          }
        }
        _endTracking();
        ref.read(missionsControllerProvider.notifier).refresh();
        _driverStatusMoved(ref);
      });

  /// La course est close : plus de position à partager, plus d'alerte de
  /// suivi à montrer.
  void _endTracking() {
    ref.read(locationServiceProvider).stopTracking();
    ref.read(trackingIssueControllerProvider.notifier).clear();
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
    _driverStatusMoved(ref);
    ref.invalidateSelf();
  }
}

/// Le serveur change le statut du livreur avec la course : `ON_DELIVERY` à
/// l'acceptation, retour à `AVAILABLE` à la clôture (DEL-005). Le profil est
/// relu, sans quoi l'app le croirait encore en course — et le polling des
/// missions, réservé au livreur disponible, ne reprendrait jamais.
void _driverStatusMoved(Ref ref) => ref.invalidate(profileControllerProvider);
