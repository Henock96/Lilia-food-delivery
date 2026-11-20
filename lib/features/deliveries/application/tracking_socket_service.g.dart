// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_socket_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(trackingSocketService)
final trackingSocketServiceProvider = TrackingSocketServiceProvider._();

final class TrackingSocketServiceProvider
    extends
        $FunctionalProvider<
          TrackingSocketService,
          TrackingSocketService,
          TrackingSocketService
        >
    with $Provider<TrackingSocketService> {
  TrackingSocketServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trackingSocketServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trackingSocketServiceHash();

  @$internal
  @override
  $ProviderElement<TrackingSocketService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TrackingSocketService create(Ref ref) {
    return trackingSocketService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TrackingSocketService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TrackingSocketService>(value),
    );
  }
}

String _$trackingSocketServiceHash() =>
    r'f8e04214b6083e38413eebc1f19f45dc8dd08ad6';
