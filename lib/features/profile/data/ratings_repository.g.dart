// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'ratings_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ratingsRepository)
final ratingsRepositoryProvider = RatingsRepositoryProvider._();

final class RatingsRepositoryProvider
    extends
        $FunctionalProvider<
          RatingsRepository,
          RatingsRepository,
          RatingsRepository
        >
    with $Provider<RatingsRepository> {
  RatingsRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'ratingsRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$ratingsRepositoryHash();

  @$internal
  @override
  $ProviderElement<RatingsRepository> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  RatingsRepository create(Ref ref) {
    return ratingsRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(RatingsRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<RatingsRepository>(value),
    );
  }
}

String _$ratingsRepositoryHash() => r'12ba15c8447e2dd0e5e7bbd1ea83b79579837bcf';

@ProviderFor(myRatings)
final myRatingsProvider = MyRatingsProvider._();

final class MyRatingsProvider
    extends
        $FunctionalProvider<
          AsyncValue<List<MyRating>>,
          List<MyRating>,
          FutureOr<List<MyRating>>
        >
    with $FutureModifier<List<MyRating>>, $FutureProvider<List<MyRating>> {
  MyRatingsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'myRatingsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$myRatingsHash();

  @$internal
  @override
  $FutureProviderElement<List<MyRating>> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<List<MyRating>> create(Ref ref) {
    return myRatings(ref);
  }
}

String _$myRatingsHash() => r'04c6a9ce36cda729df79328c7f0d8eebe865501e';

@ProviderFor(myRatingSummary)
final myRatingSummaryProvider = MyRatingSummaryFamily._();

final class MyRatingSummaryProvider
    extends
        $FunctionalProvider<
          AsyncValue<RatingSummary>,
          RatingSummary,
          FutureOr<RatingSummary>
        >
    with $FutureModifier<RatingSummary>, $FutureProvider<RatingSummary> {
  MyRatingSummaryProvider._({
    required MyRatingSummaryFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'myRatingSummaryProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$myRatingSummaryHash();

  @override
  String toString() {
    return r'myRatingSummaryProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $FutureProviderElement<RatingSummary> $createElement(
    $ProviderPointer pointer,
  ) => $FutureProviderElement(pointer);

  @override
  FutureOr<RatingSummary> create(Ref ref) {
    final argument = this.argument as String;
    return myRatingSummary(ref, argument);
  }

  @override
  bool operator ==(Object other) {
    return other is MyRatingSummaryProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$myRatingSummaryHash() => r'22087b27278b1474897ae1af2ab2c66070ba1647';

final class MyRatingSummaryFamily extends $Family
    with $FunctionalFamilyOverride<FutureOr<RatingSummary>, String> {
  MyRatingSummaryFamily._()
    : super(
        retry: null,
        name: r'myRatingSummaryProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MyRatingSummaryProvider call(String delivererId) =>
      MyRatingSummaryProvider._(argument: delivererId, from: this);

  @override
  String toString() => r'myRatingSummaryProvider';
}
