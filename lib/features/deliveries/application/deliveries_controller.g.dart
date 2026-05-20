// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'deliveries_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Liste de mes missions actives (ASSIGNER + EN_TRANSIT)

@ProviderFor(MissionsController)
final missionsControllerProvider = MissionsControllerProvider._();

/// Liste de mes missions actives (ASSIGNER + EN_TRANSIT)
final class MissionsControllerProvider
    extends $AsyncNotifierProvider<MissionsController, List<Delivery>> {
  /// Liste de mes missions actives (ASSIGNER + EN_TRANSIT)
  MissionsControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'missionsControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$missionsControllerHash();

  @$internal
  @override
  MissionsController create() => MissionsController();
}

String _$missionsControllerHash() =>
    r'3bf253a9642ef1398e25cb8c593da6bd23d738af';

/// Liste de mes missions actives (ASSIGNER + EN_TRANSIT)

abstract class _$MissionsController extends $AsyncNotifier<List<Delivery>> {
  FutureOr<List<Delivery>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Delivery>>, List<Delivery>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Delivery>>, List<Delivery>>,
              AsyncValue<List<Delivery>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Historique de toutes mes livraisons

@ProviderFor(DeliveriesHistoryController)
final deliveriesHistoryControllerProvider =
    DeliveriesHistoryControllerProvider._();

/// Historique de toutes mes livraisons
final class DeliveriesHistoryControllerProvider
    extends
        $AsyncNotifierProvider<DeliveriesHistoryController, List<Delivery>> {
  /// Historique de toutes mes livraisons
  DeliveriesHistoryControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deliveriesHistoryControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deliveriesHistoryControllerHash();

  @$internal
  @override
  DeliveriesHistoryController create() => DeliveriesHistoryController();
}

String _$deliveriesHistoryControllerHash() =>
    r'b1114c4f9b972a53a767fdd6f1307b4ba6699176';

/// Historique de toutes mes livraisons

abstract class _$DeliveriesHistoryController
    extends $AsyncNotifier<List<Delivery>> {
  FutureOr<List<Delivery>> build();
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<List<Delivery>>, List<Delivery>>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<List<Delivery>>, List<Delivery>>,
              AsyncValue<List<Delivery>>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, build);
  }
}

/// Détail d'une livraison spécifique

@ProviderFor(DeliveryDetailController)
final deliveryDetailControllerProvider = DeliveryDetailControllerFamily._();

/// Détail d'une livraison spécifique
final class DeliveryDetailControllerProvider
    extends $AsyncNotifierProvider<DeliveryDetailController, Delivery> {
  /// Détail d'une livraison spécifique
  DeliveryDetailControllerProvider._({
    required DeliveryDetailControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'deliveryDetailControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$deliveryDetailControllerHash();

  @override
  String toString() {
    return r'deliveryDetailControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  DeliveryDetailController create() => DeliveryDetailController();

  @override
  bool operator ==(Object other) {
    return other is DeliveryDetailControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$deliveryDetailControllerHash() =>
    r'e6cc1bfce4cdd9649eb8947d95c62a9ffd27198a';

/// Détail d'une livraison spécifique

final class DeliveryDetailControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          DeliveryDetailController,
          AsyncValue<Delivery>,
          Delivery,
          FutureOr<Delivery>,
          String
        > {
  DeliveryDetailControllerFamily._()
    : super(
        retry: null,
        name: r'deliveryDetailControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Détail d'une livraison spécifique

  DeliveryDetailControllerProvider call(String deliveryId) =>
      DeliveryDetailControllerProvider._(argument: deliveryId, from: this);

  @override
  String toString() => r'deliveryDetailControllerProvider';
}

/// Détail d'une livraison spécifique

abstract class _$DeliveryDetailController extends $AsyncNotifier<Delivery> {
  late final _$args = ref.$arg as String;
  String get deliveryId => _$args;

  FutureOr<Delivery> build(String deliveryId);
  @$mustCallSuper
  @override
  void runBuild() {
    final ref = this.ref as $Ref<AsyncValue<Delivery>, Delivery>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<Delivery>, Delivery>,
              AsyncValue<Delivery>,
              Object?,
              Object?
            >;
    element.handleCreate(ref, () => build(_$args));
  }
}
