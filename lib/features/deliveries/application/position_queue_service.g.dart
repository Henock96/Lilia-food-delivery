// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'position_queue_service.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(positionQueueService)
final positionQueueServiceProvider = PositionQueueServiceProvider._();

final class PositionQueueServiceProvider
    extends
        $FunctionalProvider<
          AsyncValue<PositionQueueService>,
          PositionQueueService,
          FutureOr<PositionQueueService>
        >
    with
        $FutureModifier<PositionQueueService>,
        $FutureProvider<PositionQueueService> {
  PositionQueueServiceProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'positionQueueServiceProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$positionQueueServiceHash();

  @$internal
  @override
  $FutureProviderElement<PositionQueueService> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<PositionQueueService> create(Ref ref) {
    return positionQueueService(ref);
  }
}

String _$positionQueueServiceHash() =>
    r'fd91439a90916e31c83bcb2347be478ad4e50296';
