import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:lilia_food_delivery/features/deliveries/application/position_batch_flusher.dart';
import 'package:lilia_food_delivery/features/deliveries/application/position_queue_service.dart';
import 'package:lilia_food_delivery/features/deliveries/data/delivery_repository.dart';

part 'connectivity_watcher.g.dart';

/// Observe les transitions réseau et flush la file des positions GPS
/// dès que la connexion revient (none → wifi/mobile).
class ConnectivityWatcher {
  ConnectivityWatcher(this._ref);

  final Ref _ref;
  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _wasOffline = false;

  void start() {
    _sub?.cancel();
    _sub = Connectivity().onConnectivityChanged.listen(_onChange);
    debugPrint('📡 ConnectivityWatcher started');
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onChange(List<ConnectivityResult> results) {
    final isOnline = results.any(
      (r) => r == ConnectivityResult.wifi || r == ConnectivityResult.mobile,
    );
    if (_wasOffline && isOnline) {
      debugPrint('📡 Réseau revenu → flush position queue');
      unawaited(flushQueue());
    }
    _wasOffline = !isOnline;
  }

  Future<void>? _inFlight;

  /// Vide la file des positions hors ligne. Public pour pouvoir être appelé
  /// depuis TrackingResumeService au resume foreground (ceinture+bretelles).
  ///
  /// Un seul vidage à la fois : retour réseau et reprise de l'app arrivent
  /// souvent ensemble, et deux vidages parallèles enverraient deux fois les
  /// mêmes positions.
  Future<void> flushQueue() => _inFlight ??= _flush().whenComplete(() {
        _inFlight = null;
      });

  Future<void> _flush() async {
    final queue = await _ref.read(positionQueueServiceProvider.future);
    final repo = _ref.read(deliveryRepositoryProvider);
    final report = await PositionBatchFlusher(
      queue: queue,
      send: repo.sendPositionsBatch,
    ).flush();
    debugPrint(
      '📡 Flush positions : ${report.sent} envoyée(s), ${report.dropped} '
      'abandonnée(s), ${report.batches} lot(s)'
      '${report.stoppedOnTransientError ? ' — reprise au prochain déclencheur' : ''}',
    );
  }
}

@Riverpod(keepAlive: true)
ConnectivityWatcher connectivityWatcher(Ref ref) {
  final w = ConnectivityWatcher(ref);
  ref.onDispose(w.stop);
  return w;
}
