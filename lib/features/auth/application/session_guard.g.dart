// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_guard.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Message montré sur l'écran de connexion après une déconnexion forcée.

@ProviderFor(SessionEndedNotice)
final sessionEndedNoticeProvider = SessionEndedNoticeProvider._();

/// Message montré sur l'écran de connexion après une déconnexion forcée.
final class SessionEndedNoticeProvider
    extends $NotifierProvider<SessionEndedNotice, String?> {
  /// Message montré sur l'écran de connexion après une déconnexion forcée.
  SessionEndedNoticeProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionEndedNoticeProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionEndedNoticeHash();

  @$internal
  @override
  SessionEndedNotice create() => SessionEndedNotice();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(String? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<String?>(value),
    );
  }
}

String _$sessionEndedNoticeHash() =>
    r'34d2fbfebcc37c07fd67611207ee793d3b008665';

/// Message montré sur l'écran de connexion après une déconnexion forcée.

abstract class _$SessionEndedNotice extends $Notifier<String?> {
  String? build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<String?, String?>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<String?, String?>,
              String?,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

/// Déconnecte une session que le serveur n'accepte plus.
///
/// Sans elle, un compte supprimé côté Lilia laissait le téléphone connecté
/// face à « Compte non synchronisé » sur chaque écran, sans jamais revenir à
/// la connexion (bug du 24/09/2026).

@ProviderFor(SessionGuard)
final sessionGuardProvider = SessionGuardProvider._();

/// Déconnecte une session que le serveur n'accepte plus.
///
/// Sans elle, un compte supprimé côté Lilia laissait le téléphone connecté
/// face à « Compte non synchronisé » sur chaque écran, sans jamais revenir à
/// la connexion (bug du 24/09/2026).
final class SessionGuardProvider extends $NotifierProvider<SessionGuard, void> {
  /// Déconnecte une session que le serveur n'accepte plus.
  ///
  /// Sans elle, un compte supprimé côté Lilia laissait le téléphone connecté
  /// face à « Compte non synchronisé » sur chaque écran, sans jamais revenir à
  /// la connexion (bug du 24/09/2026).
  SessionGuardProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'sessionGuardProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$sessionGuardHash();

  @$internal
  @override
  SessionGuard create() => SessionGuard();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$sessionGuardHash() => r'79aad494413d3858559e2f8ac18fb4493702dc6a';

/// Déconnecte une session que le serveur n'accepte plus.
///
/// Sans elle, un compte supprimé côté Lilia laissait le téléphone connecté
/// face à « Compte non synchronisé » sur chaque écran, sans jamais revenir à
/// la connexion (bug du 24/09/2026).

abstract class _$SessionGuard extends $Notifier<void> {
  void build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<void, void>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<void, void>,
              void,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
