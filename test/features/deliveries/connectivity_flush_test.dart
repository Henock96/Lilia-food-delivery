import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_client.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/connectivity_watcher.dart';
import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Serveur simulé : enregistre les lots, échoue tant que [offline] est vrai.
class _FakeRepo extends DeliveryRepository {
  _FakeRepo()
    : super(
        ApiClient.test(
          baseUrl: 'http://test',
          tokenProvider: () async => null,
          forceRefreshToken: () async => null,
        ),
      );

  bool offline = false;
  Completer<void>? gate;
  final batches = <Map<String, dynamic>>[];

  @override
  Future<void> sendPositionsBatch(
    String orderId,
    List<Map<String, dynamic>> positions,
  ) async {
    if (gate != null) await gate!.future;
    if (offline) {
      throw const ApiException('hors ligne', kind: ApiErrorKind.network);
    }
    batches.add({'orderId': orderId, 'positions': positions});
  }
}

/// T09 / T24 — perte réseau pendant la course, puis retour du réseau.
///
/// Ces tests passent par le vrai `ConnectivityWatcher` : c'est lui qui, sur la
/// transition « hors ligne → en ligne », doit vider la file. Le contrat du
/// lot lui-même est couvert par `position_batch_flusher_test.dart`.
void main() {
  late ProviderContainer container;
  late _FakeRepo repo;
  late PositionQueueService queue;
  final t0 = DateTime.utc(2026, 10, 8, 12);

  QueuedPosition point(int s) => QueuedPosition(
    orderId: 'o-1',
    deliveryId: 'd-1',
    latitude: -4.26 + s / 10000,
    longitude: 15.24,
    accuracy: 8,
    recordedAt: t0.add(Duration(seconds: s)),
  );

  const none = [ConnectivityResult.none];
  const mobile = [ConnectivityResult.mobile];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    queue = PositionQueueService(await SharedPreferences.getInstance());
    repo = _FakeRepo();
    container = ProviderContainer(
      overrides: [
        deliveryRepositoryProvider.overrideWithValue(repo),
        positionQueueServiceProvider.overrideWith((ref) async => queue),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('T09+T24 : positions accumulées hors ligne, vidées au retour du réseau, '
      'puis une nouvelle position repart normalement', () async {
    final watcher = container.read(connectivityWatcherProvider);

    // Coupure : plusieurs positions s'accumulent.
    repo.offline = true;
    watcher.onConnectivityChanged(none);
    for (final s in [0, 5, 10]) {
      await queue.enqueue(point(s));
    }
    expect(queue.queuedCount, 3);

    // Réseau revenu : un seul lot, trié, et la file est vide.
    repo.offline = false;
    watcher.onConnectivityChanged(mobile);
    await watcher.flushQueue();
    expect(repo.batches, hasLength(1));
    final sent = repo.batches.single['positions'] as List;
    expect(sent.map((p) => p['timestamp']), [
      t0.millisecondsSinceEpoch,
      t0.add(const Duration(seconds: 5)).millisecondsSinceEpoch,
      t0.add(const Duration(seconds: 10)).millisecondsSinceEpoch,
    ]);
    expect(queue.queuedCount, 0);

    // Après le vidage, une nouvelle position mise en file repart seule.
    await queue.enqueue(point(20));
    await watcher.flushQueue();
    expect(repo.batches, hasLength(2));
    expect(repo.batches.last['positions'] as List, hasLength(1));
    expect(queue.queuedCount, 0);
  });

  test('retour réseau encore instable : rien n’est perdu, le prochain '
      'déclencheur termine le travail', () async {
    final watcher = container.read(connectivityWatcherProvider);
    watcher.onConnectivityChanged(none);
    await queue.enqueue(point(0));
    await queue.enqueue(point(5));

    repo.offline = true;
    watcher.onConnectivityChanged(mobile);
    await watcher.flushQueue();
    expect(queue.queuedCount, 2);

    repo.offline = false;
    await watcher.flushQueue();
    expect(queue.queuedCount, 0);
    expect(repo.batches, hasLength(1));
  });

  test('retour réseau et reprise de l’app simultanés : un seul envoi', () async {
    final watcher = container.read(connectivityWatcherProvider);
    await queue.enqueue(point(0));
    repo.gate = Completer<void>();

    final a = watcher.flushQueue();
    final b = watcher.flushQueue();
    repo.gate!.complete();
    await Future.wait([a, b]);

    expect(repo.batches, hasLength(1));
    expect(queue.queuedCount, 0);
  });

  test('en ligne → en ligne : pas de vidage déclenché', () async {
    final watcher = container.read(connectivityWatcherProvider);
    await queue.enqueue(point(0));
    watcher.onConnectivityChanged(mobile);
    watcher.onConnectivityChanged(mobile);
    await Future<void>.delayed(Duration.zero);
    expect(repo.batches, isEmpty);
    expect(queue.queuedCount, 1);
  });
}
