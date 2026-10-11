import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/position_batch_flusher.dart';
import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F3-12.1, gate R8 — la file hors ligne se vide, et ne boucle jamais.
///
/// Avant : le lot partait sans `orderId`, avec `latitude`/`recordedAt` ISO —
/// 400 à chaque envoi, file jamais vidée, rejouée à chaque retour réseau.
void main() {
  late PositionQueueService queue;
  final t0 = DateTime.utc(2026, 9, 28, 10);

  QueuedPosition at(
    int seconds, {
    String? orderId = 'o-1',
    double lat = -4.26,
  }) => QueuedPosition(
    orderId: orderId,
    deliveryId: 'd-${orderId ?? 'old'}',
    latitude: lat,
    longitude: 15.24,
    accuracy: 5,
    recordedAt: t0.add(Duration(seconds: seconds)),
  );

  /// Serveur simulé : enregistre chaque lot, répond selon [responses]
  /// (dans l'ordre ; `null` = 200).
  List<Map<String, dynamic>> sent = [];
  SendPositionBatch server(List<Object?> responses) {
    var i = 0;
    return (orderId, positions) async {
      sent.add({'orderId': orderId, 'positions': positions});
      final r = i < responses.length ? responses[i] : null;
      i++;
      if (r != null) throw r;
    };
  }

  const network = ApiException('hors ligne', kind: ApiErrorKind.network);
  const badRequest = ApiException(
    'contrat',
    statusCode: 400,
    kind: ApiErrorKind.client,
  );
  const forbidden = ApiException(
    'réassigné',
    statusCode: 403,
    kind: ApiErrorKind.client,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    queue = PositionQueueService(await SharedPreferences.getInstance());
    sent = [];
  });

  test('hors ligne → file → réseau revenu → lot accepté → file vide', () async {
    await queue.enqueue(at(0));
    await queue.enqueue(at(5));
    final report = await PositionBatchFlusher(
      queue: queue,
      send: server([]),
    ).flush();
    expect(report.sent, 2);
    expect(queue.queuedCount, 0);
    expect(sent, hasLength(1));
    expect(sent.single['orderId'], 'o-1');
  });

  test(
    'retry : 1er envoi en panne réseau, 2e OK — file vidée, sans doublon',
    () async {
      await queue.enqueue(at(0));
      final send = server([network]);
      final first = await PositionBatchFlusher(
        queue: queue,
        send: send,
      ).flush();
      expect(first.stoppedOnTransientError, isTrue);
      expect(queue.queuedCount, 1);

      await PositionBatchFlusher(queue: queue, send: send).flush();
      expect(queue.queuedCount, 0);
      expect(sent, hasLength(2));
      expect(sent[0], sent[1]); // le même lot, rejoué une fois
    },
  );

  test('4xx permanent (400 puis 403) : file vidée, aucune boucle', () async {
    await queue.enqueue(at(0, orderId: 'o-1'));
    await queue.enqueue(at(1, orderId: 'o-2'));
    final report = await PositionBatchFlusher(
      queue: queue,
      send: server([badRequest, forbidden]),
    ).flush();
    expect(report.dropped, 2);
    expect(queue.queuedCount, 0);

    // Un nouveau déclencheur n'envoie plus rien.
    await PositionBatchFlusher(queue: queue, send: server([])).flush();
    expect(sent, hasLength(2));
  });

  test(
    'multi-courses : un lot par orderId, points triés par heure de relevé',
    () async {
      await queue.enqueue(at(10, orderId: 'o-1', lat: -4.10));
      await queue.enqueue(at(3, orderId: 'o-2'));
      await queue.enqueue(at(0, orderId: 'o-1', lat: -4.00));
      await PositionBatchFlusher(queue: queue, send: server([])).flush();

      expect(sent.map((b) => b['orderId']), ['o-1', 'o-2']);
      final o1 = sent.first['positions'] as List<Map<String, dynamic>>;
      expect(o1.map((p) => p['lat']), [-4.00, -4.10]);
    },
  );

  test(
    'entrées héritées sans orderId : abandonnées, jamais envoyées',
    () async {
      await queue.enqueue(at(0, orderId: null));
      await queue.enqueue(at(1));
      final report = await PositionBatchFlusher(
        queue: queue,
        send: server([]),
      ).flush();
      expect(report.dropped, 1);
      expect(sent, hasLength(1));
      expect(queue.queuedCount, 0);
    },
  );

  test(
    'panne passagère sur un lot : les suivants attendent, rien n’est perdu',
    () async {
      await queue.enqueue(at(0, orderId: 'o-1'));
      await queue.enqueue(at(1, orderId: 'o-2'));
      await PositionBatchFlusher(queue: queue, send: server([network])).flush();
      expect(sent, hasLength(1));
      expect(queue.queuedCount, 2);
    },
  );

  test('lots découpés à chunkSize', () async {
    for (var i = 0; i < 5; i++) {
      await queue.enqueue(at(i));
    }
    await PositionBatchFlusher(
      queue: queue,
      send: server([]),
      chunkSize: 2,
    ).flush();
    expect(sent.map((b) => (b['positions'] as List).length), [2, 2, 1]);
    expect(queue.queuedCount, 0);
  });

  test('une position arrivée pendant l’envoi n’est pas effacée', () async {
    await queue.enqueue(at(0));
    final report = await PositionBatchFlusher(
      queue: queue,
      send: (orderId, positions) async {
        sent.add({'orderId': orderId});
        await queue.enqueue(at(99, orderId: 'o-9'));
      },
    ).flush();
    expect(report.sent, 1);
    expect(queue.queuedCount, 1);
    expect(queue.readEntries().single.position!.orderId, 'o-9');
  });

  /// Contrat partagé avec le backend : `lilia-backend` valide LE MÊME fichier
  /// avec `BatchPositionsDto` (`tracking-batch.contract.spec.ts`). Un champ
  /// renommé d'un côté casse l'un des deux tests.
  test('contrat : le corps produit est exactement le fixture v1', () async {
    final fixture =
        jsonDecode(
              File(
                'test/contract/tracking_position_batch.v1.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final base = DateTime.fromMillisecondsSinceEpoch(
      1790000000000,
      isUtc: true,
    );
    await queue.enqueue(
      QueuedPosition(
        orderId: 'order-contract-1',
        deliveryId: 'd-contract',
        latitude: -4.2634,
        longitude: 15.2429,
        accuracy: 8.5,
        recordedAt: base,
      ),
    );
    await queue.enqueue(
      QueuedPosition(
        orderId: 'order-contract-1',
        deliveryId: 'd-contract',
        latitude: -4.2641,
        longitude: 15.2437,
        recordedAt: base.add(const Duration(seconds: 5)),
      ),
    );
    await PositionBatchFlusher(queue: queue, send: server([])).flush();
    expect(jsonDecode(jsonEncode(sent.single)), fixture);
  });
}
