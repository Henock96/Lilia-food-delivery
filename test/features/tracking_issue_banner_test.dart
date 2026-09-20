import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/features/deliveries/application/location_service.dart';
import 'package:lilia_food_delivery/features/deliveries/application/tracking_issue.dart';
import 'package:lilia_food_delivery/features/deliveries/presentation/widgets/tracking_issue_banner.dart';

/// Le bandeau « le client ne vous voit pas ».
///
/// Il est monté au-dessus du routeur pour survivre à la navigation : le livreur
/// passe sa course sur l'écran de détail, poussé par-dessus les onglets. Ces
/// tests vérifient les trois propriétés dont dépend son utilité — il n'apparaît
/// que quand il faut, il propose l'action qui correspond au motif, et il ne
/// masque jamais l'écran en dessous.
void main() {
  Widget harness(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: const TrackingIssueBanner(
        child: Scaffold(body: Center(child: Text('contenu de l’écran'))),
      ),
    ),
  );

  testWidgets('reste invisible quand le suivi fonctionne', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container));

    expect(find.text('Le client ne vous voit pas'), findsNothing);
    expect(find.text('contenu de l’écran'), findsOneWidget);
  });

  testWidgets('apparaît sans masquer l’écran en dessous', (tester) async {
    // Le point important : c'est un bandeau, pas une modale. Le livreur doit
    // pouvoir continuer sa course — et surtout atteindre « Marquer comme
    // livrée » — pendant que l'alerte est affichée.
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(harness(container));

    container
        .read(trackingIssueControllerProvider.notifier)
        .report(
          const LocationPermissionResult(
            granted: false,
            reason: LocationDenialReason.serviceDisabled,
          ),
        );
    await tester.pump();

    expect(find.text('Le client ne vous voit pas'), findsOneWidget);
    expect(find.text('contenu de l’écran'), findsOneWidget);
  });

  testWidgets('propose « Activer » quand la localisation est éteinte', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    container
        .read(trackingIssueControllerProvider.notifier)
        .report(
          const LocationPermissionResult(
            granted: false,
            reason: LocationDenialReason.serviceDisabled,
          ),
        );
    await tester.pump();

    // Redemander l'autorisation applicative ne servirait à rien : c'est le GPS
    // de l'appareil qui est coupé.
    expect(find.text('Activer'), findsOneWidget);
  });

  testWidgets('renvoie vers les réglages après un refus définitif', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    container
        .read(trackingIssueControllerProvider.notifier)
        .report(
          const LocationPermissionResult(
            granted: false,
            reason: LocationDenialReason.deniedForever,
          ),
        );
    await tester.pump();

    // Android et iOS ne réaffichent plus la demande après un refus définitif :
    // proposer « Autoriser » mènerait à un bouton sans effet.
    expect(find.text('Réglages'), findsOneWidget);
  });

  testWidgets('disparaît de lui-même quand le suivi repart', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    final notifier = container.read(trackingIssueControllerProvider.notifier);
    notifier.report(
      const LocationPermissionResult(
        granted: false,
        reason: LocationDenialReason.denied,
      ),
    );
    await tester.pump();
    expect(find.text('Le client ne vous voit pas'), findsOneWidget);

    notifier.clear();
    await tester.pump();

    expect(find.text('Le client ne vous voit pas'), findsNothing);
  });

  testWidgets('n’offre aucun bouton de fermeture', (tester) async {
    // Délibéré : la cause dure tant qu'elle n'est pas traitée. Un bandeau qu'on
    // peut écarter finit écarté, et l'on retrouve la panne silencieuse que ce
    // bandeau existe précisément pour rendre visible.
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(harness(container));

    container
        .read(trackingIssueControllerProvider.notifier)
        .report(
          const LocationPermissionResult(
            granted: false,
            reason: LocationDenialReason.denied,
          ),
        );
    await tester.pump();

    expect(find.byIcon(Icons.close), findsNothing);
  });
}
