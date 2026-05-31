import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

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

  /// Flush en boucle par batches de 50 tant qu'il reste des positions
  /// ET que le serveur répond OK. Public pour pouvoir être appelé depuis
  /// TrackingResumeService au resume foreground (ceinture+bretelles).
  Future<void> flushQueue() async {
    final queue = await _ref.read(positionQueueServiceProvider.future);
    final repo = _ref.read(deliveryRepositoryProvider);

    while (queue.queuedCount > 0) {
      final batch = await queue.drainBatch(50);
      if (batch.isEmpty) break;
      final ok = await repo.sendPositionsBatch(
        batch.map((p) => p.toJson()).toList(),
      );
      if (!ok) {
        debugPrint('📡 Batch send failed, will retry next trigger');
        break;
      }
      await queue.markFlushed(batch.length);
    }
  }
}

@Riverpod(keepAlive: true)
ConnectivityWatcher connectivityWatcher(Ref ref) {
  final w = ConnectivityWatcher(ref);
  ref.onDispose(w.stop);
  return w;
}
