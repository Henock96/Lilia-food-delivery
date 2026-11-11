import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/features/deliveries/application/dispatch_capability.dart';

void main() {
  var now = DateTime(2026, 11, 10, 8);
  late int calls;
  late bool fail;

  DispatchCapabilityDeclarer build() {
    calls = 0;
    fail = false;
    now = DateTime(2026, 11, 10, 8);
    return DispatchCapabilityDeclarer(
      declare: () async {
        calls++;
        if (fail) throw Exception('réseau');
      },
      minInterval: const Duration(minutes: 30),
      now: () => now,
    );
  }

  test('la première déclaration part, la suivante attend 30 min', () async {
    final d = build();
    expect(await d.declare(), isTrue);
    expect(await d.declare(), isFalse);
    now = now.add(const Duration(minutes: 29));
    expect(await d.declare(), isFalse);
    now = now.add(const Duration(minutes: 2));
    expect(await d.declare(), isTrue);
    expect(calls, 2);
  });

  test('force (connexion) ignore la cadence', () async {
    final d = build();
    await d.declare();
    expect(await d.declare(force: true), isTrue);
    expect(calls, 2);
  });

  test('un échec ne compte pas : on réessaie à la prochaine occasion', () async {
    final d = build();
    fail = true;
    expect(await d.declare(), isFalse);
    expect(d.lastSuccess, isNull);
    fail = false;
    expect(await d.declare(), isTrue);
  });

  test('reset (déconnexion) rouvre la déclaration', () async {
    final d = build();
    await d.declare();
    d.reset();
    expect(await d.declare(), isTrue);
    expect(calls, 2);
  });
}
