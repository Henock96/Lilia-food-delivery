import 'package:flutter/foundation.dart';

import '../core/network/api_client.dart';

/// Cycle de vie du token FCM d'une session livreur.
///
/// Isolé de [DeliveryNotificationService] parce que ce dernier touche
/// `FirebaseMessaging.instance` dès sa construction et n'est donc pas
/// instanciable en test unitaire. Ici il n'y a que de l'HTTP : le contrat
/// avec le backend et la garde de session sont vérifiables directement.
///
/// La garde de session est la partie subtile : elle empêche une double
/// initialisation, mais [remove] doit la **réarmer**, sinon une reconnexion
/// dans la même session d'app ne réenregistre jamais de token et le livreur
/// cesse silencieusement de recevoir ses missions.
class FcmTokenRegistrar {
  FcmTokenRegistrar(this._api, {Duration Function(int attempt)? backoff})
      : _backoff = backoff ?? _defaultBackoff;

  final ApiClient _api;

  /// Attente entre deux tentatives d'enregistrement. Injectable pour que les
  /// tests n'attendent pas les paliers de production.
  final Duration Function(int attempt) _backoff;

  static Duration _defaultBackoff(int attempt) =>
      Duration(seconds: attempt * 15);

  String? _token;
  bool _sessionOpen = false;

  /// Token actuellement enregistré côté serveur, `null` si aucun.
  String? get token => _token;

  /// Ouvre une session d'enregistrement. Renvoie `false` si une session est
  /// déjà ouverte — l'appelant doit alors sauter son initialisation.
  bool beginSession() {
    if (_sessionOpen) return false;
    _sessionOpen = true;
    return true;
  }

  /// Enregistre [token] auprès du backend, avec [maxRetries] tentatives.
  /// N'échoue jamais bruyamment : une notification perdue ne doit pas casser
  /// le flux de connexion. Le token n'est mémorisé qu'en cas de succès, pour
  /// ne pas tenter plus tard de supprimer un token que le serveur ignore.
  Future<void> register(String token, {int maxRetries = 3}) async {
    for (var attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        await _api.postJson(
          '/notifications/register-token',
          body: {'token': token},
        );
        _token = token;
        return;
      } catch (e) {
        debugPrint(
          'Erreur enregistrement FCM token (tentative $attempt/$maxRetries): $e',
        );
        if (attempt == maxRetries) return;
        await Future<void>.delayed(_backoff(attempt));
      }
    }
  }

  /// Supprime le token côté serveur et referme la session.
  ///
  /// L'état local est purgé même si l'appel échoue (typiquement un token
  /// Firebase déjà expiré au moment du logout) : garder un token mort
  /// empêcherait le prochain enregistrement.
  Future<void> remove() async {
    final current = _token;
    if (current == null) {
      _sessionOpen = false;
      return;
    }
    try {
      await _api.deleteJson('/notifications/token', body: {'token': current});
    } catch (e) {
      debugPrint('Erreur suppression FCM token: $e');
    } finally {
      _token = null;
      _sessionOpen = false;
    }
  }
}
