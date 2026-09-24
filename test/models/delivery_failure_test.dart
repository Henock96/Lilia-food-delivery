import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/models/delivery_failure.dart';

/// Échec de livraison (F3-05), côté livreur.
void main() {
  test('les motifs parlent le vocabulaire du serveur', () {
    expect(DeliveryFailureReason.values.map((r) => r.wire), [
      'CUSTOMER_UNREACHABLE',
      'ADDRESS_NOT_FOUND',
      'CUSTOMER_REFUSED',
      'ACCIDENT',
      'LOST_OR_DAMAGED',
      'OTHER',
    ]);
  });

  test('protocole lu tel que le serveur le tient', () {
    final p = UnreachableProtocol.fromJson({
      'callAttempts': 1,
      'smsSent': true,
      'waitRemainingSeconds': 320,
    });
    expect(p.callAttempts, 1);
    expect(p.smsSent, isTrue);
    expect(p.canDeclare, isFalse);
  });

  test('déclarer : attente écoulée ET deux appels', () {
    const waiting = UnreachableProtocol(
      callAttempts: 3,
      smsSent: true,
      waitRemainingSeconds: 1,
    );
    expect(waiting.canDeclare, isFalse);
    expect(waiting.tick().canDeclare, isTrue);

    const oneCall = UnreachableProtocol(
      callAttempts: 1,
      smsSent: true,
      waitRemainingSeconds: 0,
    );
    expect(oneCall.canDeclare, isFalse);
  });

  test('le minuteur ne descend pas sous zéro', () {
    const done = UnreachableProtocol(
      callAttempts: 2,
      smsSent: false,
      waitRemainingSeconds: 0,
    );
    expect(done.tick().waitRemainingSeconds, 0);
  });
}
