// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'available_deliveries_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
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

@ProviderFor(AvailableDeliveriesController)
final availableDeliveriesControllerProvider =
    AvailableDeliveriesControllerProvider._();

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
final class AvailableDeliveriesControllerProvider
    extends
        $AsyncNotifierProvider<
          AvailableDeliveriesController,
          AvailableDeliveries
        > {
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
  AvailableDeliveriesControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'availableDeliveriesControllerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$availableDeliveriesControllerHash();

  @$internal
  @override
  AvailableDeliveriesController create() => AvailableDeliveriesController();
}

String _$availableDeliveriesControllerHash() =>
    r'63cefb9954fff8ee11530ebdfde83d359bdd4924';

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

abstract class _$AvailableDeliveriesController
    extends $AsyncNotifier<AvailableDeliveries> {
  FutureOr<AvailableDeliveries> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AvailableDeliveries>, AvailableDeliveries>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AvailableDeliveries>, AvailableDeliveries>,
              AsyncValue<AvailableDeliveries>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
