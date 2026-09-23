import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/deliveries_controller.dart';
import 'package:lilia_food_delivery/features/deliveries/application/location_service.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:lilia_food_delivery/features/deliveries/presentation/widgets/handover_code_dialog.dart';
import 'package:lilia_food_delivery/models/delivery.dart';

/// Preuve de remise (Master Audit v1, F-06) côté livreur.
///
/// Deux propriétés : la boîte ne laisse partir qu'un code bien formé, et un
/// refus du serveur (code faux, trop d'essais) laisse la course OUVERTE —
/// suivi GPS compris. Avant, `markDelivered` coupait le suivi et l'écran se
/// refermait même quand le serveur refusait.
class _FakeRepository implements DeliveryRepository {
  _FakeRepository(this._onUpdate);

  final Future<Delivery> Function(String? code) _onUpdate;
  final sentCodes = <String?>[];

  static final _inTransit = Delivery.fromJson({
    'id': 'd1',
    'orderId': 'o1',
    'status': 'EN_TRANSIT',
  });

  @override
  Future<Delivery> updateStatus(
    String id,
    DeliveryStatus status, {
    String? handoverCode,
  }) {
    sentCodes.add(handoverCode);
    return _onUpdate(handoverCode);
  }

  @override
  Future<Delivery> getDelivery(String deliveryId) async => _inTransit;

  @override
  Future<List<Delivery>> getMyMissions() async => [_inTransit];

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non utilisé ici');
}

class _FakeLocationService implements LocationService {
  int stops = 0;

  @override
  void stopTracking() => stops++;

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non utilisé ici');
}

void main() {
  group('HandoverCodeDialog', () {
    /// Ouvre la boîte ; `results` reçoit la valeur rendue à la fermeture.
    Future<List<String?>> open(WidgetTester tester) async {
      final results = <String?>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  results.add(await showHandoverCodeDialog(context)),
              child: const Text('ouvrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('ouvrir'));
      await tester.pumpAndSettle();
      return results;
    }

    testWidgets(
      'le bouton reste désactivé tant que le code n’a pas 4 chiffres',
      (tester) async {
        final results = await open(tester);
        await tester.enterText(
          find.byKey(const Key('handover-code-field')),
          '482',
        );
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const Key('handover-code-submit')),
              )
              .onPressed,
          isNull,
        );

        await tester.enterText(
          find.byKey(const Key('handover-code-field')),
          '4821',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('handover-code-submit')));
        await tester.pumpAndSettle();
        expect(results, ['4821']);
      },
    );

    testWidgets('les lettres sont ignorées à la saisie', (tester) async {
      await open(tester);
      await tester.enterText(
        find.byKey(const Key('handover-code-field')),
        '4a8b',
      );
      await tester.pump();
      final field = tester.widget<TextField>(
        find.byKey(const Key('handover-code-field')),
      );
      expect(field.controller!.text, '48');
    });

    testWidgets('« Annuler » ne rend aucun code', (tester) async {
      final results = await open(tester);
      await tester.tap(find.text('Annuler'));
      await tester.pumpAndSettle();
      expect(results, [null]);
    });
  });

  group('DeliveryDetailController.markDelivered', () {
    late ProviderContainer container;
    late _FakeRepository repo;
    late _FakeLocationService location;

    void build(Future<Delivery> Function(String? code) onUpdate) {
      repo = _FakeRepository(onUpdate);
      location = _FakeLocationService();
      container = ProviderContainer(
        overrides: [
          deliveryRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(location),
        ],
      );
      addTearDown(container.dispose);
      container.listen(
        deliveryDetailControllerProvider('d1'),
        (_, _) {},
        fireImmediately: true,
      );
    }

    DeliveryDetailController notifier() =>
        container.read(deliveryDetailControllerProvider('d1').notifier);

    test('transmet le code au serveur et clôt le suivi sur succès', () async {
      build(
        (_) async => Delivery.fromJson({
          'id': 'd1',
          'orderId': 'o1',
          'status': 'LIVRER',
        }),
      );
      await container.read(deliveryDetailControllerProvider('d1').future);

      await notifier().markDelivered(handoverCode: '4821');

      expect(repo.sentCodes, ['4821']);
      expect(location.stops, 1);
    });

    test(
      'code refusé : l’erreur remonte, la course et le suivi restent ouverts',
      () async {
        build(
          (_) async => throw const ApiException(
            'Code de remise incorrect. 4 essais restants.',
            statusCode: 400,
            kind: ApiErrorKind.client,
          ),
        );
        await container.read(deliveryDetailControllerProvider('d1').future);

        await expectLater(
          notifier().markDelivered(handoverCode: '0000'),
          throwsA(
            isA<ApiException>().having(
              (e) => e.message,
              'message',
              contains('incorrect'),
            ),
          ),
        );
        expect(location.stops, 0, reason: 'le livreur roule toujours');
        final state = container.read(deliveryDetailControllerProvider('d1'));
        expect(state.value?.status, DeliveryStatus.en_transit);
      },
    );
  });
}
