import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_client.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/deliveries_controller.dart';
import 'package:lilia_food_delivery/features/deliveries/application/missions_sync.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:lilia_food_delivery/features/profile/application/profile_controller.dart';
import 'package:lilia_food_delivery/models/app_user.dart';
import 'package:lilia_food_delivery/models/delivery.dart';

/// Minuteur simulé : on déclenche les cycles à la main.
class _FakeTimer implements Timer {
  _FakeTimer(this._onTick);
  final void Function(Timer) _onTick;
  bool cancelled = false;
  int _ticks = 0;

  void fire() {
    if (cancelled) return;
    _ticks++;
    _onTick(this);
  }

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => _ticks;
}

/// Serveur simulé : la liste des missions change sans aucun push.
class _FakeRepo extends DeliveryRepository {
  _FakeRepo()
    : super(
        ApiClient.test(
          baseUrl: 'http://test.invalid',
          tokenProvider: () async => null,
          forceRefreshToken: () async => null,
        ),
      );

  List<Delivery> missions = [];
  bool down = false;
  int calls = 0;
  String driverStatus = 'AVAILABLE';

  @override
  Future<AppUser> getMe() async => AppUser.fromJson({
    'id': 'u1',
    'role': 'LIVREUR',
    'driverStatus': driverStatus,
  });

  @override
  Future<List<Delivery>> getMyMissions() async {
    calls++;
    if (down) {
      throw const ApiException('Serveur injoignable', kind: ApiErrorKind.network);
    }
    return missions;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<_FakeTimer> timers;
  late DriverStatus? status;
  late int refreshes;
  late int profileRefreshes;

  MissionsSync build({Future<void> Function()? refresh}) {
    timers = [];
    refreshes = 0;
    profileRefreshes = 0;
    final sync = MissionsSync(
      refresh:
          refresh ??
          () async {
            refreshes++;
          },
      refreshProfile: () => profileRefreshes++,
      driverStatus: () => status,
      periodic: (period, tick) {
        expect(period, const Duration(seconds: 60));
        final t = _FakeTimer(tick);
        timers.add(t);
        return t;
      },
    );
    addTearDown(sync.stop);
    return sync;
  }

  _FakeTimer? live() =>
      timers.where((t) => !t.cancelled).isEmpty
          ? null
          : timers.lastWhere((t) => !t.cancelled);

  setUp(() => status = DriverStatus.available);

  test('AVAILABLE, aucun push : le polling fait apparaître la mission', () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [deliveryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.listen(missionsControllerProvider, (_, _) {});
    await container.read(missionsControllerProvider.future);
    expect(container.read(missionsControllerProvider).value, isEmpty);

    final sync = build(
      refresh: () async {
        await container
            .read(missionsControllerProvider.notifier)
            .syncSilently();
      },
    )..start();

    // Le vendeur assigne une course ; le push se perd.
    repo.missions = [
      Delivery.fromJson({'id': 'd1', 'orderId': 'o1', 'status': 'ASSIGNER'}),
    ];
    live()!.fire();
    await Future<void>.delayed(Duration.zero);

    expect(sync.isPolling, isTrue);
    final shown = container.read(missionsControllerProvider).value!;
    expect(shown.map((d) => d.id), ['d1']);
  });

  test('arrière-plan : aucun polling', () {
    final sync = build()..start();
    expect(sync.isPolling, isTrue);

    sync.didChangeAppLifecycleState(AppLifecycleState.inactive);
    expect(sync.isPolling, isTrue, reason: 'inactive = encore à l’écran');

    sync.didChangeAppLifecycleState(AppLifecycleState.hidden);
    sync.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(sync.isPolling, isFalse);
    expect(timers.single.cancelled, isTrue);
    timers.single.fire(); // un minuteur annulé ne déclenche plus rien
    expect(refreshes, 0);
  });

  test('retour au premier plan : relecture immédiate, missions et profil', () {
    final sync = build()..start();
    sync.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(refreshes, 0);

    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(refreshes, 1, reason: 'sans attendre le prochain cycle');
    expect(profileRefreshes, 1);
    expect(sync.isPolling, isTrue);
  });

  test('OFFLINE : ni polling, ni relecture au retour', () {
    status = DriverStatus.offline;
    final sync = build()..start();
    expect(sync.isPolling, isFalse);

    sync.didChangeAppLifecycleState(AppLifecycleState.paused);
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(refreshes, 0);
    expect(sync.isPolling, isFalse);
    expect(timers, isEmpty);
  });

  test('en course : pas de polling ; redevenu disponible : il reprend', () {
    status = DriverStatus.on_delivery;
    final sync = build()..start();
    expect(sync.isPolling, isFalse);

    status = DriverStatus.available; // course livrée, profil relu
    sync.evaluate();
    expect(sync.isPolling, isTrue);

    status = DriverStatus.offline;
    sync.evaluate();
    expect(sync.isPolling, isFalse);
  });

  test('un seul minuteur, quel que soit le nombre de réévaluations', () {
    final sync = build()..start();
    for (var i = 0; i < 5; i++) {
      sync.evaluate();
    }
    sync.didChangeAppLifecycleState(AppLifecycleState.inactive);
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(timers.where((t) => !t.cancelled), hasLength(1));
  });

  test('profil pas encore chargé : on relit au retour, sans polling', () {
    status = null;
    final sync = build()..start();
    expect(sync.isPolling, isFalse);
    sync.didChangeAppLifecycleState(AppLifecycleState.paused);
    sync.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(refreshes, 1);
  });

  test('relecture de fond en échec : la liste affichée reste', () async {
    final repo = _FakeRepo()
      ..missions = [
        Delivery.fromJson({'id': 'd1', 'orderId': 'o1', 'status': 'ASSIGNER'}),
      ];
    final container = ProviderContainer(
      overrides: [deliveryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    container.listen(missionsControllerProvider, (_, _) {});
    await container.read(missionsControllerProvider.future);

    repo.down = true;
    final ok = await container
        .read(missionsControllerProvider.notifier)
        .syncSilently();

    expect(ok, isFalse);
    final state = container.read(missionsControllerProvider);
    expect(state.hasError, isFalse);
    expect(state.value!.map((d) => d.id), ['d1']);
  });

  test('câblage réel : le statut du profil allume et éteint le polling',
      () async {
    final repo = _FakeRepo();
    final container = ProviderContainer(
      overrides: [deliveryRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final sync = container.read(missionsSyncProvider);
    await container.read(profileControllerProvider.future);
    sync.start();
    expect(sync.isPolling, isTrue, reason: 'AVAILABLE et visible');

    // Le livreur accepte : le serveur le passe ON_DELIVERY, le profil est relu.
    repo.driverStatus = 'ON_DELIVERY';
    container.invalidate(profileControllerProvider);
    await container.read(profileControllerProvider.future);
    expect(sync.isPolling, isFalse);

    // Course livrée : retour à AVAILABLE, le polling reprend seul.
    repo.driverStatus = 'AVAILABLE';
    container.invalidate(profileControllerProvider);
    await container.read(profileControllerProvider.future);
    expect(sync.isPolling, isTrue);
  });
}

