// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'tracking_resume_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(trackingResumeService)
final trackingResumeServiceProvider = TrackingResumeServiceProvider._();

final class TrackingResumeServiceProvider
    extends
        $FunctionalProvider<
          TrackingResumeService,
          TrackingResumeService,
          TrackingResumeService
        >
    with $Provider<TrackingResumeService> {
  TrackingResumeServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'trackingResumeServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$trackingResumeServiceHash();

  @$internal
  @override
  $ProviderElement<TrackingResumeService> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  TrackingResumeService create(Ref ref) {
    return trackingResumeService(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(TrackingResumeService value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<TrackingResumeService>(value),
    );
  }
}

String _$trackingResumeServiceHash() =>
    r'3a100ccb39be2f9f44a8fc498ff3839d01f917d4';
