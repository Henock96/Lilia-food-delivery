import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/models/order.dart';

/// Position du point de retrait.
///
/// Le livreur fait deux trajets par course — vers le comptoir, puis vers la
/// porte du client. Seul le second portait des coordonnées ; le premier
/// n'était guidable par rien, et le livreur retapait l'adresse du vendeur à la
/// main dans Google Maps.
void main() {
  group('DeliveryRestaurant — position du point de retrait', () {
    test('lit les coordonnées servies par le backend', () {
      final vendor = DeliveryRestaurant.fromJson({
        'id': 'rest_1',
        'nom': 'Chez Mado',
        'adresse': 'Avenue de la Paix, Moungali',
        'phone': '+242065000000',
        'vendorType': 'RESTAURANT',
        'latitude': -4.2634,
        'longitude': 15.2429,
      });

      expect(vendor.latitude, -4.2634);
      expect(vendor.longitude, 15.2429);
      expect(vendor.hasPosition, isTrue);
    });

    test('un vendeur sans position reste exploitable par son adresse', () {
      // Les vendeurs enregistrés avant l'onboarding géolocalisé n'ont pas de
      // coordonnées. La course doit rester praticable : c'est le texte qui
      // sert alors de cible au guidage.
      final vendor = DeliveryRestaurant.fromJson({
        'nom': 'Boulangerie du Rond-Point',
        'adresse': 'Rond-point Moungali, Brazzaville',
      });

      expect(vendor.hasPosition, isFalse);
      expect(vendor.adresse, isNotNull);
    });

    test('une coordonnée seule ne fait pas une position', () {
      // Une latitude sans longitude ne situe rien. Poser un marqueur dessus
      // reviendrait à inventer un point.
      final vendor = DeliveryRestaurant.fromJson({
        'nom': 'Chez Mado',
        'latitude': -4.2634,
      });

      expect(vendor.hasPosition, isFalse);
    });

    test('ignore des coordonnées non numériques au lieu de casser', () {
      final vendor = DeliveryRestaurant.fromJson({
        'nom': 'Chez Mado',
        'latitude': 'nord',
        'longitude': <String, dynamic>{},
      });

      expect(vendor.latitude, isNull);
      expect(vendor.hasPosition, isFalse);
    });
  });
}
