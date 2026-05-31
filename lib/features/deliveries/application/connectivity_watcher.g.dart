// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'connectivity_watcher.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(connectivityWatcher)
final connectivityWatcherProvider = ConnectivityWatcherProvider._();

final class ConnectivityWatcherProvider
    extends
        $FunctionalProvider<
          ConnectivityWatcher,
          ConnectivityWatcher,
          ConnectivityWatcher
        >
    with $Provider<ConnectivityWatcher> {
  ConnectivityWatcherProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'connectivityWatcherProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$connectivityWatcherHash();

  @$internal
  @override
  $ProviderElement<ConnectivityWatcher> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConnectivityWatcher create(Ref ref) {
    return connectivityWatcher(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConnectivityWatcher value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConnectivityWatcher>(value),
    );
  }
}

String _$connectivityWatcherHash() =>
    r'ea16b2051ea962122e3d04d1225ec049c3758add';
