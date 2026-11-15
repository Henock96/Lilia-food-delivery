// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dispatch_capability.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(dispatchCapability)
final dispatchCapabilityProvider = DispatchCapabilityProvider._();

final class DispatchCapabilityProvider
    extends
        $FunctionalProvider<
          DispatchCapabilityDeclarer,
          DispatchCapabilityDeclarer,
          DispatchCapabilityDeclarer
        >
    with $Provider<DispatchCapabilityDeclarer> {
  DispatchCapabilityProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'dispatchCapabilityProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$dispatchCapabilityHash();

  @$internal
  @override
  $ProviderElement<DispatchCapabilityDeclarer> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  DispatchCapabilityDeclarer create(Ref ref) {
    return dispatchCapability(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DispatchCapabilityDeclarer value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DispatchCapabilityDeclarer>(value),
    );
  }
}

String _$dispatchCapabilityHash() =>
    r'730093797b3878a485e82ecd59a9a5b923d0d509';
