// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(deliveryNotificationService)
final deliveryNotificationServiceProvider =
    DeliveryNotificationServiceProvider._();

final class DeliveryNotificationServiceProvider
    extends
        $FunctionalProvider<
          DeliveryNotificationService,
          DeliveryNotificationService,
          DeliveryNotificationService
        >
    with $Provider<DeliveryNotificationService> {
  DeliveryNotificationServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'deliveryNotificationServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$deliveryNotificationServiceHash();

  @$internal
  @override
  $ProviderElement<DeliveryNotificationService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DeliveryNotificationService create(Ref ref) {
    return deliveryNotificationService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DeliveryNotificationService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DeliveryNotificationService>(value),
    );
  }
}

String _$deliveryNotificationServiceHash() =>
    r'76a3d47fee5b4b93924ff4cec01a41dfdc14a731';
