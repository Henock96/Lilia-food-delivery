// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'auth_repository.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(authRepository)
final authRepositoryProvider = AuthRepositoryProvider._();

final class AuthRepositoryProvider
    extends $FunctionalProvider<AuthRepository, AuthRepository, AuthRepository>
    with $Provider<AuthRepository> {
  AuthRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authRepositoryHash();

  @$internal
  @override
  $ProviderElement<AuthRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AuthRepository create(Ref ref) {
    return authRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AuthRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AuthRepository>(value),
    );
  }
}

String _$authRepositoryHash() => r'2819231fb4b84b382969f822ad54d153b3aa8429';

@ProviderFor(authStateChange)
final authStateChangeProvider = AuthStateChangeProvider._();

final class AuthStateChangeProvider
    extends $FunctionalProvider<AsyncValue<User?>, User?, Stream<User?>>
    with $FutureModifier<User?>, $StreamProvider<User?> {
  AuthStateChangeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'authStateChangeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$authStateChangeHash();

  @$internal
  @override
  $StreamProviderElement<User?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<User?> create(Ref ref) {
    return authStateChange(ref);
  }
}

String _$authStateChangeHash() => r'226bc77a3d2a69815a3618d9841da696a41d6adc';

/// Jeton d'identité courant, réémis à chaque renouvellement Firebase.

@ProviderFor(firebaseIdToken)
final firebaseIdTokenProvider = FirebaseIdTokenProvider._();

/// Jeton d'identité courant, réémis à chaque renouvellement Firebase.

final class FirebaseIdTokenProvider
    extends $FunctionalProvider<AsyncValue<String?>, String?, Stream<String?>>
    with $FutureModifier<String?>, $StreamProvider<String?> {
  /// Jeton d'identité courant, réémis à chaque renouvellement Firebase.
  FirebaseIdTokenProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'firebaseIdTokenProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$firebaseIdTokenHash();

  @$internal
  @override
  $StreamProviderElement<String?> $createElement($ProviderPointer pointer) =>
      $StreamProviderElement(pointer);

  @override
  Stream<String?> create(Ref ref) {
    return firebaseIdToken(ref);
  }
}

String _$firebaseIdTokenHash() => r'8b1dc460d841d7f8d534850716aa5964c6de1b9b';
