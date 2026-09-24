import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/network_observer.dart';
import '../data/auth_repository.dart';
import 'auth_controller.dart';

part 'session_guard.g.dart';

/// Le serveur refuse-t-il la session elle-même ?
///
///  - 401 : jeton refusé ;
///  - 403 `ACCOUNT_NOT_SYNCED` : aucun compte Lilia pour ce jeton — compte
///    livreur supprimé pendant que le téléphone gardait sa session (les
///    comptes livreur sont créés par l'admin, jamais par cette app) ;
///  - 403 `ACCOUNT_REVOKED` : compte suspendu ou supprimé.
///
/// Le texte ne sert qu'aux serveurs antérieurs au code.
bool refusesSession(ApiException e) {
  if (e.kind == ApiErrorKind.unauthorized) return true;
  if (e.statusCode != 403) return false;
  return e.code == 'ACCOUNT_NOT_SYNCED' ||
      e.code == 'ACCOUNT_REVOKED' ||
      e.message.startsWith('Compte non synchronisé');
}

const kSessionEndedMessage =
    'Ce compte n’est plus disponible. Connectez-vous avec un autre compte.';

/// Message montré sur l'écran de connexion après une déconnexion forcée.
@Riverpod(keepAlive: true)
class SessionEndedNotice extends _$SessionEndedNotice {
  @override
  String? build() => null;

  void show(String message) => state = message;
  void clear() => state = null;
}

/// Déconnecte une session que le serveur n'accepte plus.
///
/// Sans elle, un compte supprimé côté Lilia laissait le téléphone connecté
/// face à « Compte non synchronisé » sur chaque écran, sans jamais revenir à
/// la connexion (bug du 24/09/2026).
@Riverpod(keepAlive: true)
class SessionGuard extends _$SessionGuard {
  /// Absorbe les déconnexions concurrentes (plusieurs requêtes échouent
  /// ensemble) et le 401 éventuel du `DELETE /notifications/token` de la
  /// déconnexion elle-même.
  bool _enCours = false;

  @override
  void build() {}

  Future<void> handle(Object error) async {
    if (error is! ApiException || _enCours || !refusesSession(error)) return;
    if (ref.read(authRepositoryProvider).currentUser == null) return;

    _enCours = true;
    try {
      ref.read(sessionEndedNoticeProvider.notifier).show(kSessionEndedMessage);
      await ref.read(authControllerProvider.notifier).signOut();
    } finally {
      _enCours = false;
    }
  }
}

/// Relie toutes les erreurs d'API à la garde de session.
class SessionAwareNetworkObserver implements NetworkObserver {
  const SessionAwareNetworkObserver(this._delegate, this._guard);

  final NetworkObserver _delegate;
  final SessionGuard _guard;

  @override
  void onRequest(RequestSnapshot r) => _delegate.onRequest(r);

  @override
  void onError(ApiException e, RequestSnapshot r) {
    _delegate.onError(e, r);
    // Non attendu : l'erreur d'origine remonte à l'appelant sans délai.
    _guard.handle(e).catchError((Object _) {});
  }
}
