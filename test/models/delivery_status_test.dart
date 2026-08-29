import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/models/delivery.dart';

/// Le cycle de vie d'une course, côté livreur.
///
/// Ces tests protègent la règle centrale du flux : **accepter une mission
/// n'est pas être en route vers le client**. `ACCEPTER` et `EN_TRANSIT` sont
/// deux états distincts, et les confondre — comme le faisait le backend avant
/// le 29/08 — fait annoncer au client une commande qui est encore au comptoir.
void main() {
  group('parsing', () {
    test('reconnaît tous les statuts émis par le backend', () {
      expect(DeliveryStatusX.fromString('ASSIGNER'), DeliveryStatus.assigner);
      expect(DeliveryStatusX.fromString('ACCEPTER'), DeliveryStatus.accepter);
      expect(DeliveryStatusX.fromString('EN_TRANSIT'), DeliveryStatus.en_transit);
      expect(DeliveryStatusX.fromString('LIVRER'), DeliveryStatus.livrer);
      expect(DeliveryStatusX.fromString('ECHEC'), DeliveryStatus.echec);
      expect(DeliveryStatusX.fromString('EN_ATTENTE'), DeliveryStatus.en_attente);
    });

    test('un statut inconnu retombe sur en_attente plutôt que de planter', () {
      // Si le backend introduit un état, l'app doit rester utilisable.
      expect(
        DeliveryStatusX.fromString('UN_ETAT_FUTUR'),
        DeliveryStatus.en_attente,
      );
    });

    test('l’aller-retour parsing → API est stable', () {
      for (final status in DeliveryStatus.values) {
        expect(
          DeliveryStatusX.fromString(status.toApiString()),
          status,
          reason: status.name,
        );
      }
    });
  });

  group('missions actives', () {
    test('assigner, accepter et en_transit occupent le livreur', () {
      // `accepter` DOIT en faire partie : sans lui, la mission disparaîtrait
      // de l'écran entre l'acceptation et l'arrivée au restaurant.
      expect(DeliveryStatus.assigner.isActive, isTrue);
      expect(DeliveryStatus.accepter.isActive, isTrue);
      expect(DeliveryStatus.en_transit.isActive, isTrue);
    });

    test('les états terminaux ne sont pas actifs', () {
      expect(DeliveryStatus.livrer.isActive, isFalse);
      expect(DeliveryStatus.echec.isActive, isFalse);
      expect(DeliveryStatus.en_attente.isActive, isFalse);
    });
  });

  group('libellés', () {
    test('accepter et en_transit ne disent PAS la même chose au livreur', () {
      // C'est ce que l'audit relevait côté UX : après « Accepter », l'écran
      // affichait « Livraison en cours » alors que le livreur n'avait pas
      // encore le repas.
      expect(DeliveryStatus.accepter.label, isNot(DeliveryStatus.en_transit.label));
      expect(DeliveryStatus.accepter.label, 'À récupérer');
      expect(DeliveryStatus.en_transit.label, 'En livraison');
    });

    test('chaque statut a un libellé non vide', () {
      for (final status in DeliveryStatus.values) {
        expect(status.label, isNotEmpty, reason: status.name);
      }
    });
  });

  group('désérialisation d’une livraison', () {
    test('lit les trois horodatages du cycle', () {
      final delivery = Delivery.fromJson({
        'id': 'd1',
        'orderId': 'o1',
        'status': 'EN_TRANSIT',
        'createdAt': '2026-08-29T10:00:00.000Z',
        'acceptedAt': '2026-08-29T10:05:00.000Z',
        'pickedUpAt': '2026-08-29T10:20:00.000Z',
      });

      expect(delivery.status, DeliveryStatus.en_transit);
      expect(delivery.acceptedAt, isNotNull);
      expect(delivery.pickedUpAt, isNotNull);
      // L'acceptation précède la récupération : c'est toute la distinction.
      expect(delivery.acceptedAt!.isBefore(delivery.pickedUpAt!), isTrue);
    });

    test('une mission acceptée n’a pas encore de pickedUpAt', () {
      final delivery = Delivery.fromJson({
        'id': 'd1',
        'orderId': 'o1',
        'status': 'ACCEPTER',
        'createdAt': '2026-08-29T10:00:00.000Z',
        'acceptedAt': '2026-08-29T10:05:00.000Z',
      });

      expect(delivery.status, DeliveryStatus.accepter);
      expect(delivery.acceptedAt, isNotNull);
      // Le champ était renseigné dès l'acceptation : donnée fausse en base.
      expect(delivery.pickedUpAt, isNull);
    });

    test('un payload minimal ne fait pas planter le parsing', () {
      final delivery = Delivery.fromJson({'id': 'd1', 'orderId': 'o1'});
      expect(delivery.status, DeliveryStatus.en_attente);
      expect(delivery.acceptedAt, isNull);
    });
  });
}
