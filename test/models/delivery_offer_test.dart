import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/models/delivery_offer.dart';
import 'package:lilia_food_delivery/models/vendor_type.dart';

/// Réponse de `GET /deliveries/available` telle que le backend la projette
/// (`delivery-offer-projection.ts`). Les champs absents le sont exprès.
Map<String, dynamic> _payload({
  List<Map<String, dynamic>>? data,
  String? reason,
  bool enabled = true,
}) => {
  'data': data ?? const [],
  'count': data?.length ?? 0,
  'meta': {
    'page': 1,
    'limit': 20,
    'total': data?.length ?? 0,
    'hasMore': false,
    'dispatchEnabled': enabled,
    'driver': {
      'eligible': reason == null,
      'reason': reason,
      'driverStatus': 'AVAILABLE',
    },
  },
};

const _offer = {
  'deliveryId': 'd-1',
  'orderRef': '#ABC123',
  'restaurant': {
    'nom': 'Chez Awa',
    'vendorType': 'HOME_COOK',
    'quartier': 'Poto-Poto',
  },
  'deliveryQuartier': 'Moungali',
  'itemCount': 3,
  'isPreorder': false,
  'scheduledFor': null,
  'readySince': '2026-11-10T12:00:00.000Z',
  'searchingSince': '2026-11-10T12:00:00.000Z',
  'round': 2,
};

void main() {
  group('DeliveryOffer', () {
    test('lit la projection d’offre', () {
      final o = DeliveryOffer.fromJson(_offer);
      expect(o.deliveryId, 'd-1');
      expect(o.orderRef, '#ABC123');
      expect(o.restaurantName, 'Chez Awa');
      expect(o.vendorType, VendorType.HOME_COOK);
      expect(o.restaurantQuartier, 'Poto-Poto');
      expect(o.deliveryQuartier, 'Moungali');
      expect(o.itemCount, 3);
      expect(o.isPreorder, isFalse);
      expect(o.readySince, DateTime.utc(2026, 11, 10, 12).toLocal());
      expect(o.round, 2);
    });

    test('champs facultatifs absents : valeurs sûres', () {
      final o = DeliveryOffer.fromJson({'deliveryId': 'd-2'});
      expect(o.restaurantName, 'Point de retrait');
      expect(o.vendorType, VendorType.RESTAURANT);
      expect(o.itemCount, 0);
      expect(o.round, 0);
      expect(o.readySince, isNull);
    });
  });

  group('AvailableDeliveries', () {
    test('liste et éligibilité', () {
      final a = AvailableDeliveries.fromJson(_payload(data: [_offer]));
      expect(a.offers, hasLength(1));
      expect(a.eligible, isTrue);
      expect(a.dispatchEnabled, isTrue);
    });

    test('raison serveur connue → message affichable', () {
      final a = AvailableDeliveries.fromJson(_payload(reason: 'OFFLINE'));
      expect(a.eligible, isFalse);
      expect(a.ineligibility, OfferIneligibility.offline);
      expect(a.ineligibility!.message, contains('Disponible'));
    });

    test('raison serveur inconnue : affichée brute, jamais ignorée', () {
      final a = AvailableDeliveries.fromJson(_payload(reason: 'FUTURE_RULE'));
      expect(a.eligible, isFalse);
      expect(a.ineligibility, isNull);
      expect(a.ineligibilityRaw, 'FUTURE_RULE');
    });

    test('without retire une carte sans toucher au reste', () {
      final a = AvailableDeliveries.fromJson(
        _payload(
          data: [
            _offer,
            {..._offer, 'deliveryId': 'd-2'},
          ],
        ),
      );
      final b = a.without('d-1');
      expect(b.offers.map((o) => o.deliveryId), ['d-2']);
      expect(b.eligible, isTrue);
    });
  });
}
