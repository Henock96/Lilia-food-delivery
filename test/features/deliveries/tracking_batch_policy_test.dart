import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/deliveries/application/tracking_batch_policy.dart';

void main() {
  ApiException status(int code, ApiErrorKind kind) =>
      ApiException('x', statusCode: code, kind: kind);

  group('classifyTrackingError — garder ou abandonner un lot', () {
    test('pannes passagères : gardé', () {
      for (final e in [
        const ApiException('x', kind: ApiErrorKind.network),
        const ApiException('x', kind: ApiErrorKind.timeout),
        status(500, ApiErrorKind.server),
        status(503, ApiErrorKind.server),
        status(408, ApiErrorKind.client),
        status(429, ApiErrorKind.client),
        status(401, ApiErrorKind.unauthorized),
        StateError('bogue local'),
      ]) {
        expect(
          classifyTrackingError(e),
          BatchFailureAction.retryLater,
          reason: '$e',
        );
      }
    });

    test('refus définitifs : abandonné', () {
      for (final code in [400, 403, 404, 409, 422]) {
        expect(
          classifyTrackingError(status(code, ApiErrorKind.client)),
          BatchFailureAction.drop,
          reason: '$code',
        );
      }
    });
  });

  test('un PATCH de position refusé en 4xx n’entre pas dans la file', () {
    expect(
      shouldQueueFailedPosition(status(400, ApiErrorKind.client)),
      isFalse,
    );
    expect(
      shouldQueueFailedPosition(status(403, ApiErrorKind.client)),
      isFalse,
    );
    expect(
      shouldQueueFailedPosition(
        const ApiException('x', kind: ApiErrorKind.network),
      ),
      isTrue,
    );
  });
}
