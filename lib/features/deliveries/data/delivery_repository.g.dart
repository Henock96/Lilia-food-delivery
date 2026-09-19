// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'delivery_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deliveryRepository)
final deliveryRepositoryProvider = DeliveryRepositoryProvider._();

final class DeliveryRepositoryProvider
    extends
        $FunctionalProvider<
          DeliveryRepository,
          DeliveryRepository,
          DeliveryRepository
        >
    with $Provider<DeliveryRepository> {
  DeliveryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deliveryRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deliveryRepositoryHash();

  @$internal
  @override
  $ProviderElement<DeliveryRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeliveryRepository create(Ref ref) {
    return deliveryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeliveryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeliveryRepository>(value),
    );
  }
}

String _$deliveryRepositoryHash() =>
    r'8c2f42b435d498a1390c5ce257bce6b0aff7496a';

/// Ce qui reste dû au livreur connecté.
///
/// ⚠️ Lecture pure : la consulter ne verrouille aucune course et ne déclenche
/// aucun versement. Elle peut donc être rafraîchie librement.

@ProviderFor(myOutstanding)
final myOutstandingProvider = MyOutstandingProvider._();

/// Ce qui reste dû au livreur connecté.
///
/// ⚠️ Lecture pure : la consulter ne verrouille aucune course et ne déclenche
/// aucun versement. Elle peut donc être rafraîchie librement.

final class MyOutstandingProvider
    extends
        $FunctionalProvider<
          AsyncValue<DriverOutstanding>,
          DriverOutstanding,
          FutureOr<DriverOutstanding>
        >
    with
        $FutureModifier<DriverOutstanding>,
        $FutureProvider<DriverOutstanding> {
  /// Ce qui reste dû au livreur connecté.
  ///
  /// ⚠️ Lecture pure : la consulter ne verrouille aucune course et ne déclenche
  /// aucun versement. Elle peut donc être rafraîchie librement.
  MyOutstandingProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myOutstandingProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myOutstandingHash();

  @$internal
  @override
  $FutureProviderElement<DriverOutstanding> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<DriverOutstanding> create(Ref ref) {
    return myOutstanding(ref);
  }
}

String _$myOutstandingHash() => r'bd9d91b9c128fe1dc9430bc391fab1ecb9610b64';

/// Les versements déjà reçus par le livreur connecté.

@ProviderFor(mySettlements)
final mySettlementsProvider = MySettlementsProvider._();

/// Les versements déjà reçus par le livreur connecté.

final class MySettlementsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<DriverSettlement>>,
          List<DriverSettlement>,
          FutureOr<List<DriverSettlement>>
        >
    with
        $FutureModifier<List<DriverSettlement>>,
        $FutureProvider<List<DriverSettlement>> {
  /// Les versements déjà reçus par le livreur connecté.
  MySettlementsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'mySettlementsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$mySettlementsHash();

  @$internal
  @override
  $FutureProviderElement<List<DriverSettlement>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<DriverSettlement>> create(Ref ref) {
    return mySettlements(ref);
  }
}

String _$mySettlementsHash() => r'5bc4cea81d4baa612dd65520603d143baddccd60';
