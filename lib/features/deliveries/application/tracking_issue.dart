import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'location_service.dart';

part 'tracking_issue.g.dart';

/// Le partage de position est interrompu alors qu'une course est en cours.
///
/// Cet état existe parce que la panne est **silencieuse par nature**. Quand
/// `TrackingResumeService` tente de reprendre le suivi au retour en avant-plan
/// et que la localisation est refusée, il n'a ni écran ni `BuildContext` : le
/// refus n'allait que dans les logs. Le livreur reprenait sa course en croyant
/// être suivi, et le client regardait un marqueur figé jusqu'à la sonnette.
///
/// Aucun des deux ne pouvait s'en apercevoir. D'où un état observable, que
/// l'interface affiche partout où le livreur se trouve.
class TrackingIssue {
  const TrackingIssue({required this.permission, this.deliveryId});

  /// Le motif exact du refus — il commande l'action proposée : rallumer la
  /// localisation, réautoriser dans l'application, ou passer par les réglages
  /// système.
  final LocationPermissionResult permission;

  /// La course concernée, quand on la connaît. Sert à relancer le suivi sur la
  /// bonne mission une fois le problème réglé.
  final String? deliveryId;

  String get message => permission.message;
  LocationDenialReason? get reason => permission.reason;
}

/// Interruption en cours, ou `null` si tout va bien.
///
/// `keepAlive` : l'interruption ne doit pas disparaître parce que le livreur a
/// changé d'onglet. Elle survit tant que la cause n'est pas levée.
@Riverpod(keepAlive: true)
class TrackingIssueController extends _$TrackingIssueController {
  @override
  TrackingIssue? build() => null;

  /// Signale que le suivi n'a pas pu démarrer ou reprendre.
  void report(LocationPermissionResult permission, {String? deliveryId}) {
    if (permission.granted) {
      clear();
      return;
    }
    state = TrackingIssue(permission: permission, deliveryId: deliveryId);
  }

  /// Le suivi fonctionne à nouveau : le bandeau doit disparaître de lui-même,
  /// sans que le livreur ait à le fermer. Un bandeau qu'on ferme à la main
  /// finit fermé alors que le problème dure.
  void clear() => state = null;
}
