import 'package:lilia_food_delivery/core/network/api_exception.dart';

/// Que faire d'un envoi de positions qui a échoué (F3-12.1, gate R8).
///
/// Avant : tout échec gardait le lot, qui était rejoué à chaque retour réseau
/// et à chaque reprise de l'app. Un refus PERMANENT du serveur (contrat
/// invalide, course réassignée, commande inconnue) tournait donc en boucle,
/// et bloquait derrière lui toutes les positions suivantes.
enum BatchFailureAction {
  /// Panne passagère (réseau, délai, 5xx, 408, 429, 401 après rafraîchissement
  /// du jeton) : le lot reste en file, nouvel essai au prochain déclencheur.
  retryLater,

  /// Refus définitif (autre 4xx) : le lot ne passera jamais, il est abandonné.
  drop,
}

/// Classe une erreur d'envoi. Une erreur qui n'est pas une [ApiException]
/// (bogue local, sérialisation) est gardée : la file est bornée, et perdre
/// des points pour une cause qu'on ne comprend pas serait pire.
BatchFailureAction classifyTrackingError(Object error) {
  if (error is! ApiException) return BatchFailureAction.retryLater;
  switch (error.kind) {
    case ApiErrorKind.network:
    case ApiErrorKind.timeout:
    case ApiErrorKind.server:
      return BatchFailureAction.retryLater;
    case ApiErrorKind.unauthorized:
    case ApiErrorKind.client:
    case ApiErrorKind.unknown:
      break;
  }
  final status = error.statusCode;
  if (status == null) return BatchFailureAction.retryLater;
  // 401 : l'intercepteur a déjà rafraîchi le jeton et rejoué une fois. Ce qui
  // remonte encore est une session en cours de réparation, pas un refus du lot.
  if (status == 401 || status == 408 || status == 429 || status >= 500) {
    return BatchFailureAction.retryLater;
  }
  return BatchFailureAction.drop;
}

/// Une position dont le `PATCH` direct a échoué mérite-t-elle la file ?
///
/// Seulement si l'échec est passager. Un 4xx (course hors `EN_TRANSIT`,
/// livreur réassigné) entrait aussi dans la file, d'où il ne pouvait
/// ressortir que par un autre 4xx.
bool shouldQueueFailedPosition(Object error) =>
    classifyTrackingError(error) == BatchFailureAction.retryLater;
