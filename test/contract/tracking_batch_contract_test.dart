import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:lilia_food_delivery/core/network/api_client.dart';
import 'package:lilia_food_delivery/features/deliveries/application/position_batch_flusher.dart';
import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// F3-12.1, gate R8 — test de CONTRAT, de la file jusqu'au fil.
///
/// Le corps capturé est celui que Dio émet réellement (vrai
/// `DeliveryRepository`, vrai `ApiClient`), comparé au fixture
/// `tracking_position_batch.v1.json`. Le backend valide le même fichier avec
/// `BatchPositionsDto` : un champ renommé ou retiré de l'un ou l'autre côté
/// casse l'un des deux tests.
///
/// ⚠️ Deux copies du fixture (une par dépôt) : les modifier ENSEMBLE.
void main() {
  test(
    'POST /tracking/position/batch : le corps émis est le fixture v1',
    () async {
      final fixture = jsonDecode(
        File(
          'test/contract/tracking_position_batch.v1.json',
        ).readAsStringSync(),
      );

      final client = ApiClient.test(
        baseUrl: 'https://test.local',
        tokenProvider: () async => 'tok',
        forceRefreshToken: () async => 'tok2',
      );
      Object? emitted;
      String? path;
      client.dio.interceptors.insert(
        0,
        InterceptorsWrapper(
          onRequest: (options, handler) {
            emitted = options.data;
            path = options.path;
            handler.next(options);
          },
        ),
      );
      DioAdapter(dio: client.dio).onPost(
        '/tracking/position/batch',
        (s) => s.reply(200, {
          'data': {'synced': 2, 'eta': null},
        }),
        data: Matchers.any,
      );

      SharedPreferences.setMockInitialValues({});
      final queue = PositionQueueService(await SharedPreferences.getInstance());
      final base = DateTime.fromMillisecondsSinceEpoch(
        1790000000000,
        isUtc: true,
      );
      // Enfilées dans le désordre : le lot sort trié.
      await queue.enqueue(
        QueuedPosition(
          orderId: 'order-contract-1',
          deliveryId: 'd-contract',
          latitude: -4.2641,
          longitude: 15.2437,
          recordedAt: base.add(const Duration(seconds: 5)),
        ),
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

      final report = await PositionBatchFlusher(
        queue: queue,
        send: DeliveryRepository(client).sendPositionsBatch,
      ).flush();

      expect(path, '/tracking/position/batch');
      expect(jsonDecode(jsonEncode(emitted)), fixture);
      expect(report.sent, 2);
      expect(queue.queuedCount, 0);
    },
  );
}
