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
