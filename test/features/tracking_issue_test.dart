import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/features/deliveries/application/location_service.dart';
import 'package:lilia_food_delivery/features/deliveries/application/tracking_issue.dart';

/// Le partage de position est interrompu — et il faut que ça se voie.
///
/// La panne d'origine était invisible des deux côtés : le livreur reprenait sa
/// course en croyant être suivi, le client regardait un marqueur figé. Ni l'un
/// ni l'autre ne disposait du moindre signal.
///
/// Cet état est le support de l'alerte. Ce qui compte ici n'est pas qu'il
/// stocke une valeur, mais **quand il se lève et quand il retombe** : une
/// alerte qui disparaît trop tôt rétablit exactement le silence qu'on cherchait
/// à rompre.
void main() {
  late ProviderContainer container;

  setUp(() => container = ProviderContainer());
  tearDown(() => container.dispose());

  TrackingIssueController notifier() =>
      container.read(trackingIssueControllerProvider.notifier);

  TrackingIssue? current() => container.read(trackingIssueControllerProvider);

  const granted = LocationPermissionResult(granted: true);
  const disabled = LocationPermissionResult(
    granted: false,
    reason: LocationDenialReason.serviceDisabled,
  );
  const deniedForever = LocationPermissionResult(
    granted: false,
    reason: LocationDenialReason.deniedForever,
  );

  test('aucune alerte au démarrage', () {
    expect(current(), isNull);
  });

  test('un refus lève l’alerte, avec la course concernée', () {
    // Le `deliveryId` sert à relancer le suivi sur la bonne mission une fois le
    // problème réglé.
    notifier().report(disabled, deliveryId: 'deliv-1');

    expect(current(), isNotNull);
    expect(current()!.reason, LocationDenialReason.serviceDisabled);
    expect(current()!.deliveryId, 'deliv-1');
  });

  test('une permission accordée ne lève aucune alerte', () {
    // `report` est appelé sur le chemin nominal comme sur le chemin d'échec :
    // il doit savoir distinguer les deux plutôt que d'obliger l'appelant à le
    // faire — c'est justement l'oubli qui produit ce genre de bug.
    notifier().report(granted, deliveryId: 'deliv-1');

    expect(current(), isNull);
  });

  test('un succès après un refus efface l’alerte', () {
    // Le bandeau doit disparaître seul quand le suivi repart. Il n'a
    // volontairement pas de bouton de fermeture : un bandeau qu'on peut écarter
    // finit écarté alors que la panne dure.
    notifier().report(disabled, deliveryId: 'deliv-1');
    expect(current(), isNotNull);

    notifier().report(granted, deliveryId: 'deliv-1');
    expect(current(), isNull);
  });

  test('un second refus met le motif à jour', () {
    // Un refus ponctuel devient définitif au second rejet, et l'action à
    // proposer change avec lui : redemander sur place, ou ouvrir les réglages.
    notifier().report(
      const LocationPermissionResult(
        granted: false,
        reason: LocationDenialReason.denied,
      ),
    );
    expect(current()!.reason, LocationDenialReason.denied);

    notifier().report(deniedForever);
    expect(current()!.reason, LocationDenialReason.deniedForever);
  });

  test('la fin de course efface l’alerte', () {
    notifier().report(disabled, deliveryId: 'deliv-1');

    notifier().clear();

    expect(current(), isNull);
  });

  test('le message porté est celui, lisible, du motif', () {
    // Le bandeau affiche ce texte tel quel : il doit parler au livreur, pas
    // décrire un état d'API.
    notifier().report(deniedForever);

    expect(current()!.message, contains('réglages'));
    expect(current()!.message, isNot(contains('deniedForever')));
  });
}
