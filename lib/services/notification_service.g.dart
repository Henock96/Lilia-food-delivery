// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'notification_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(fcmTokenRegistrar)
final fcmTokenRegistrarProvider = FcmTokenRegistrarProvider._();

final class FcmTokenRegistrarProvider
    extends
        $FunctionalProvider<
          FcmTokenRegistrar,
          FcmTokenRegistrar,
          FcmTokenRegistrar
        >
    with $Provider<FcmTokenRegistrar> {
  FcmTokenRegistrarProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'fcmTokenRegistrarProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$fcmTokenRegistrarHash();

  @$internal
  @override
  $ProviderElement<FcmTokenRegistrar> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  FcmTokenRegistrar create(Ref ref) {
    return fcmTokenRegistrar(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FcmTokenRegistrar value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FcmTokenRegistrar>(value),
    );
  }
}

String _$fcmTokenRegistrarHash() => r'daea2bd1dd3d0edff940d7a7285b0a278d07f1a9';

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
    r'd6e321ce9116bb3443576f2f0a45155ca24fc40d';
