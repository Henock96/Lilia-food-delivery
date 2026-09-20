import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/services/notification_router.dart';

void main() {
  const router = NotificationRouter();

  NotificationAction onTap(Map<String, dynamic> data) =>
      router.resolve(data, trigger: NotificationTrigger.tap);

  NotificationAction inForeground(Map<String, dynamic> data) =>
      router.resolve(data, trigger: NotificationTrigger.foreground);

  group('nouveaux types du cycle de vie', () {
    // Le livreur ne recevait que `delivery_assigned` : ni « commande prête »,
    // ni « mission retirée », ni « commande annulée » ne lui parvenaient
    // (backend : DeliveriesListener).
    test('delivery_ready rafraîchit et ouvre la mission au tap', () {
      final action = onTap({'type': 'delivery_ready', 'deliveryId': 'd-1'});

      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, '/deliveries/d-1');
    });

    test('delivery_failed rafraîchit et reste ouvrable', () {
      final action = onTap({'type': 'delivery_failed', 'deliveryId': 'd-1'});

      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, '/deliveries/d-1');
    });

    test('delivery_unassigned rafraîchit mais n’ouvre rien', () {
      final action = onTap({'type': 'delivery_unassigned', 'deliveryId': 'd-1'});

      // La course n'est plus la sienne : ouvrir son détail n'aurait pas de sens.
      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, isNull);
    });

    test('delivery_cancelled rafraîchit mais n’ouvre rien', () {
      final action = onTap({'type': 'delivery_cancelled', 'deliveryId': 'd-1'});

      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, isNull);
    });

    test('un type de retrait sans deliveryId reste inoffensif', () {
      final action = onTap({'type': 'delivery_cancelled'});

      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, isNull);
    });
  });

  group('nouvelle mission', () {
    // Le backend envoie `delivery_assigned` (delivery-assignment.service.ts),
    // pas `new_mission` : l'ancienne branche ne matchait jamais et seul le
    // repli sur `deliveryId` sauvait le rafraîchissement.
    test('le type delivery_assigned rafraîchit les missions', () {
      final action = inForeground({
        'type': 'delivery_assigned',
        'deliveryId': 'd-1',
        'orderId': 'o-1',
      });

      expect(action.refresh, NotificationTarget.missions);
    });

    test('un tap ouvre le détail de la mission', () {
      final action = onTap({
        'type': 'delivery_assigned',
        'deliveryId': 'd-1',
        'orderId': 'o-1',
      });

      expect(action.route, '/deliveries/d-1');
    });

    test('en foreground, rafraîchit sans déplacer le livreur', () {
      final action = inForeground({
        'type': 'delivery_assigned',
        'deliveryId': 'd-1',
      });

      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, isNull);
    });

    test('un deliveryId suffit même si le type change côté backend', () {
      final action = inForeground({'type': 'autre_chose', 'deliveryId': 'd-1'});

      expect(action.refresh, NotificationTarget.missions);
    });

    test('sans deliveryId, rafraîchit mais n\'ouvre aucun écran', () {
      final action = onTap({'type': 'delivery_assigned'});

      expect(action.refresh, NotificationTarget.missions);
      expect(action.route, isNull);
    });
  });

  group('messages non reconnus', () {
    test('un payload vide ne déclenche rien', () {
      expect(inForeground({}), NotificationAction.none);
    });

    test('un type inconnu sans deliveryId ne déclenche rien', () {
      expect(onTap({'type': 'promo'}), NotificationAction.none);
    });
  });
}
