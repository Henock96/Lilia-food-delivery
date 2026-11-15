import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_exception.dart';
import '../../../models/delivery.dart';
import '../../../models/delivery_offer.dart';
import '../../profile/application/profile_controller.dart';
import '../data/delivery_repository.dart';
import 'deliveries_controller.dart';

part 'available_deliveries_controller.g.dart';

/// Issue d'une tentative d'acceptation — ce que l'écran affiche.
sealed class ClaimOutcome {
  const ClaimOutcome();
}

/// La course est à lui : elle apparaît dans Missions, « À récupérer ».
class ClaimWon extends ClaimOutcome {
  const ClaimWon(this.delivery);
  final Delivery delivery;
}

/// Un autre livreur l'a prise (409 `DELIVERY_ALREADY_TAKEN`), ou la commande
/// n'est plus proposée (annulée, recherche close).
class ClaimTaken extends ClaimOutcome {
  const ClaimTaken(this.message);
  final String message;
}

/// Second appui pendant un claim en cours : rien à montrer.
class ClaimIgnored extends ClaimOutcome {
  const ClaimIgnored();
}

/// Le livreur ne peut pas la prendre : déjà engagé, hors ligne, compte…
class ClaimRefused extends ClaimOutcome {
  const ClaimRefused(this.message, {this.busy = false});
  final String message;
  final bool busy;
}

/// Réseau ou serveur : rien n'est décidé, réessayer.
class ClaimFailed extends ClaimOutcome {
  const ClaimFailed(this.message);
  final String message;
}

/// Codes du serveur (`delivery-claim.service.ts`). Le message vient du
/// serveur ; le code décide du geste de l'app.
const _takenCodes = {
  'DELIVERY_ALREADY_TAKEN',
  'ORDER_NOT_READY',
  'DISPATCH_CLOSED',
};

/// Commandes prêtes que ce livreur peut accepter (dispatch FCFS).
///
/// Le serveur est la vérité : la liste et l'issue du claim ne dépendent
/// d'aucun push. Le push `delivery_offer` / `delivery_offer_taken` ne fait
/// que déclencher une relecture ; le polling de `MissionsSync` et le retour
/// au premier plan en font autant.
///
/// `keepAlive` : le polling et les pushs le relisent même quand l'onglet
/// n'est pas affiché ; détruit entre deux relectures, il refaisait une
/// requête de construction à chaque cycle et écrivait dans un état disposé.
@Riverpod(keepAlive: true)
class AvailableDeliveriesController extends _$AvailableDeliveriesController {
  @override
  FutureOr<AvailableDeliveries> build() =>
      ref.watch(deliveryRepositoryProvider).getAvailableDeliveries();

  /// Geste « Actualiser » : la liste reste affichée pendant la relecture
  /// (le `RefreshIndicator` porte l'attente) ; sans liste, l'erreur s'affiche.
  Future<void> refresh() async {
    if (!state.hasValue) state = const AsyncValue.loading();
    state = await AsyncValue.guard(
      () => ref.read(deliveryRepositoryProvider).getAvailableDeliveries(),
    );
  }

  /// Relecture de fond : la liste affichée reste à l'écran pendant la
  /// requête, un échec ne remplace pas une liste déjà là.
  Future<bool> syncSilently() async {
    try {
      state = AsyncValue.data(
        await ref.read(deliveryRepositoryProvider).getAvailableDeliveries(),
      );
      return true;
    } catch (e, st) {
      debugPrint('[Disponibles] relecture de fond en échec : $e');
      if (!state.hasValue) state = AsyncValue.error(e, st);
      return false;
    }
  }

  /// Retire une carte sans attendre le serveur (push « course prise »).
  void removeLocally(String deliveryId) {
    final current = state.asData?.value;
    if (current == null) return;
    state = AsyncValue.data(current.without(deliveryId));
  }

  bool _claiming = false;

  /// Réseau coupé ou réponse perdue : le serveur a PEUT-ÊTRE accepté. On
  /// relit tout (liste, missions, statut) plutôt que d'annoncer un échec ;
  /// réessayer est sûr, le claim du gagnant se rejoue en 200.
  ClaimOutcome _uncertain() {
    unawaited(syncSilently());
    ref.read(missionsControllerProvider.notifier).refresh();
    ref.invalidate(profileControllerProvider);
    return const ClaimFailed(
      'Réponse non reçue. Vérifiez vos missions avant de réessayer.',
    );
  }

  /// « ACCEPTER LA LIVRAISON ». Une seule tentative à la fois : un double
  /// appui n'envoie pas deux claims (le serveur rejouerait en 200 de toute
  /// façon, mais l'écran n'a pas à clignoter).
  Future<ClaimOutcome> claim(String deliveryId) async {
    if (_claiming) return const ClaimIgnored();
    _claiming = true;
    try {
      final delivery = await ref
          .read(deliveryRepositoryProvider)
          .claimDelivery(deliveryId);
      // Gagnée : elle sort des disponibles, entre dans Missions, et le
      // livreur est passé ON_DELIVERY côté serveur.
      removeLocally(deliveryId);
      ref.read(missionsControllerProvider.notifier).refresh();
      ref.invalidate(profileControllerProvider);
      return ClaimWon(delivery);
    } on ApiException catch (e) {
      if (e.statusCode == 409 && _takenCodes.contains(e.code)) {
        removeLocally(deliveryId);
        // La liste est relue tout de suite : d'autres courses ont pu
        // apparaître, et celle-ci a vraiment disparu.
        unawaited(syncSilently());
        return ClaimTaken(e.message);
      }
      if (e.statusCode == 409 || e.statusCode == 403) {
        unawaited(syncSilently());
        return ClaimRefused(e.message, busy: e.code == 'DRIVER_BUSY');
      }
      if (e.statusCode == 404) {
        removeLocally(deliveryId);
        return const ClaimTaken('Cette commande n’est plus disponible.');
      }
      return _uncertain();
    } catch (_) {
      return _uncertain();
    } finally {
      _claiming = false;
    }
  }
}
