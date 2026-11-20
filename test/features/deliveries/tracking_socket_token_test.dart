// Le jeton de la socket de suivi doit être frais à CHAQUE connexion.
//
// Il était capturé une fois, à l'ouverture. Au bout d'une heure il expirait,
// la gateway coupait la socket (`io server disconnect`, que Socket.io ne
// relance pas), et le relais censé reconnecter n'agissait que sur une socket
// encore connectée. Le suivi WebSocket restait mort jusqu'à la fin de la
// course, masqué par le repli HTTP.

import 'package:flutter_test/flutter_test.dart';
import 'package:lilia_food_delivery/features/auth/data/auth_repository.dart';
import 'package:lilia_food_delivery/features/deliveries/application/tracking_socket_service.dart';
import 'package:socket_io_client/socket_io_client.dart' as sio;
// `onError` est une extension qui passe par `socket.io` (le gestionnaire), qui
// n'est pas réexporté.
// ignore: implementation_imports
import 'package:socket_io_client/src/manager.dart' show Manager;

/// Rend un jeton différent à chaque appel, comme Firebase après renouvellement.
class _FauxAuth implements AuthRepository {
  int appels = 0;
  bool connecte = true;

  @override
  Future<String?> getIdToken() async {
    if (!connecte) return null;
    appels++;
    return 'jeton-$appels';
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FauxManager implements Manager {
  @override
  dynamic Function() on(String event, dynamic handler) => () => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

class _FauxSocket implements sio.Socket {
  _FauxSocket(this.options);

  final Map<String, dynamic> options;
  bool connecte = false;
  int connexions = 0;
  int disposes = 0;
  final emis = <Object?>[];

  @override
  Manager io = _FauxManager();

  @override
  bool get connected => connecte;

  @override
  dynamic Function() on(String event, dynamic handler) => () => null;

  @override
  sio.Socket connect() {
    connexions++;
    return this;
  }

  @override
  sio.Socket emit(String event, [dynamic data]) {
    emis.add(data);
    return this;
  }

  @override
  void dispose() {
    disposes++;
    connecte = false;
  }

  /// Ce que Socket.io fait à chaque ouverture de transport : demander l'auth.
  Future<Map<dynamic, dynamic>> demanderAuth() async {
    final fn = options['auth'] as void Function(
      void Function(Map<dynamic, dynamic>),
    );
    Map<dynamic, dynamic>? recu;
    fn((auth) => recu = auth);
    await Future<void>.delayed(Duration.zero);
    return recu!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => this;
}

void main() {
  late _FauxAuth auth;
  late List<_FauxSocket> sockets;
  late DateTime maintenant;

  TrackingSocketService monter() {
    auth = _FauxAuth();
    sockets = [];
    maintenant = DateTime(2026, 11, 20, 12);
    return TrackingSocketService(
      auth,
      fabrique: (url, options) {
        final s = _FauxSocket(options);
        sockets.add(s);
        return s;
      },
      maintenant: () => maintenant,
    );
  }

  bool emettre(TrackingSocketService s) =>
      s.emitPosition(orderId: 'o1', lat: -4.26, lng: 15.28);

  test('chaque tentative de connexion relit le jeton auprès de Firebase',
      () async {
    final service = monter();
    await service.connect();

    final premier = await sockets.single.demanderAuth();
    // Reconnexion automatique de Socket.io, une heure plus tard.
    final second = await sockets.single.demanderAuth();

    expect(premier['token'], isNot(second['token']));
    expect(second['token'], startsWith('jeton-'));
  });

  test('jeton indisponible : le rappel est servi quand même, vide', () async {
    final service = monter();
    await service.connect();
    auth.connecte = false;

    final recu = await sockets.single.demanderAuth();

    expect(recu, {'token': ''});
  });

  test('socket tombée : une émission relance la connexion et part en HTTP',
      () async {
    final service = monter();
    await service.connect();
    sockets.single.connecte = false; // la gateway a coupé

    maintenant = maintenant.add(TrackingSocketService.delaiEntreRelances);
    expect(emettre(service), isFalse, reason: 'cette position part en HTTP');
    await Future<void>.delayed(Duration.zero);

    expect(sockets, hasLength(2), reason: 'une nouvelle socket est ouverte');
    expect(sockets.first.disposes, 1);
  });

  test('les relances sont plafonnées à une par délai', () async {
    final service = monter();
    await service.connect();
    sockets.single.connecte = false;

    for (var i = 0; i < 5; i++) {
      maintenant = maintenant.add(const Duration(seconds: 5));
      emettre(service);
      await Future<void>.delayed(Duration.zero);
    }
    expect(sockets, hasLength(1), reason: '25 s < délai : aucune relance');

    maintenant = maintenant.add(const Duration(seconds: 5));
    emettre(service);
    await Future<void>.delayed(Duration.zero);
    expect(sockets, hasLength(2));
  });

  // Revue ECC : la gateway fixe l'uid à la poignée de main. Un autre livreur
  // connecté sur le même téléphone publiait sous l'uid du précédent — refusé
  // par la gateway, alors que `emitPosition` rendait `true`.
  test('un autre compte ferme la socket ; la même session la garde', () async {
    final service = monter();
    service.onSessionChanged('livreur-a');
    await service.connect();
    sockets.single.connecte = true;

    service.onSessionChanged('livreur-a');
    expect(sockets.single.disposes, 0, reason: 'même session');

    service.onSessionChanged('livreur-b');
    expect(sockets.single.disposes, 1);
    expect(service.isConnected, isFalse);

    // La position suivante rouvre aussitôt, sans attendre le délai de relance.
    expect(emettre(service), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(sockets, hasLength(2));
  });

  test('déconnexion : la socket est fermée', () async {
    final service = monter();
    service.onSessionChanged('livreur-a');
    await service.connect();

    service.onSessionChanged(null);

    expect(sockets.single.disposes, 1);
  });

  test('socket connectée : la position part en WebSocket', () async {
    final service = monter();
    await service.connect();
    sockets.single.connecte = true;

    expect(emettre(service), isTrue);
    expect(sockets.single.emis, hasLength(1));
  });
}
