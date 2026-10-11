import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/features/deliveries/presentation/widgets/delivery_card.dart';
import 'package:lilia_food_delivery/models/app_user.dart';
import 'package:lilia_food_delivery/models/delivery.dart';

/// D-PAY (DEL-002) — le livreur ne voit ni sa rémunération, ni un montant de
/// commande, et ne voit que son TYPE de profil.
///
/// Le serveur ne renvoie plus ces champs ; la carte est testée avec un
/// payload qui les porte TOUS (serveur ancien, régression backend) : l'app ne
/// doit pas les afficher pour autant.
void main() {
  final leakyPayload = <String, dynamic>{
    'id': 'd1',
    'orderId': 'o1',
    'status': 'ASSIGNER',
    'driverEconomicsFrozenAt': '2026-10-08T10:00:00Z',
    'driverPayXaf': 650,
    'driverSharePercent': 65,
    'driverCompensationModel': 'PER_DELIVERY',
    'order': {
      'id': 'o1',
      'total': 6750,
      'subTotal': 5000,
      'deliveryFee': 1000,
      'deliveryAddress': 'Moungali, rue 12',
      'user': {'nom': 'Client', 'phone': '+242061111111'},
      'restaurant': {'id': 'r1', 'nom': 'Resto', 'vendorType': 'RESTAURANT'},
      'items': [
        {
          'id': 'i1',
          'quantite': 2,
          'prix': 2500,
          'product': {'nom': 'Poulet DG'},
        },
      ],
    },
  };

  testWidgets('la carte de mission n’affiche aucun montant', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DeliveryCard(
            delivery: Delivery.fromJson(leakyPayload),
            onAccept: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('XAF'), findsNothing);
    expect(find.textContaining('650'), findsNothing);
    expect(find.textContaining('6750'), findsNothing);
    expect(find.textContaining('Vous'), findsNothing);
    // La carte reste utile : le point de retrait et les articles y sont.
    expect(find.textContaining('Resto'), findsWidgets);
    expect(find.textContaining('article'), findsOneWidget);
  });

  group('type de profil — seule donnée économique visible', () {
    Map<String, dynamic> me(Object? employmentType) => {
      'id': 'u1',
      'role': 'LIVREUR',
      'driverProfile': {
        'vehicleType': 'MOTO',
        'isActive': true,
        'employmentType': ?employmentType,
      },
    };

    test('LILIA → « Livreur Lilia »', () {
      final p = AppUser.fromJson(me('LILIA')).driverProfile!;
      expect(p.employmentType?.label, 'Livreur Lilia');
    });

    test('INDEPENDENT → « Livreur indépendant »', () {
      final p = AppUser.fromJson(me('INDEPENDENT')).driverProfile!;
      expect(p.employmentType?.label, 'Livreur indépendant');
    });

    test('absent ou inconnu → rien (pas de type deviné)', () {
      expect(AppUser.fromJson(me(null)).driverProfile!.employmentType, isNull);
      expect(
        AppUser.fromJson(me('FREELANCE')).driverProfile!.employmentType,
        isNull,
      );
    });
  });
}
