// Ce que la carte de course affiche quand la position du livreur manque
// (audit du 18/11 : L-4, L-5, SEC-18).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/features/deliveries/application/driver_gps_watcher.dart';
import 'package:lilia_food_delivery/features/deliveries/presentation/widgets/gps_state_views.dart';

Widget _app(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(height: 320, child: child)),
);

void main() {
  for (final (state, label, action) in [
    (MapGpsState.serviceDisabled, 'Activer', MapGpsAction.openLocationSettings),
    (MapGpsState.denied, 'Autoriser', MapGpsAction.requestPermission),
    (MapGpsState.deniedForever, 'Réglages', MapGpsAction.openAppSettings),
    (MapGpsState.streamFailed, 'Réessayer', MapGpsAction.retry),
    (MapGpsState.weakSignal, 'Réessayer', MapGpsAction.retry),
  ]) {
    testWidgets('$state : message explicite et geste « $label »', (
      tester,
    ) async {
      MapGpsAction? recu;
      await tester.pumpWidget(
        _app(GpsStatusStrip(state: state, onAction: (a) => recu = a)),
      );

      expect(find.text(state.message), findsOneWidget);
      await tester.tap(find.text(label));
      expect(recu, action);
    });
  }

  testWidgets('recherche en cours : aucun bouton, et jamais « Acquisition »', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(GpsStatePlaceholder(state: MapGpsState.acquiring, onAction: (_) {})),
    );

    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('Acquisition'), findsNothing);
  });

  testWidgets('le placeholder propose le même geste que le bandeau', (
    tester,
  ) async {
    MapGpsAction? recu;
    await tester.pumpWidget(
      _app(
        GpsStatePlaceholder(
          state: MapGpsState.deniedForever,
          onAction: (a) => recu = a,
        ),
      ),
    );

    await tester.tap(find.text('Réglages'));
    expect(recu, MapGpsAction.openAppSettings);
  });
}
