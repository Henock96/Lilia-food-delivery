// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'missions_sync.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(missionsSync)
final missionsSyncProvider = MissionsSyncProvider._();

final class MissionsSyncProvider
    extends $FunctionalProvider<MissionsSync, MissionsSync, MissionsSync>
    with $Provider<MissionsSync> {
  MissionsSyncProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'missionsSyncProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$missionsSyncHash();

  @$internal
  @override
  $ProviderElement<MissionsSync> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  MissionsSync create(Ref ref) {
    return missionsSync(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MissionsSync value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MissionsSync>(value),
    );
  }
}

String _$missionsSyncHash() => r'5c9c20f58b825b4f78f6c870d15b078c93fb9b9f';
