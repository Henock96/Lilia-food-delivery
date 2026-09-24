import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/core/network/api_exception.dart';
import 'package:lilia_food_delivery/features/auth/application/session_guard.dart';

/// Compte supprimé pendant que le téléphone gardait sa session (bug du
/// 24/09/2026) : ces refus déconnectent, les autres non.
void main() {
  test('401 : session refusée', () {
    expect(
      refusesSession(
        const ApiException(
          'x',
          statusCode: 401,
          kind: ApiErrorKind.unauthorized,
        ),
      ),
      isTrue,
    );
  });

  test('403 ACCOUNT_NOT_SYNCED et ACCOUNT_REVOKED : session refusée', () {
    for (final code in ['ACCOUNT_NOT_SYNCED', 'ACCOUNT_REVOKED']) {
      expect(
        refusesSession(
          ApiException(
            'x',
            statusCode: 403,
            kind: ApiErrorKind.client,
            code: code,
          ),
        ),
        isTrue,
      );
    }
  });

  test('serveur antérieur au code : reconnu par le message', () {
    expect(
      refusesSession(
        const ApiException(
          'Compte non synchronisé. Appelez POST /users/sync avant cette action.',
          statusCode: 403,
          kind: ApiErrorKind.client,
        ),
      ),
      isTrue,
    );
  });

  test('un 403 ordinaire, une panne : la session tient', () {
    expect(
      refusesSession(
        const ApiException(
          'Accès refusé',
          statusCode: 403,
          kind: ApiErrorKind.client,
        ),
      ),
      isFalse,
    );
    expect(
      refusesSession(
        const ApiException('Panne', statusCode: 500, kind: ApiErrorKind.server),
      ),
      isFalse,
    );
  });
}
