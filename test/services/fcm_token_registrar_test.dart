import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http_mock_adapter/http_mock_adapter.dart';
import 'package:lilia_food_delivery/core/network/api_client.dart';
import 'package:lilia_food_delivery/services/fcm_token_registrar.dart';

/// Compte les requêtes réellement parties sur le réseau, par méthode + chemin.
class _CallCounter extends Interceptor {
  final List<String> calls = [];

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    calls.add('${options.method} ${options.path}');
    handler.next(options);
  }

  int countOf(String signature) => calls.where((c) => c == signature).length;
}

void main() {
  late _CallCounter counter;

  /// Construit un registrar branché sur un ApiClient réel dont seul l'adapter
  /// HTTP est simulé. Le backoff est neutralisé pour que les tests de retry
  /// n'attendent pas les 15s de production.
  FcmTokenRegistrar buildRegistrar(void Function(DioAdapter) stub) {
    final client = ApiClient.test(
      baseUrl: 'https://test.local',
      tokenProvider: () async => 'firebase-tok',
      forceRefreshToken: () async => 'firebase-tok2',
    );
    counter = _CallCounter();
    client.dio.interceptors.add(counter);
    stub(DioAdapter(dio: client.dio));
    return FcmTokenRegistrar(client, backoff: (_) => Duration.zero);
  }

  group('register', () {
    test('envoie le token sur /notifications/register-token', () async {
      final registrar = buildRegistrar((a) {
        a.onPost(
          '/notifications/register-token',
          (s) => s.reply(200, {'data': {'status': 'success'}}),
          data: {'token': 'fcm-abc'},
        );
      });

      await registrar.register('fcm-abc');

      expect(counter.countOf('POST /notifications/register-token'), 1);
      expect(registrar.token, 'fcm-abc');
    });

    test('réessaie jusqu\'à maxRetries quand le serveur échoue', () async {
      final registrar = buildRegistrar((a) {
        a.onPost(
          '/notifications/register-token',
          (s) => s.reply(500, {'message': 'boom'}),
          data: {'token': 'fcm-abc'},
        );
      });

      await registrar.register('fcm-abc', maxRetries: 3);

      expect(counter.countOf('POST /notifications/register-token'), 3);
    });

    test('n\'expose pas le token quand toutes les tentatives échouent',
        () async {
      final registrar = buildRegistrar((a) {
        a.onPost(
          '/notifications/register-token',
          (s) => s.reply(500, {'message': 'boom'}),
          data: {'token': 'fcm-abc'},
        );
      });

      await registrar.register('fcm-abc', maxRetries: 2);

      expect(registrar.token, isNull);
    });
  });

  group('remove', () {
    test('supprime le token côté serveur puis l\'oublie', () async {
      final registrar = buildRegistrar((a) {
        a.onPost(
          '/notifications/register-token',
          (s) => s.reply(200, {'data': {'status': 'success'}}),
          data: {'token': 'fcm-abc'},
        );
        a.onDelete(
          '/notifications/token',
          (s) => s.reply(200, {'data': null}),
          data: {'token': 'fcm-abc'},
        );
      });
      await registrar.register('fcm-abc');

      await registrar.remove();

      expect(counter.countOf('DELETE /notifications/token'), 1);
      expect(registrar.token, isNull);
    });

    test('ne fait aucun appel réseau si aucun token n\'est enregistré',
        () async {
      final registrar = buildRegistrar((_) {});

      await registrar.remove();

      expect(counter.calls, isEmpty);
    });

    test('oublie le token même si le serveur refuse la suppression', () async {
      final registrar = buildRegistrar((a) {
        a.onPost(
          '/notifications/register-token',
          (s) => s.reply(200, {'data': {'status': 'success'}}),
          data: {'token': 'fcm-abc'},
        );
        a.onDelete(
          '/notifications/token',
          (s) => s.reply(401, {'message': 'expiré'}),
          data: {'token': 'fcm-abc'},
        );
      });
      await registrar.register('fcm-abc');

      await registrar.remove();

      expect(registrar.token, isNull);
    });
  });

  group('session', () {
    test('beginSession refuse une seconde ouverture tant que la session dure',
        () {
      final registrar = buildRegistrar((_) {});

      expect(registrar.beginSession(), isTrue);
      expect(registrar.beginSession(), isFalse);
    });

    // Régression : au logout le livreur purgeait son token mais la garde
    // d'initialisation restait armée. Une reconnexion dans la même session
    // d'app ne réenregistrait alors plus aucun token — plus aucune mission
    // ne remontait jusqu'au redémarrage complet de l'app.
    test('remove réarme la session pour permettre une reconnexion', () async {
      final registrar = buildRegistrar((a) {
        a.onPost(
          '/notifications/register-token',
          (s) => s.reply(200, {'data': {'status': 'success'}}),
          data: {'token': 'fcm-abc'},
        );
        a.onDelete(
          '/notifications/token',
          (s) => s.reply(200, {'data': null}),
          data: {'token': 'fcm-abc'},
        );
      });
      registrar.beginSession();
      await registrar.register('fcm-abc');

      await registrar.remove();

      expect(registrar.beginSession(), isTrue);
    });
  });
}
